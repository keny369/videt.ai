# frozen_string_literal: true

# DID THIS PROOF EVALUATE THE CONTROL IT NAMES? (round 9, R9-4.)
#
# THE INSTRUMENT THIS REPLACES ASKED THE WRONG QUESTION. It resolved a control to a SOURCE LINE and
# asserted that line executed. Two facts about Ruby make that unsound, and round 9 proved both:
#
#   * `unless guard || Owner.new(...).predicate?` is ONE `:line` event, fired whether or not the
#     right operand is ever evaluated. A proof asserting on it passes in a run where the control is
#     provably short-circuited past — which is exactly the bypass form R9-3 exploits.
#   * A LEADING-DOT CONTINUATION LINE NEVER FIRES A `:line` EVENT AT ALL. So the line that actually
#     carries `.authority_current?` can never be asserted on: a positive assertion is unsatisfiable
#     and, worse, a NEGATIVE assertion on it passes vacuously forever.
#
# So this observes INVOCATION, not location. `TracePoint(:call)` fires when a method body is entered
# — there is no arrangement of `||`, `&&`, `unless`, helper extraction, line wrapping or operator
# spelling that enters a method body without firing it. What a proof asserts is "this predicate was
# evaluated in this block", which is the thing it means.
#
#   AUTHORITY = ExecutionProbe.calls("IdentityAccess::Authorization::CommandAuthorizer.authority_current?")
#   seen = ExecutionProbe.watch(AUTHORITY) { drive_the_handler }
#   expect(seen).to have_evaluated(AUTHORITY.first)
#
# `spec/architecture/execution_probe_spec.rb` holds this instrument to its own claims: it passes when
# the control is evaluated, FAILS when the statement is reached and the control short-circuits, and
# cannot satisfy a negative assertion through a line Ruby never reports.
module ExecutionProbe
  # A method to observe, named the way the repository names it. `Klass.method` is a singleton method,
  # `Klass#method` an instance method. Resolution happens when the target is built, so a renamed or
  # deleted control fails loudly rather than silently observing nothing.
  Target = Struct.new(:owner, :name, :singleton) do
    def to_s = "#{owner}#{singleton ? '.' : '#'}#{name}"

    def klass = Object.const_get(owner)

    # The bound method object, whichever kind it is. `instance_method`/`method` both walk the
    # ancestry, so an INHERITED method resolves to the ancestor that defines it and an ALIAS resolves
    # to the body it names — which is what must be observed, since that is what `TracePoint` reports.
    def reflect = singleton ? klass.method(name) : klass.instance_method(name)

    # The class `TracePoint#defined_class` reports: the singleton class for a class method, the
    # DEFINING class or module for an instance method — not the class it was looked up through.
    def traced_class = singleton ? klass.singleton_class : reflect.owner

    # WHAT KIND OF METHOD THIS IS, decided by the interpreter rather than inferred (R10-21).
    #
    # `TracePoint(:call)` fires for exactly the methods that have an INSTRUCTION SEQUENCE, so
    # `RubyVM::InstructionSequence.of` is the discriminator — not `source_location`, which the round-11
    # repair used and which is INCOMPLETE. Measured on Ruby 3.4.10:
    #
    #   attr_reader     source_location ["-e", 2]   iseq nil       <- watching it observes NOTHING
    #   plain def       source_location ["-e", 2]   iseq present
    #   define_method   source_location ["-e", 2]   iseq present   <- dynamic, and observable
    #   Struct accessor source_location nil         iseq nil
    #   C method        source_location nil         iseq nil
    #
    # `source_location` therefore refuses Struct accessors and ACCEPTS `attr_reader`, which is exactly
    # the vacuity this repair exists to remove — a proof watching an `attr_reader` would have gone on
    # observing nothing while every negative assertion passed. The self-test that found this is
    # PROOF 206b; the round-11 patch is ported with its discriminator corrected rather than as-is.
    def kind
      method = reflect
      return :ruby if RubyVM::InstructionSequence.of(method)
      return :accessor if method.source_location # attr_* and friends: a location, but no body to trace

      :c_defined
    rescue TypeError, ArgumentError
      :c_defined
    end

    # Identity of the BODY this target resolved to, so a later redefinition is detectable. A probe
    # holding stale metadata would watch a class/method pair that no longer names the code under
    # test and report "not evaluated" forever.
    def fingerprint
      method = reflect
      [method.owner, method.source_location, method.arity]
    rescue NameError
      nil
    end

    def resolve!
      unless singleton ? klass.respond_to?(name, true) : klass.method_defined?(name) || klass.private_method_defined?(name)
        raise "#{self} does not resolve to a method"
      end

      refuse_unobservable!
      @resolved_fingerprint = fingerprint
      self
    rescue NameError => e
      raise "#{self} does not resolve: #{e.message}"
    end

    # RE-CHECKED AT OBSERVATION TIME. Resolution proves the target existed when the proof was
    # written; this proves it is still the same body when the proof RUNS. `stub_const`, a monkey
    # patch, a reopened class or a `prepend` between the two would otherwise leave the probe
    # watching a body nobody calls, and every negative assertion on it would pass.
    def assert_current!
      return if @resolved_fingerprint.nil? || fingerprint == @resolved_fingerprint

      raise "#{self} was redefined after this target was resolved (was #{@resolved_fingerprint.inspect}, " \
            "now #{fingerprint.inspect}); the probe would be watching a body nothing calls"
    end

    # A TARGET THIS PROBE CANNOT SEE IS REFUSED AT CONSTRUCTION, NOT SILENTLY WATCHED (R10-21).
    #
    # Watching a C-defined method observes nothing, forever. Every `have_evaluated` on it fails and
    # every `not_to have_evaluated` PASSES — so the probe certifies absence it never checked. The
    # round-10 review found this by inspection; refusing the target makes it impossible rather than
    # documented, and the message says which kind was refused and what to do instead.
    def refuse_unobservable!
      case kind
      when :ruby then nil
      when :accessor
        raise "#{self} is a generated accessor (attr_* or similar). It reports a source location, so " \
              "it LOOKS observable, but it carries no instruction sequence and TracePoint(:call) " \
              "never fires for it — watching it would observe nothing while every negative assertion " \
              "passed. Observe a Ruby method that calls it instead."
      else
        raise "#{self} is implemented in C, so TracePoint(:call) never fires for it. Watching it " \
              "would observe nothing while every negative assertion passed. Observe a Ruby method " \
              "that calls it instead."
      end
    end
  end

  # What the block did, per target.
  class Observation
    def initialize(counts) = @counts = counts
    def evaluated?(target) = count(target).positive?
    def count(target) = @counts.fetch(target.to_s, 0)
    def to_s = @counts.empty? ? "(nothing observed)" : @counts.map { |k, v| "#{k}=#{v}" }.join(" ")
    def inspect = "#<ExecutionProbe::Observation #{self}>"
  end

  module_function

  # Parse `"Klass.method"` / `"Klass#method"` into targets, resolving each one NOW.
  def calls(*names)
    names.map do |name|
      separator_index = name.rindex(/[#.]/)
      raise "#{name.inspect} is not Klass#method or Klass.method" if separator_index.nil?

      Target.new(name[0...separator_index], name[(separator_index + 1)..].to_sym,
                 name[separator_index] == ".").resolve!
    end
  end

  # Count entries into each target's body during the block.
  #
  # `:call` fires for a Ruby method body being entered — after argument binding, before the first
  # statement. It cannot be reached by a short-circuit, and it is not a line, so nothing about source
  # formatting can make it unobservable.
  def watch(targets)
    counts = Hash.new(0)
    # STALE METADATA IS REFUSED BEFORE THE BLOCK RUNS, not discovered afterwards as an empty result.
    targets.each(&:assert_current!)
    wanted = targets.to_h { |t| [[t.traced_class, t.name], t.to_s] }
    trace = TracePoint.new(:call) do |tp|
      label = wanted[[tp.defined_class, tp.method_id]]
      counts[label] += 1 if label
    end
    trace.enable
    begin
      yield
    ensure
      trace.disable
    end
    Observation.new(counts)
  end

  # Every line of `relative_paths` executed inside the block, as { relative_path => Set(line) }.
  #
  # RETAINED FOR THE ONE QUESTION LINES CAN HONESTLY ANSWER: "did execution reach this region at
  # all", which is what R8-3's vacuous PROOF 168 needed. It is NOT a way to assert that a control was
  # evaluated — `watch` is — and `line_of` now refuses to resolve a control to a line Ruby cannot
  # report, so the old instrument's two unsound uses are impossible rather than discouraged.
  def executed(*relative_paths)
    roots = relative_paths.to_h { |path| [Rails.root.join(path).to_s, path] }
    seen = Hash.new { |h, k| h[k] = Set.new }
    trace = TracePoint.new(:line) do |tp|
      relative = roots[tp.path]
      seen[relative] << tp.lineno if relative
    end
    trace.enable
    begin
      yield
    ensure
      trace.disable
    end
    seen
  end

  def lines(relative_path, &) = executed(relative_path, &).fetch(relative_path, Set.new)

  # The 1-based line in `relative_path` matching `pattern`, REFUSING a line Ruby will never report.
  def line_of(relative_path, pattern)
    source = Rails.root.join(relative_path).read.lines
    matches = source.each_with_index.filter_map do |line, index|
      index + 1 if line.match?(pattern) && !line.strip.start_with?("#")
    end
    raise "no line in #{relative_path} matches #{pattern.inspect}" if matches.empty?
    raise "#{matches.length} lines in #{relative_path} match #{pattern.inspect}" if matches.length > 1

    line = matches.first
    if source[line - 1].strip.start_with?(".", "&.")
      raise "#{relative_path}:#{line} is a continuation line; Ruby emits no :line event for it, so " \
            "neither a positive nor a negative assertion about it means anything. Observe the " \
            "method with ExecutionProbe.watch instead."
    end

    line
  end
end

RSpec::Matchers.define :have_evaluated do |target|
  match { |observation| observation.evaluated?(target) }
  failure_message do |observation|
    "expected #{target} to have been evaluated in this block, but it was not. Observed: #{observation}"
  end
  failure_message_when_negated do |observation|
    "expected #{target} NOT to have been evaluated, but it ran #{observation.count(target)} time(s)"
  end
end
