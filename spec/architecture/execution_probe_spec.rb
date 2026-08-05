# frozen_string_literal: true

require "rails_helper"

# THE PROBE'S OWN PROOF (D5 family 6, R10-21).
#
# Several of this tranche's claims rest on `ExecutionProbe`, so a probe that silently observes
# nothing would make all of them vacuous at once — the highest-leverage single point of failure in
# the repair. Every example here is about the probe itself.
RSpec.describe ExecutionProbe, type: :architecture do
  # A real Ruby-defined surface to observe, with an alias, an inherited method, a singleton method
  # and a delegator — the kinds the probe must tell apart.
  class ProbeSubject
    def observed = :ok
    alias observed_alias observed
    def self.class_level = :ok
    def delegates = observed
  end

  class ProbeHeir < ProbeSubject; end

  describe "targets it can observe" do
    it "PROOF 205 — observes a Ruby-defined instance method that actually ran" do
      target = described_class.calls("ProbeSubject#observed").first
      seen = described_class.watch([target]) { ProbeSubject.new.observed }

      expect(seen).to have_evaluated(target)
    end

    it "PROOF 205b — resolves an ALIAS to the body it names, and observes that body" do
      # An alias shares the original's body, so `TracePoint` reports the ORIGINAL name. A probe that
      # keyed on the alias would observe nothing and report a false negative.
      aliased = described_class.calls("ProbeSubject#observed_alias").first
      original = described_class.calls("ProbeSubject#observed").first

      seen = described_class.watch([original]) { ProbeSubject.new.observed_alias }

      expect(aliased.traced_class).to eq(ProbeSubject)
      expect(seen).to have_evaluated(original)
    end

    it "PROOF 205c — resolves an INHERITED method to its defining class, not the class it was found through" do
      target = described_class.calls("ProbeHeir#observed").first

      expect(target.traced_class).to eq(ProbeSubject), "TracePoint reports the defining class"
      expect(described_class.watch([target]) { ProbeHeir.new.observed }).to have_evaluated(target)
    end

    it "PROOF 205d — observes a singleton method" do
      target = described_class.calls("ProbeSubject.class_level").first

      expect(described_class.watch([target]) { ProbeSubject.class_level }).to have_evaluated(target)
    end
  end

  describe "targets it must refuse" do
    it "PROOF 206 — refuses a C-defined target rather than watching it blindly" do
      stub_const("ProbeBlindSpot", Struct.new(:value))

      expect { described_class.calls("ProbeBlindSpot#value") }
        .to raise_error(/implemented in C/, "a C-defined target must be refused, not silently watched")
    end

    it "PROOF 206b — refuses a generated ACCESSOR, which reports a source location but has no body" do
      # THE DEFECT THIS EXAMPLE FOUND. The round-11 repair discriminated on `source_location`, and
      # `attr_reader` HAS one (`["file", line]`) while `TracePoint(:call)` still never fires for it.
      # Porting that patch unchanged would have left exactly the vacuity R10-21 is about, for the most
      # common accessor form in the language. The discriminator is now the instruction sequence.
      stub_const("ProbeAttr", Class.new { attr_reader :value })
      expect(ProbeAttr.instance_method(:value).source_location).not_to be_nil, "premise of this example"

      expect { described_class.calls("ProbeAttr#value") }.to raise_error(/generated accessor/)
    end

    it "PROOF 206d — ACCEPTS a define_method body, which is dynamic but genuinely observable" do
      # The discriminator must not simply refuse everything unusual: `define_method` carries an
      # instruction sequence and TracePoint reports it, so refusing it would block legitimate proofs.
      klass = Class.new { define_method(:dynamic) { :ok } }
      stub_const("ProbeDynamic", klass)
      target = described_class.calls("ProbeDynamic#dynamic").first

      expect(described_class.watch([target]) { ProbeDynamic.new.dynamic }).to have_evaluated(target)
    end

    it "PROOF 206e — the refusal happens BEFORE the user's proof runs, not as a later empty result" do
      stub_const("ProbeAttr2", Class.new { attr_reader :value })
      constructed = false

      expect { described_class.calls("ProbeAttr2#value"); constructed = true }.to raise_error(/generated accessor/)
      expect(constructed).to be(false), "the target was built, so a proof could have rested on it"
    end

    it "PROOF 206c — THE OLD FORM WOULD HAVE PASSED INCORRECTLY, and this is that demonstration" do
      # THE DEFECT, REPRODUCED AGAINST THE OLD MECHANISM. Before this repair the probe accepted a
      # C-defined target, observed nothing however many times the method ran, and therefore satisfied
      # every NEGATIVE assertion. This reconstructs exactly that arrangement and shows it: the
      # accessor is called, the observation is empty, and `not_to have_evaluated` would pass.
      subject_class = Struct.new(:value)
      stub_const("ProbeLegacy", subject_class)
      unchecked = described_class::Target.new("ProbeLegacy", :value, false) # deliberately NOT resolved

      seen = described_class.watch([unchecked]) { 5.times { ProbeLegacy.new(1).value } }

      expect(seen.evaluated?(unchecked)).to be(false), "the old form saw nothing, as recorded"
      # ...and that false is indistinguishable from a control that genuinely did not run, which is
      # why the repaired probe refuses the target instead of reporting it.
      expect { described_class.calls("ProbeLegacy#value") }.to raise_error(/implemented in C/)
    end

    it "PROOF 207 — a renamed or deleted control fails loudly at construction" do
      expect { described_class.calls("ProbeSubject#no_such_control") }.to raise_error(/does not resolve/)
    end

    it "PROOF 207b — a target REDEFINED after resolution is refused rather than watched stale" do
      # A probe holding metadata for a body nobody calls reports "not evaluated" forever, which is a
      # false negative that looks exactly like a control that did not run.
      klass = Class.new { def moving = :first }
      stub_const("ProbeMoving", klass)
      target = described_class.calls("ProbeMoving#moving").first

      klass.class_eval { def moving = :second }

      expect { described_class.watch([target]) { ProbeMoving.new.moving } }
        .to raise_error(/was redefined after this target was resolved/)
    end
  end

  describe "what a negative assertion is worth" do
    it "PROOF 208 — a negative assertion can only be written about a target the probe can see" do
      # THE FAILURE MODE THIS FORECLOSES: `expect(seen).not_to have_evaluated(X)` passes trivially when
      # X can never be observed. Since such an X can no longer be constructed, the assertion below is
      # the only remaining way to write one, and it observes a real Ruby method that genuinely did not
      # run in the block.
      target = described_class.calls("ProbeSubject#observed").first
      seen = described_class.watch([target]) { :nothing_called }

      expect(seen).not_to have_evaluated(target)
    end
  end
end
