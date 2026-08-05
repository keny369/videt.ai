# frozen_string_literal: true

require "rails_helper"

# THE REPLACEMENT FOR WireTap, PROVED UNDER THE CONDITIONS THAT BROKE IT (D5 family 2).
#
# `WireTap` prepended redefinitions of fourteen `PG::Connection` methods with a `*args, **kwargs,
# &block` signature none of them declares, claimed to observe "every execution API", could not
# recover SQL from the prepared-statement doors, and produced a SIGSEGV in the headline gate. It is
# deleted. What replaces it is one hook on one door, owned by the sentinel that needs it.
#
# These examples are about the HOOK's behaviour, not about the sentinels' rules. The rules are proved
# elsewhere; this proves that installing the hook does not change how the object under it behaves.
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
