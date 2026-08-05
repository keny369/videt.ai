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

    it "PROOF 207c — a PREPENDED wrapper leaves the original observable, and is NOT treated as staleness" do
      # THE DISTINCTION THIS MUST DRAW. `AuthoritySentinel` prepends an observer to
      # `CommandAuthorizer` for the whole suite and the original body still runs via `super`. An
      # earlier version of this repair treated that as a redefinition and refused to watch, breaking
      # eight existing post-wait authority proofs. Instrumentation is not a redefinition.
      klass = Class.new { def wrapped = :original }
      stub_const("ProbeWrapped", klass)
      target = described_class.calls("ProbeWrapped#wrapped").first
      klass.prepend(Module.new { def wrapped = super })

      expect(described_class.watch([target]) { ProbeWrapped.new.wrapped }).to have_evaluated(target)
    end

    it "PROOF 207b — a body REDEFINED after resolution is still observed, because metadata is re-derived" do
      # THE REQUIREMENT: a redefinition must not leave the probe holding stale metadata. It cannot,
      # because `traced_class` is resolved on every `watch` rather than cached at construction. This
      # asserts that property directly instead of asserting a refusal that would be wrong.
      klass = Class.new { def moving = :first }
      stub_const("ProbeMoving", klass)
      target = described_class.calls("ProbeMoving#moving").first

      klass.class_eval { def moving = :second }

      seen = described_class.watch([target]) { ProbeMoving.new.moving }
      expect(seen).to have_evaluated(target), "the probe watched a stale definition"
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

  # CALLER BINDING (D5 family 1, R10-17/R10-18).
  #
  # THE LESSON THIS PRESERVES: a proof that only establishes the owner ran SOMEWHERE inside a block is
  # insufficient. It must establish that THE CALLER UNDER TEST invoked the owner as part of that
  # caller's own execution. Every example below is one of the ways "somewhere" is satisfied by
  # something other than the caller.
  describe "binding an invocation to its caller" do
    class CallerBound
      def self.owner_control = :consulted
      def gate = CallerBound.owner_control          # the caller under test
      def sibling = CallerBound.owner_control       # a different production path
      def reimplemented = :consulted                # the inversion: same answer, owner never called
    end

    let(:owner) { described_class.calls("CallerBound.owner_control").first }

    it "PROOF 209 — passes when the caller under test invoked the owner" do
      seen = described_class.watch([owner]) { CallerBound.new.gate }

      expect(seen).to have_evaluated(owner).from("CallerBound#gate")
    end

    it "PROOF 209b — FAILS when the caller reimplemented the control instead of consulting it" do
      # THE R10-17 SHAPE. The block still produces the right answer and the owner is never called.
      seen = described_class.watch([owner]) { CallerBound.new.reimplemented }

      expect(seen).not_to have_evaluated(owner).from("CallerBound#reimplemented")
    end

    it "PROOF 209c — FAILS when only a SIBLING call path invoked the owner" do
      # THE EXACT DEFECT THAT SURVIVED ROUND 11's FIRST ATTEMPT: a pass consults the deadline again
      # through another route, so "evaluated somewhere" stayed true while the gate was inverted.
      seen = described_class.watch([owner]) { CallerBound.new.sibling }

      expect(seen).to have_evaluated(owner), "the owner did run — via the sibling"
      expect(seen).not_to have_evaluated(owner).from("CallerBound#gate"),
                          "but the caller under test never consulted it"
    end

    it "PROOF 209d — FAILS when a SETUP HOOK invoked the owner before the caller" do
      seen = described_class.watch([owner]) do
        CallerBound.owner_control          # setup, not the caller
        CallerBound.new.reimplemented      # the caller, which consults nothing
      end

      expect(seen).to have_evaluated(owner)
      expect(seen).not_to have_evaluated(owner).from("CallerBound#reimplemented")
    end

    it "PROOF 209e — FAILS when the owner ran AFTER the caller completed" do
      seen = described_class.watch([owner]) do
        CallerBound.new.reimplemented
        CallerBound.owner_control
      end

      expect(seen).not_to have_evaluated(owner).from("CallerBound#reimplemented")
    end

    it "PROOF 209f — FAILS when ANOTHER THREAD invoked the owner" do
      # Attribution is per thread. A concurrent worker consulting the control must not satisfy a
      # proof about this thread's caller — a shared counter cannot tell the difference, which is why
      # the invocation record carries the thread rather than a count.
      seen = described_class.watch([owner]) do
        Thread.new { CallerBound.new.gate }.join
        CallerBound.new.reimplemented
      end

      expect(seen).to have_evaluated(owner), "the other thread did consult it"
      expect(seen).not_to have_evaluated(owner).from("CallerBound#gate"),
                          "but not on the asserting thread"
    end

    it "PROOF 209g — and the cross-thread case can be asserted DELIBERATELY when that is the subject" do
      # Not a loophole: the thread must be named, so a proof cannot pick up another thread's work by
      # accident. This is the only way to write it.
      other = nil
      seen = described_class.watch([owner]) { other = Thread.new { CallerBound.new.gate }.tap(&:join) }

      expect(seen).to have_evaluated(owner).from("CallerBound#gate").on_thread(other)
    end

    it "PROOF 209h — FAILS when the invocation happened OUTSIDE the observation scope" do
      CallerBound.new.gate # before the block opens
      seen = described_class.watch([owner]) { CallerBound.new.reimplemented }

      expect(seen).not_to have_evaluated(owner)
    end

    it "PROOF 209i — THE OLD FORM WOULD HAVE PASSED every one of the cases above" do
      # The demonstration the repair is required to carry: unbound `evaluated?` is satisfied by the
      # sibling, the setup hook, the trailing call and the other thread alike.
      %i[sibling].each do |via|
        seen = described_class.watch([owner]) { CallerBound.new.public_send(via) }
        expect(seen.evaluated?(owner)).to be(true), "the old form passes for #{via}"
      end
      seen = described_class.watch([owner]) { Thread.new { CallerBound.new.gate }.join }
      expect(seen.evaluated?(owner)).to be(true), "the old form passes for another thread"
    end
  end
end
