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

    # NO STALE METADATA, BY CONSTRUCTION.
    #
    # An earlier version of this repair cached the resolved body and refused to watch a target whose
    # definition had moved. That was solving a problem this probe does not have — `traced_class` is
    # re-derived on EVERY `watch`, so the hook is always keyed on the definition that is current when
    # the block runs. The cached form also could not tell a redefinition from ordinary
    # instrumentation: `AuthoritySentinel` prepends an observer to `CommandAuthorizer` for the whole
    # suite, and treating that as staleness broke eight existing post-wait authority proofs.
    #
    # PROOF 207b and 207c hold both halves: a redefined body is observed, and a prepended wrapper
    # leaves the original observable.

    def resolve!
      unless singleton ? klass.respond_to?(name, true) : klass.method_defined?(name) || klass.private_method_defined?(name)
        raise "#{self} does not resolve to a method"
      end

      refuse_unobservable!
      self
    rescue NameError => e
      raise "#{self} does not resolve: #{e.message}"
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
    def initialize(counts, invocations = {})
      @counts = counts
      @invocations = invocations
    end

    def evaluated?(target) = count(target).positive?
    def count(target) = @counts.fetch(target.to_s, 0)

    # EVERY INVOCATION, WITH WHO ISSUED IT AND ON WHICH THREAD (D5 family 1).
    #
    # WHY `evaluated?` IS NOT ENOUGH, stated where it will be read. It answers "did anything call this
    # during the block", and that is too weak wherever the block reaches the control by more than one
    # route. Inverting `CrawlDriver#within_wall_clock?` to reimplement :442's comparison left
    # `evaluated?` TRUE and its proof passing, because the same pass consults the deadline again
    # through `RunBoundedOutbound` on every request. A proof that a control ran SOMEWHERE is not a
    # proof that a given caller consulted it — and a setup hook, a sibling path, another instance or
    # another thread all satisfy "somewhere".
    def invocations(target) = @invocations.fetch(target.to_s, [])

    def sites(target) = invocations(target).map { |i| i[:site] }

    # Did THIS caller, on THIS thread, invoke the target during the block?
    # THE SITE MUST RESOLVE, AND IT MUST MATCH EXACTLY.
    #
    # TWO DEFECTS THIS CLOSES, both found by attacking the instrument rather than using it. The match
    # was `String#include?`, so `.from("X#gate")` was satisfied by `X#gate_two` — a substring
    # collision inside the very mechanism built to stop "somewhere" satisfying "here". And nothing
    # checked that the named site resolved to anything, so every NEGATIVE assertion naming a typo, a
    # renamed method or a fictional class passed vacuously.
    #
    # The site is now compared as a whole method identity, and a site that names no method this target
    # was ever invoked from — in a run where it WAS invoked — raises rather than answering false.
    def evaluated_from?(target, site, thread: Thread.current)
      assert_site_resolves!(site)
      invocations(target).any? { |i| site_matches?(i[:site], site) && i[:thread] == thread.object_id }
    end

    # THE NAMED SITE MUST BE A REAL METHOD.
    #
    # WHY NOT "a site nothing invoked": a legitimate negative assertion — the gate under test did NOT
    # consult the owner — is indistinguishable from a typo by that test, and treating it as an error
    # would break every proof that asserts a caller did nothing. The resolvable question is whether
    # the site NAMES SOMETHING THAT EXISTS, which a typo, a rename and a fictional class all fail and
    # a legitimate negative passes.
    def assert_site_resolves!(site)
      identity = site.split(":").last
      match = identity.match(/\A([A-Z][\w:]*)([#.])(\w+[?!=]?)\z/)
      return unless match

      owner, kind, name = match.captures
      # `caller_locations#label` reports the DEMODULIZED class, so `Workflows::Wf005::Admission`
      # arrives as `Admission`. Resolution therefore tries the bare constant first and then searches
      # loaded modules for one whose demodulized name matches — otherwise every namespaced production
      # site would be reported as a typo.
      klass = resolve_owner(owner)
      if klass.nil?
        raise "#{site.inspect} names #{owner}, which is not a defined constant; a caller-bound " \
              "assertion naming a site that does not exist passes vacuously"
      end
      exists = kind == "." ? klass.respond_to?(name, true) : klass.method_defined?(name) ||
                                                             klass.private_method_defined?(name)
      return if exists

      raise "#{site.inspect} names #{name}, which #{owner} does not define; a caller-bound assertion " \
            "naming a site that does not exist passes vacuously"
    end

    # `file:Klass#method` — the site matches when the METHOD IDENTITY is equal, not merely contained.
    def resolve_owner(owner)
      Object.const_get(owner)
    rescue NameError
      ObjectSpace.each_object(Module).find do |mod|
        name = mod.name
        name && name.split("::").last == owner
      end
    end

    def site_matches?(recorded, site)
      recorded.split(":").last == site || recorded == site
    end
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
    invocations = Hash.new { |h, k| h[k] = [] }
    # RE-CHECKED AT OBSERVATION TIME, NOT ONLY AT CONSTRUCTION. A target resolved as a Ruby method and
    # then REDEFINED as an `attr_reader` observes nothing while every negative assertion passes — the
    # exact R10-21 vacuity, restored by redefinition. Construction-time refusal alone cannot see it.
    targets.each(&:refuse_unobservable!)
    wanted = targets.to_h { |t| [[t.traced_class, t.name], t.to_s] }
    trace = TracePoint.new(:call) do |tp|
      label = wanted[[tp.defined_class, tp.method_id]]
      next unless label

      counts[label] += 1
      # THE CALLER, NOT THE CALLEE. `caller_locations(2, 1)` from inside the hook is the frame that
      # ISSUED the call. Recorded as file plus calling-method name rather than a line number, so it
      # survives an edit above it and still names exactly which gate consulted the control — and with
      # the THREAD, so one thread's work cannot be attributed to another's caller.
      origin = caller_locations(2, 1)&.first
      invocations[label] << { site: origin ? "#{origin.path.split('/app/').last}:#{origin.label}" : "(unknown)",
                              thread: Thread.current.object_id }
    end
    trace.enable
    begin
      yield
    ensure
      trace.disable
    end
    Observation.new(counts, invocations)
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
  # `.from("Caller#method")` binds the assertion to the CALLER AND THE THREAD. Without it, a block
  # that reaches the control by ANY route passes — which is how an inverted gate survived its own
  # proof. `.on_thread(t)` is for the deliberate cross-thread case.
  chain(:from) { |site| @site = site }
  chain(:on_thread) { |thread| @thread = thread }

  match do |observation|
    next false unless observation.evaluated?(target)

    @site.nil? || observation.evaluated_from?(target, @site, thread: @thread || Thread.current)
  end

  failure_message do |observation|
    if @site && observation.evaluated?(target)
      "expected #{target} to have been evaluated BY #{@site} on the asserting thread, but it was " \
        "only evaluated by: #{observation.invocations(target).map { |i| "#{i[:site]} (thread #{i[:thread]})" }.uniq.join(', ')}"
    else
      "expected #{target} to have been evaluated in this block, but it was not. Observed: #{observation}"
    end
  end
  failure_message_when_negated do |observation|
    "expected #{target} NOT to have been evaluated, but it ran #{observation.count(target)} time(s)"
  end
end
