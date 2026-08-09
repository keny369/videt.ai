# frozen_string_literal: true

require "rails_helper"

# THE REPLACEMENT FOR WireTap, PROVED UNDER THE CONDITIONS THAT BROKE IT (D5 family 2).
#
# `WireTap` prepended redefinitions of fourteen `PG::Connection` methods with a `*args, **kwargs,
# &block` signature none of them declares, claimed to observe "every execution API", could not
# recover SQL from the prepared-statement doors, and produced a SIGSEGV in the headline gate. It is
# deleted. What replaces it is one hook on one door, owned by the sentinel that needs it.
#
# WHAT EACH HALF OF THIS FILE PROVES, STATED EXACTLY, BECAUSE THE HEADER USED TO OVERSTATE IT
# (FU-55).
#
# The first half is about PREPENDING as a technique: that a prepended `exec_params` does not change
# arity, visibility, dispatch, block forwarding, inheritance, nesting, exception propagation, thread
# attribution or idempotence. Those examples build their own anonymous module over a stand-in class
# and NEVER TOUCH `GovernedWriteSentinel::Instrumentation`, which is the right shape for what they
# ask — and it means they say nothing whatever about the production hook. Measured: replacing the
# production `Instrumentation#exec_params` body with a bare `super`, so it observes nothing at all,
# left this file at 10 examples / 0 failures while `wf005_closed_fact_set_spec.rb` went 7/7 red. The
# header claimed to be what binds the instrument, and the acceptance spec was.
#
# The second half — "the production hook, on the real door" — is what binds it here. It drives a
# real statement through the real `PG::Connection` that `arm!` prepended to, and reads the census
# back. That is the example the gutted hook fails.
RSpec.describe "the governed-write observer", type: :architecture do
  # A stand-in with the same shape as the door, so dispatch properties can be asserted without
  # driving PostgreSQL for each one.
  let(:base) do
    Class.new do
      attr_reader :calls

      def initialize = @calls = []
      def exec_params(sql, params = nil, &blk) = @calls << [sql, params, blk&.call]
      def private_helper = :hidden
      private :private_helper
    end
  end

  def observed_class(sink)
    hook = Module.new do
      define_method(:exec_params) do |sql, *rest, &blk|
        sink << sql
        super(sql, *rest, &blk)
      end
    end
    Class.new(base).tap { |k| k.prepend(hook) }
  end

  it "observes the statement without altering the return value" do
    sink = []
    subject = observed_class(sink).new

    subject.exec_params("SELECT 1", [2])

    expect(sink).to eq(["SELECT 1"])
    expect(subject.calls).to eq([["SELECT 1", [2], nil]])
  end

  it "does not change arity, visibility, or method lookup" do
    sink = []
    klass = observed_class(sink)

    expect(klass.instance_method(:exec_params).arity).to eq(base.instance_method(:exec_params).arity)
    expect(klass.private_method_defined?(:private_helper)).to be(true)
    expect(klass.public_method_defined?(:exec_params)).to be(true)
  end

  it "forwards positional arguments and blocks exactly" do
    sink = []
    subject = observed_class(sink).new

    subject.exec_params("SELECT 2", [7]) { :from_block }

    expect(subject.calls).to eq([["SELECT 2", [7], :from_block]])
  end

  it "observes each INSTANCE separately, and never another instance's work" do
    sink = []
    klass = observed_class(sink)
    a = klass.new
    b = klass.new

    a.exec_params("FROM A")

    expect(a.calls.length).to eq(1)
    expect(b.calls).to be_empty, "one instance's statement was attributed to another"
  end

  it "survives INHERITANCE: a subclass is observed and still dispatches to its own override" do
    sink = []
    child = Class.new(observed_class(sink)) do
      def exec_params(sql, params = nil, &blk)
        super("#{sql} /*child*/", params, &blk)
      end
    end

    child.new.exec_params("SELECT 3")

    expect(sink).to eq(["SELECT 3 /*child*/"])
  end

  it "observes NESTED calls once each, not once per frame" do
    sink = []
    klass = observed_class(sink)
    nested = Class.new(klass) do
      def outer = exec_params("INNER")
    end

    nested.new.outer

    expect(sink).to eq(["INNER"])
  end

  it "observes a statement that RAISES, and re-raises unchanged" do
    sink = []
    raiser = Class.new do
      def exec_params(_sql, *) = raise(PG::Error, "boom")
    end
    hook = Module.new do
      define_method(:exec_params) do |sql, *rest, &blk|
        super(sql, *rest, &blk)
      rescue PG::Error
        sink << sql
        raise
      end
    end
    raiser.prepend(hook)

    expect { raiser.new.exec_params("BAD SQL") }.to raise_error(PG::Error, "boom")
    expect(sink).to eq(["BAD SQL"])
  end

  it "attributes CONCURRENT statements to the thread that issued them" do
    # WireTap published into a shared subscriber list with a `@publishing` flag, so one thread's
    # statement could suppress another's. The replacement records per call with the thread.
    seen = Queue.new
    hook = Module.new do
      define_method(:exec_params) do |sql, *rest, &blk|
        seen << [Thread.current.object_id, sql]
        super(sql, *rest, &blk)
      end
    end
    klass = Class.new(base).tap { |k| k.prepend(hook) }

    threads = 4.times.map { |i| Thread.new { klass.new.exec_params("SELECT #{i}") } }
    threads.each { |t| t.join(5) || raise("a thread did not finish within 5s") }

    recorded = Array.new(seen.size) { seen.pop }
    expect(recorded.length).to eq(4), "statements were suppressed by a shared publishing flag"
    expect(recorded.map(&:first).uniq.length).to eq(4), "statements were attributed to one thread"
  end

  it "is idempotent under repeated installation" do
    sink = []
    klass = observed_class(sink)
    hook = klass.ancestors.first
    klass.prepend(hook) # prepending the same module again must not double-count

    klass.new.exec_params("SELECT 4")

    expect(sink).to eq(["SELECT 4"])
  end

  # ---- the production hook, on the real door (FU-55) ------------------------------------------
  describe "the production hook, on the real door" do
    # The census is process-wide and is judged at suite end, so an example that writes into it would
    # be supplying the very evidence that judgement looks for. It is snapshotted and restored, and
    # the entry this example makes is `reachable=false` anyway — no WF-005 entry point is on the
    # stack — so it could not enter the failure set even if it were left behind.
    around do |example|
      snapshot = GovernedWriteSentinel.census.dup
      example.run
    ensure
      GovernedWriteSentinel.census.replace(snapshot)
    end

    it "is installed on `PG::Connection`, ahead of the method it observes" do
      ancestors = PG::Connection.ancestors

      expect(ancestors).to include(GovernedWriteSentinel::Instrumentation)
      expect(ancestors.index(GovernedWriteSentinel::Instrumentation))
        .to be < ancestors.index(PG::Connection),
            "the module is in the ancestry but BEHIND the class, so its `exec_params` is never the " \
            "one that runs"
      expect(GovernedWriteSentinel).to be_armed
    end

    it "records a governed statement executed through the REAL door" do
      # A GOVERNED TABLE READ FROM THE CATALOGUE, not named here: the instrument derives its set
      # from `pg_trigger`, so a table that stops being governed must stop being used by this proof
      # too, rather than pinning it to a name the rule no longer covers.
      table = GovernedWriteSentinel.governed_tables.first
      expect(table).to be_present, "no table carries `f1_crawl_child_fact_closed`, so this example " \
                                   "has nothing governed to write and would pass vacuously"

      # THE STATEMENT IS REAL AND APPLIES NOTHING. `WHERE false` inserts no row, so no closed-fact
      # trigger fires and no state moves; what is being proved is that the DOOR saw the statement,
      # which the census records from the text and the call stack alone.
      #
      # The sentinel classifies by ISSUING FRAME, and production's issuers live under
      # `app/workflows/wf005/`. Pointing `WF005_SOURCE` at this file is what makes this example the
      # issuer — the alternative is to reach the census only through a WF-005 producer, which would
      # make this a proof about that producer rather than about the hook.
      stub_const("GovernedWriteSentinel::WF005_SOURCE", Regexp.new(Regexp.escape(__FILE__)))

      DbInspector.connection.exec_params("INSERT INTO #{table} (id) SELECT NULL::uuid WHERE false", [])

      observed = GovernedWriteSentinel.census.keys.select do |(site, _origin, seen, translated, reachable)|
        seen == table && site.to_s.include?(File.basename(__FILE__)) && !translated && !reachable
      end

      expect(observed).not_to be_empty,
                             "a statement writing a governed table executed through the real " \
                             "`PG::Connection` and the census did not record it: " \
                             "`Instrumentation#exec_params` is not observing. This is the exact " \
                             "state a bare `super` produces, which every other example in this " \
                             "file survives."
    end

    it "REFUSES to report success on an empty census, which is what a blind door produces" do
      # THE ASYMMETRY, DRIVEN. Blinding this instrument makes the run GREENER — "no unclassified
      # untranslated write" is satisfied perfectly by observing nothing — so the suite-end guard
      # must fail on an empty census rather than quieten. `AuthoritySentinel.assert_observed!` has
      # had this since D5; until FU-55 this sentinel had no counterpart.
      expect { GovernedWriteSentinel.assert_observed!(census: {}) }
        .to raise_error(/observed ZERO governed writes/)
      expect { GovernedWriteSentinel.assert_observed!(census: { %w[a b c] => 1 }) }
        .not_to raise_error
    end
  end

  describe "what it deliberately does NOT claim" do
    it "does not observe prepared-statement doors, and the census says so" do
      # THE DEFECT THAT KILLED WireTap, stated as a property rather than hidden. `exec_prepared`
      # carries a statement NAME, so no SQL-pattern rule can read it. The completeness argument rests
      # on PROOF 175's call-site analysis, not on this hook.
      expect(GovernedWriteSentinel::Instrumentation.instance_methods).to eq([:exec_params])
      expect(File.read(Rails.root.join("spec/support/governed_write_sentinel.rb")))
        .to include("It does NOT claim to see prepared-statement writes")
    end
  end
end
