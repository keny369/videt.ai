# frozen_string_literal: true

require "rails_helper"

# EVERY CONSTANT ANOTHER FILE NAMES MUST HAVE A FILE ZEITWERK CAN FIND IT IN.
#
# Zeitwerk resolves `Foo::Bar` by looking for `foo/bar.rb`. A constant declared as a SIBLING of
# the one its file is named for — `module CheckAttemptSchedule` sitting beside
# `module EvaluationStageSchedule` inside `evaluation_stage_schedule.rb` — has no such path, so
# it exists only once something unrelated has already caused that file to load.
#
# `bin/rails zeitwerk:check` does NOT catch this. It verifies that each file defines the constant
# its path implies; an EXTRA constant that no path implies is invisible to it. The test and
# production environments eager load, so every constant is defined before anything runs and the
# whole suite passes. Development does not (`config.eager_load = false`).
#
# THIS SPEC EXISTS BECAUSE THE PRODUCT FAILED, NOT BECAUSE THE SUITE DID. A live evaluation of
# `xirconhomes.com.au` on 2026-08-08 raised `NameError: uninitialized constant
# Workflows::Wf007::Handlers::AdvanceEvaluationStage::CheckAttemptSchedule` on the path that
# materializes every Check Result Slot. `Platform::ScheduledActions::Worker` swallowed it into
# `scheduled_action_execution_failed` — persisting a token and never the message — and the
# released action then SUCCEEDED on redelivery, because by then another reference had loaded the
# file. An intermittent, self-healing failure on a core path, invisible to every gate.
#
# WHAT IS ASSERTED IS THE NARROW, TRUE RULE. A sibling used only inside its own file is harmless:
# whatever reaches it has already loaded that file. `App::Sources` and `App::Verifications` are
# exactly that, and are deliberately still permitted. The defect is a sibling that ANOTHER file
# names, and that is what fails here.
RSpec.describe "Autoloadable constants", type: :architecture,
               acceptance_ids: %w[AC-ARCH], test_types: %w[TYP-SEC] do
  ROOT_APP = Rails.root.join("app")

  def self.camelize(basename)
    basename.split("_").map { |part| part[0].upcase + part[1..].to_s }.join
  end

  # `(indent, name)` for every `module`/`class` declaration in the file.
  def declarations(path)
    path.read.scan(/^([ \t]*)(?:module|class) ([A-Z][A-Za-z0-9_]*)/).map { |i, n| [i.length, n] }
  end

  # Constants declared at the SAME nesting level as the one the file is named for.
  def siblings(path)
    expected = self.class.camelize(path.basename(".rb").to_s)
    decls = declarations(path)
    own = decls.find { |_, name| name == expected }
    return [] if own.nil?

    decls.select { |indent, name| indent == own[0] && name != expected }.map(&:last).uniq
  end

  let(:ruby_files) { ROOT_APP.glob("**/*.rb").sort }

  it "declares no constant that another file names but Zeitwerk cannot autoload" do
    offenders = ruby_files.flat_map do |path|
      siblings(path).filter_map do |name|
        # A REAL CONSTANT REFERENCE, not the word appearing in SQL or prose. Requires the
        # constant to be followed by `::`, `.`, or `(` — how a module is actually used.
        users = (ruby_files - [path]).select do |other|
          other.read.match?(/(?<![A-Za-z0-9_:])#{Regexp.escape(name)}(?=::|\.[a-z_]|\()/)
        end
        next if users.empty?

        "#{path.relative_path_from(Rails.root)} declares #{name} as a sibling, but it is named by " \
          "#{users.map { |u| u.relative_path_from(Rails.root).to_s }.join(', ')} — give it its own file"
      end
    end

    expect(offenders).to be_empty, offenders.join("\n")
  end

  # THE PROOF THAT THE RULE IS NOT VACUOUS. `CheckAttemptSchedule` is the constant the live
  # failure named; asserting it resolves under its OWN path is what would fail if a later edit
  # folded it back beside its sibling.
  it "resolves the constant whose absence broke a live evaluation, from its own path" do
    expect(ROOT_APP.join("workflows/wf007/check_attempt_schedule.rb")).to exist
    expect(Workflows::Wf007::CheckAttemptSchedule::ACTION_KIND).to eq("check_attempt_due")
  end
end
