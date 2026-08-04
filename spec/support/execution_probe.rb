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

    # The class `TracePoint#defined_class` reports for this method: the singleton class for a class
    # method, the defining class or module for an instance method.
    def traced_class
      klass = Object.const_get(owner)
      singleton ? klass.singleton_class : Object.const_get(owner).instance_method(name).owner
    end

    def resolve!
      klass = Object.const_get(owner)
      unless singleton ? klass.respond_to?(name, true) : klass.method_defined?(name) || klass.private_method_defined?(name)
        raise "#{self} does not resolve to a method"
      end

      self
    rescue NameError => e
      raise "#{self} does not resolve: #{e.message}"
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
