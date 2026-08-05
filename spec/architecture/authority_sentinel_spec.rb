# frozen_string_literal: true

require "rails_helper"

# THE SENTINEL'S OWN PROOF (D5 family 4; R10-9, R10-11).
#
# The suite-wide rule it enforces is only worth what the instrument is worth. These examples are
# about the instrument: what it discovers, how it accounts, and whether it can go blind quietly.
RSpec.describe AuthoritySentinel, type: :architecture do
  describe "discovery" do
    it "covers EVERY WF-005 handler, derived from the directory rather than matched in source" do
      # R10-9. The set was decided by matching each file's source against
      # `/authenticate\(session_id:/`, which covered 3 of 6 handlers on this branch and which a merely
      # reformatted call defeats. Discovery is now the directory, and human-authorization is decided
      # per execution by whether `CommandAuthorizer#authenticate` RAN.
      files = Dir[Rails.root.join(described_class::HANDLER_DIR, "*.rb")].sort
      expect(files.length).to be >= 5, "the handler directory scan found #{files.length} files"

      expected = files.map { |f| File.basename(f, ".rb").camelize }.sort
      expect(described_class.observed_handlers.map { |h| h.name.split("::").last }.sort).to eq(expected),
             "a handler exists that the sentinel does not observe"
    end

    it "picks up a NEW production path without anyone updating a list" do
      # The owner's test of a derived mechanism: add a producer and see whether discovery finds it.
      # The directory is re-read, so a handler added by a later tranche joins the rule by existing.
      new_file = Rails.root.join(described_class::HANDLER_DIR, "sentinel_discovery_probe.rb")
      File.write(new_file, <<~RUBY)
        module Workflows
          module Wf005
            module Handlers
              class SentinelDiscoveryProbe
                def call(**) = nil
              end
            end
          end
        end
      RUBY
      described_class.instance_variable_set(:@observed_handlers, nil)
      load new_file

      expect(described_class.observed_handlers.map { |h| h.name.split("::").last })
        .to include("SentinelDiscoveryProbe")
    ensure
      FileUtils.rm_f(new_file)
      described_class.instance_variable_set(:@observed_handlers, nil)
      Workflows::Wf005::Handlers.send(:remove_const, :SentinelDiscoveryProbe) if
        Workflows::Wf005::Handlers.const_defined?(:SentinelDiscoveryProbe, false)
    end
  end

  describe "accounting" do
    it "keeps each thread's frame separate, so one command cannot erase another's" do
      # R10-11. The counters lived in module state, so one thread's `ensure` restored the other's
      # frame: writes were attributed to the wrong command and a real violation could be ERASED by a
      # concurrent well-behaved command. Two threads open frames simultaneously and each must see
      # only its own.
      # THE ORDER IS ESTABLISHED, NOT SLEPT FOR. The first version incremented and THEN synchronised,
      # so whether the mutation showed depended on the scheduler: if each thread opened its frame
      # AFTER the other had incremented, a shared frame was reset back to zero between them and both
      # threads still read 1. Measured: the `f4-accounting-global` mutation was killed on one
      # regeneration and SURVIVED the next, from the same bytes. A proof whose verdict is a coin toss
      # is not a proof, and this tranche has spent nine rounds on instruments that reported the
      # scheduler's choice.
      #
      # Both frames are now open BEFORE either increments, which is the only interleaving that can
      # distinguish per-thread accounting from shared accounting — and it is now the only one that
      # runs.
      opened = Queue.new
      release = Queue.new
      results = {}
      threads = %i[a b].map do |name|
        Thread.new do
          described_class.around_command(Struct.new(:name).new("T#{name}")) do
            opened << name
            release.pop(timeout: 10) || raise("thread #{name} was never released")
            described_class.frame[:governed] += 1
            results[name] = described_class.frame[:governed]
            nil
          end
        end
      end
      # BOUNDED, BECAUSE AN UNBOUNDED `pop` TURNS A THREAD THAT DIED INTO A SUITE-WIDE HANG. It did:
      # renaming the frame counter made both threads raise before reaching the barrier, and this
      # example blocked forever with no output rather than failing. An instrument's own proof must
      # fail loudly for the same reason the instrument must.
      2.times { opened.pop(timeout: 10) || raise("a sentinel thread never opened its frame") }
      2.times { release << :go }
      threads.each { |t| t.join(5) || raise("a sentinel thread did not finish within 5s") }

      expect(results.values).to eq([1, 1]),
                                "frames leaked across threads: #{results.inspect}"
    end

    it "restores the enclosing frame exactly, so nesting cannot corrupt the outer command" do
      outer = Struct.new(:name).new("Outer")
      inner = Struct.new(:name).new("Inner")
      described_class.around_command(outer) do
        described_class.frame[:governed] += 3
        described_class.around_command(inner) { described_class.frame[:governed] += 1 }
        expect(described_class.frame[:governed]).to eq(3), "the inner frame leaked into the outer"
        nil
      end
    end
  end

  describe "the human door" do
    it "is INSTALLED, so the sentinel's antecedent can be satisfied at all" do
      # THE BLOCKER THIS CLOSES. `AuthenticationObserver` was defined and never prepended, so
      # `note_authentication` was only ever called from inside its own dead module, `f[:human]` was
      # never true, and `judge` returned at its first guard for every command that has ever run. The
      # sentinel evaluated its rule ZERO times while reporting no violations — and the suite went
      # green precisely because the instrument was blind.
      described_class.arm!

      expect(IdentityAccess::Authorization::CommandAuthorizer.ancestors)
        .to include(AuthoritySentinel::AuthenticationObserver),
            "the human-authorization door is not installed; the sentinel cannot judge anything"
    end

    it "judges a command human-authorized when authenticate RUNS inside it" do
      # Observed at the callee, so no call-site spelling changes the answer.
      judged = nil
      handler = Struct.new(:name).new("ProbeHandler")
      described_class.around_command(handler) do
        described_class.note_authentication
        judged = described_class.frame[:human]
        nil
      end

      expect(judged).to be(true)
    end

    it "does NOT judge a platform-minted command human-authorized" do
      # A `crawl_fetch_due` delivery carries no Session, so :335 does not govern it. If this were
      # true for everything the rule would fire on service commands it does not cover.
      judged = nil
      handler = Struct.new(:name).new("ProbeServiceHandler")
      described_class.around_command(handler) { judged = described_class.frame[:human]; nil }

      expect(judged).to be(false)
    end
  end

  describe "the door" do
    # PROOF 232 IS REPLACED BY `spec/architecture/protected_effect_door_spec.rb` (D7).
    #
    # WHAT IT WAS AND WHY IT COULD NOT SURVIVE. It read the three stores' heredocs and asserted the
    # verb regex matched each one. That is the RIGHT direction and it was still not enough: the
    # pattern it certified — `\b(?:INSERT\s+INTO|UPDATE|DELETE\s+FROM)\b` — matches `SELECT ... FOR
    # UPDATE`, so `lock_crawl`'s ROW LOCK counted as a write and an idempotent replay, which executes
    # no data-modifying statement at all, satisfied the sentinel's antecedent. PROOF 232 passed
    # throughout, because it only ever asked whether the real writes MATCHED and never what else did.
    #
    # There is no pattern here to certify now. The door asks PostgreSQL to plan the statement and
    # reads the `ModifyTable` nodes out of the answer, so both directions are proved against the
    # planner rather than against a corpus someone remembered to write.

    it "no longer carries a verb pattern for anything to be certified against" do
      expect(described_class.const_defined?(:WRITE_VERB)).to be(false),
             "a text pattern is back in the door; the D7 record explains why every form of it was wrong"
    end
  end

  describe "non-vacuity" do
    it "REFUSES to report success from an empty census" do
      # The failure mode this forecloses is the worst kind: blinding the instrument makes the suite
      # GREENER, because a sentinel that observes nothing records no violations. Removing either
      # observer must therefore fail the run rather than quieten it.
      # DRIVEN DIRECTLY, so this does not depend on what other files ran first. An earlier version
      # asserted the live counters and was order-dependent — which is itself one of the defects this
      # family exists to remove.
      ok = { commands: 5, statements: 9, governed: 5, human: 5, undriven: [], unreached: [],
             unplannable: {} }
      expect { described_class.assert_observed!(**ok, commands: 0) }
        .to raise_error(/observed ZERO WF-005 command executions/)
      expect { described_class.assert_observed!(**ok, statements: 0) }
        .to raise_error(/observed ZERO statements/)
      # AND THE ONE THAT WAS MISSING: commands and writes observed, but the antecedent never satisfied.
      expect { described_class.assert_observed!(**ok, human: 0) }
        .to raise_error(/judged ZERO commands human-authorized/)
      # D7's OWN NON-VACUITY. Narrowing the antecedent from "wrote" to "committed a protected side
      # effect" is only a sharpening if the narrower antecedent is still reached. Zero governed
      # writes across the suite means the narrowing switched the invariant off.
      expect { described_class.assert_observed!(**ok, governed: 0) }
        .to raise_error(/observed ZERO protected side effects/)
      expect { described_class.assert_observed!(**ok, unreached: ["Workflows::Wf005::Handlers::Quiet"]) }
        .to raise_error(/never observed committing a protected side effect/)
      # A STATEMENT THE DOOR COULD NOT PLAN IS NOT A READ. If the instrument has no answer for a
      # statement that then executed, "no protected side effect" is a guess and the run must say so.
      expect { described_class.assert_observed!(**ok, unplannable: { "INSERT INTO ..." => 1 }) }
        .to raise_error(/could not\s+plan/)
      expect { described_class.assert_observed!(**ok) }.not_to raise_error
    end

    it "REFUSES to report success while any discovered handler was never executed" do
      # THE GAP A STATIC CENSUS USED TO COVER. This instrument derives its rule from EXECUTION, so a
      # handler no example drives is invisible to it by construction — a new handler could wait, write
      # and never re-read authority and nothing would notice. PROOF 193's directory census caught that
      # and was deleted; this replaces the obligation without enumerating anything, because both sides
      # are derived: the handlers from the directory, the executions from the run.
      expect(described_class.observed_handlers).not_to be_empty

      ok = { commands: 5, statements: 9, governed: 5, human: 5, undriven: [], unreached: [],
             unplannable: {} }
      expect { described_class.assert_observed!(**ok, undriven: ["Workflows::Wf005::Handlers::Unproved"]) }
        .to raise_error(/never executed by any example/)
      expect { described_class.assert_observed!(**ok) }.not_to raise_error
    end
  end
end
