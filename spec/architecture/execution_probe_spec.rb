# frozen_string_literal: true

require "rails_helper"

# THE INSTRUMENT HELD TO ITS OWN CLAIMS (round 9, R9-4).
#
# Round 9's finding was that `ExecutionProbe` did not observe what three ratified records said it
# observed. An instrument is a claim like any other, and the repository now carries the proof that
# this one is true — including the two cases the old instrument could not distinguish and the one it
# could never fail.
RSpec.describe ExecutionProbe, type: :model do
  # A subject with exactly the shape the SEC-B1 handlers have: a guard whose right operand is the
  # control, on a continuation line, reachable or short-circuited depending on the left operand.
  class ProbeSubject
    def self.control_evaluated? = true

    def guarded(short_circuit)
      unless short_circuit || ProbeSubject
                              .control_evaluated?
        return :denied
      end

      :allowed
    end
  end

  let(:control) { described_class.calls("ProbeSubject.control_evaluated?").first }

  it "observes the control when it is evaluated" do
    seen = described_class.watch([control]) { ProbeSubject.new.guarded(false) }

    expect(seen).to have_evaluated(control)
    expect(seen.count(control)).to eq(1)
  end

  it "FAILS when the statement is reached but the control short-circuits — R9-4's exact defect" do
    # THE CASE THE OLD INSTRUMENT COULD NOT SEE. The `unless` statement executes identically in both
    # runs; only the control's own invocation differs, and that is what is asserted now.
    seen = described_class.watch([control]) { ProbeSubject.new.guarded(true) }

    expect(seen).not_to have_evaluated(control)
    expect(seen.count(control)).to eq(0)
  end

  it "distinguishes the two runs by the control, where a line assertion cannot" do
    # The proof that the old mechanism was unsound, kept executable rather than described. The
    # `unless` line fires in BOTH runs, so no assertion about it can tell them apart.
    path = Object.const_source_location("ProbeSubject").first
    unless_line = File.readlines(path).each_with_index.find { |l, _| l.include?("unless short_circuit") }.last + 1

    both = [true, false].map do |short_circuit|
      lines = []
      trace = TracePoint.new(:line) { |tp| lines << tp.lineno if tp.path == path }
      trace.enable
      ProbeSubject.new.guarded(short_circuit)
      trace.disable
      lines.include?(unless_line)
    end

    expect(both).to eq([true, true]), "the `unless` line fires in both runs, which is why it proves nothing"
  end

  it "refuses to resolve a control to a continuation line, so a negative assertion cannot pass vacuously" do
    # THE OTHER HALF OF R9-4. A leading-dot line emits no `:line` event ever, so
    # `expect(lines).not_to include(n)` on it is true forever, whatever the code does. Resolution
    # now raises instead of returning a number that means nothing.
    relative = Pathname(Object.const_source_location("ProbeSubject").first)
                 .relative_path_from(Rails.root).to_s

    expect { described_class.line_of(relative, /\A\s+\.control_evaluated\?$/) }
      .to raise_error(/continuation line; Ruby emits no :line event/)
  end

  it "resolves and fails loudly on a control that does not exist" do
    expect { described_class.calls("ProbeSubject.no_such_control") }.to raise_error(/does not resolve/)
    expect { described_class.calls("NoSuchClass.anything") }.to raise_error(/does not resolve/)
    expect { described_class.calls("not a method name") }.to raise_error(/is not Klass#method/)
  end

  it "observes an instance method through an alias, a block and a helper, which lines cannot follow" do
    # WHY INVOCATION RATHER THAN LOCATION. Every one of these reaches the same method body by a route
    # a source-line rule would have to enumerate; `:call` fires for all of them without being told.
    klass = Class.new do
      def control? = true
      alias_method :aliased_control?, :control?
      def via_alias = aliased_control?
      def via_block = [1].map { control? }.first
      def via_helper = helper
      def helper = control?
    end
    Object.const_set(:ProbeAliasSubject, klass) unless Object.const_defined?(:ProbeAliasSubject)
    target = described_class.calls("ProbeAliasSubject#control?").first

    %i[via_alias via_block via_helper].each do |route|
      seen = described_class.watch([target]) { ProbeAliasSubject.new.public_send(route) }
      expect(seen).to have_evaluated(target), "#{route} did not register as an evaluation"
    end
  end
end
