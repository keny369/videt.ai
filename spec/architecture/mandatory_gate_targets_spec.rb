# frozen_string_literal: true

require "rails_helper"
require "yaml"

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

  def self.mandatory_checks(node, found = [])
    case node
    when Hash
      node["checks"]&.each { |c| found << c if c.is_a?(Hash) && c["mandatory"] && c["command"] }
      node.each_value { |v| mandatory_checks(v, found) }
    when Array then node.each { |v| mandatory_checks(v, found) }
    end
    found.uniq { |c| c["id"] }
  end

  CHECKS = mandatory_checks(MANIFEST).freeze

  it "declares mandatory checks at all, so this gate is not vacuous" do
    expect(CHECKS.length).to be >= 10, "the manifest parse found #{CHECKS.length} mandatory checks"
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
        # EXECUTABLE TARGETS: the binary the gate shells out to must exist and be runnable.
        binary = command.split.first
        next unless binary.start_with?("bin/")

        path = Rails.root.join(binary)
        expect(path).to exist, "#{id} runs #{binary}, which does not exist"
        expect(File.executable?(path)).to be(true), "#{id} runs #{binary}, which is not executable"
      end
    end
  end
end
