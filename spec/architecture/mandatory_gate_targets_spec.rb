# frozen_string_literal: true

require "rails_helper"
require "yaml"
require "shellwords"

# EVERY MANDATORY GATE MUST RESOLVE TO SOMETHING THAT RUNS (FU-45).
#
# WHAT WENT WRONG, AND FOR HOW LONG. `VERIFICATION_MANIFEST.yml` declared `controller_crash_recovery`
# and `controller_locking` mandatory, naming `spec/automation/crash_recovery` and
# `spec/automation/locking`. NEITHER PATH HAD EVER EXISTED — not at the commit that introduced the
# entries, not at any commit since. Both gates therefore reported failure only if someone ran them
# individually, and every acceptance this repository has made was granted with two mandatory gates
# silently absent. `controller_locking`'s subject was partly covered elsewhere by accident of naming;
# `controller_crash_recovery` had NO coverage anywhere.
#
# WHY A DECLARATION CHECK RATHER THAN A CONVENTION. The failure mode is not that someone wrote a bad
# gate — it is that a gate can name nothing and produce no signal. `rspec` on a missing directory
# aborts with an error OUTSIDE any example, which an aggregate suite run does not surface, so the
# absence looked exactly like success. This makes the declaration itself the thing under test.
RSpec.describe "mandatory verification gate targets", type: :architecture do
  MANIFEST = YAML.load_file(Rails.root.join("specification/automation/VERIFICATION_MANIFEST.yml")).freeze

  # EVERY MANDATORY CHECK, WHEREVER IT SITS IN THE DOCUMENT.
  #
  # The first version collected only entries nested under a `"checks"` key, which left the six under
  # `check_sets.always_required` — `repository_cleanliness`, `complete_test_suite`, `brakeman`,
  # `packwerk`, `bundler_audit`, `zeitwerk` — ungoverned. Two of them were pointed at a nonexistent
  # binary and a nonexistent spec path and this gate still reported 14 examples, 0 failures. That is
  # FU-45's own defect class reproduced inside the gate written to close FU-45.
  #
  # A check is now anything that DECLARES ITSELF ONE: a Hash carrying an `id`, a `command` and
  # `mandatory`. Nothing about where it lives in the tree decides whether it is examined.
  def self.mandatory_checks(node, found = [])
    case node
    when Hash
      found << node if node["id"] && node["command"] && node["mandatory"]
      node.each_value { |v| mandatory_checks(v, found) }
    when Array then node.each { |v| mandatory_checks(v, found) }
    end
    found.uniq { |c| c["id"] }
  end

  CHECKS = mandatory_checks(MANIFEST).freeze
  # Every id the document marks mandatory, derived by walking the same tree for the flag alone — an
  # independent count of what SHOULD be governed, so a walker that misses a nesting shape is caught.
  def self.all_mandatory_ids(node, found = [])
    case node
    when Hash
      found << node["id"] if node["id"] && node["mandatory"]
      node.each_value { |v| all_mandatory_ids(v, found) }
    when Array then node.each { |v| all_mandatory_ids(v, found) }
    end
    found.compact.uniq
  end
  MANDATORY_IDS = all_mandatory_ids(MANIFEST).freeze

  # Every executable a command invokes: the leading program, and the tool `bundle exec` runs. A
  # compound command (`a && b`) contributes each side.
  def self.executables(command)
    command.split(/&&|\|\|/).filter_map do |part|
      tokens = part.split.reject { |t| t.start_with?("-") }
      next if tokens.empty?

      tokens.first == "bundle" && tokens[1] == "exec" ? tokens[2] : tokens.first
    end.uniq
  end

  def self.resolves?(binary)
    return true if binary.nil?
    return File.executable?(Rails.root.join(binary)) if binary.start_with?("bin/")

    system("command -v #{Shellwords.escape(binary)} > /dev/null 2>&1") ||
      File.exist?(Rails.root.join("bin", binary)) ||
      !`bundle exec which #{Shellwords.escape(binary)} 2>/dev/null`.strip.empty?
  end

  def executables(command) = self.class.executables(command)
  def resolves?(binary) = self.class.resolves?(binary)

  it "examines EVERY mandatory check the manifest declares" do
    # THE FLOOR IS THE DOCUMENT'S OWN COUNT, not a number written here. `>= 15` against 19 actual is
    # a hardcoded enumeration floor — four gates could be deleted outright, or flipped to
    # `mandatory: false`, and it would still hold. And the guard that was supposed to catch that
    # compared `MANIFEST.to_s` (a Ruby Hash inspect, `{"id" => "x"}`) against `"id: x"`, which is
    # false for every id, so it could never fail. Both are replaced by comparing two independent
    # walks of the same tree.
    expect(MANDATORY_IDS).not_to be_empty, "the manifest declares no mandatory checks"
    expect(CHECKS.map { |c| c["id"] }.sort).to eq(MANDATORY_IDS.sort),
                                              "mandatory checks this gate never examines: " \
                                              "#{(MANDATORY_IDS - CHECKS.map { |c| c['id'] }).join(', ')}"
  end

  CHECKS.each do |check|
    id = check["id"]
    command = check["command"].to_s

    it "#{id} — its target exists and can execute" do
      # RSPEC TARGETS: the path must exist AND contain at least one example. A directory that exists
      # but holds no spec passes `rspec` with "0 examples, 0 failures" — a green result from a gate
      # that examined nothing, which is the same defect one level along.
      if command.start_with?("bundle exec rspec")
        targets = command.sub("bundle exec rspec", "").split.reject { |t| t.start_with?("-") }
        targets = ["spec"] if targets.empty?
        targets.each do |target|
          path = Rails.root.join(target.split(":").first)
          expect(path).to exist, "#{id} names #{target}, which does not exist, so the gate cannot run"

          files = path.directory? ? Dir[path.join("**/*_spec.rb")] : [path.to_s]
          expect(files).not_to be_empty, "#{id} names #{target}, which contains no spec files"
          examples = files.sum { |f| File.read(f).scan(/^\s*(?:it|scenario|specify)\b/).length }
          expect(examples).to be_positive,
                              "#{id} names #{target}, which defines ZERO examples; the gate would " \
                              "report success having examined nothing"
        end
      else
        # EXECUTABLE TARGETS: every executable the command invokes must resolve.
        #
        # The first version skipped anything not starting with `bin/`, so the three mandatory checks
        # whose command begins with neither `bundle exec rspec` nor `bin/` — `repository_cleanliness`
        # (`git ...`), `brakeman` and `bundler_audit` (`bundle exec ...`) — had an example titled
        # "its target exists and can execute" that ASSERTED NOTHING. Pointing all three at
        # nonexistent binaries left this gate at 20 examples, 0 failures.
        executables(command).each do |binary|
          if binary.start_with?("bin/")
            path = Rails.root.join(binary)
            expect(path).to exist, "#{id} runs #{binary}, which does not exist"
            expect(File.executable?(path)).to be(true), "#{id} runs #{binary}, which is not executable"
          else
            expect(resolves?(binary)).to be(true),
                                         "#{id} runs #{binary}, which does not resolve to an executable"
          end
        end
      end
    end
  end
end
