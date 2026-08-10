# frozen_string_literal: true

require_relative "protected_effect_door"

# NO HUMAN-AUTHORIZED WF-005 COMMAND COMMITS A PROTECTED SIDE EFFECT WITHOUT RE-READING AUTHORITY
# (round 9, R9-3; antecedent corrected in D7).
#
# WHY THIS EXISTS RATHER THAN A THIRD BRANCH MATRIX. Round 8 named two bypass axes and round 9's
# repair drove both. Round 9's review then found a THIRD — `unless current || ...` — which survived
# the whole suite and committed a policy activation on revoked authority. A matrix of axes is a list,
# and a Boolean guard can always grow another operand, so the third round of "add the axis someone
# just thought of" would fail the same way.
#
# THE INVARIANT INSTEAD, AND WHY IT NEEDS NO AXES. Across the ENTIRE suite, whatever any example
# happens to drive:
#
#     a human-authorized WF-005 command that SUCCEEDS and COMMITS A PROTECTED SIDE EFFECT
#       must have evaluated CommandAuthorizer.authority_current?
#       and must have presented an AuthorityAttestation at its protected write.
#
# A bypass keyed to any axis — a scope, a Source count, a supersede path, a state, one nobody has
# thought of — produces a successful command that made a governed write and evaluated neither. It
# does not matter which example drives it: the suite has 2000+ examples and this watches all of them
# at once. The axis is irrelevant, which is the property two rounds of matrices could not buy.
#
# THE ANTECEDENT SAYS "PROTECTED SIDE EFFECT", NOT "WROTE" (D7). It used to say "WRITES", with a verb
# regex behind it, and the record explained that a replay needed no special case because it "WRITES
# NOTHING". Both halves were wrong in a way that only showed once the regex was corrected: the regex
# counted `SELECT ... FOR UPDATE` as a write, so an idempotent `CancelCrawl` replay — which executes
# no data-modifying statement at all — satisfied the antecedent through `lock_crawl`'s ROW LOCK.
#
# `:335` is where the right word already was: "a running privileged operation rechecks at each
# durable checkpoint and STOPS BEFORE THE NEXT PROTECTED SIDE EFFECT after revocation". The
# antecedent is now that, observed by `ProtectedEffectDoor` — PostgreSQL's own plan for the real
# statement, and the catalogue's own record of which relations carry product facts.
#
# THERE IS NO REPLAY EXEMPTION, AND THERE IS NO NEED FOR ONE. A replay returns the stored result and
# executes no statement whose plan modifies a guarded relation, so it falls outside the antecedent by
# what it does rather than by being named. A denial is outside it because it is not a success. Both
# are proved, not asserted: `spec/architecture/protected_effect_door_spec.rb`.
#
# THE HANDLER SET IS DERIVED FROM THE NAMESPACE, not listed here and not read off a directory: every
# class under `Workflows::Wf005::Handlers` is observed, however deeply nested and whichever ancestry
# exposes `call`. Human-authorization is then decided per execution, by whether the command
# authenticated a Session. A handler added later joins this rule by being what it is.
module AuthoritySentinel
  HANDLER_DIR = "app/workflows/wf005/handlers"

  Violation = Struct.new(:handler, :evaluated_recheck, :attested, :writes, :relations,
                         keyword_init: true) do
    def to_s
      "#{handler} SUCCEEDED and committed #{writes} protected side effect(s) " \
        "#{Array(relations).sort.join(', ')} with " \
        "authority_current? evaluated=#{evaluated_recheck} attestation_required=#{attested}"
    end
  end

  class << self
    def violations = (@violations ||= [])
    def armed? = @armed ||= false

    # EVERY WF-005 HANDLER IS OBSERVED (D5 family 4, R10-9).
    #
    # WHAT THIS REPLACED. The handler set was decided by matching each file's SOURCE against
    # `/authenticate\(session_id:/`. Measured on this branch that covered 3 OF 6 handlers, and a
    # merely reformatted call — the argument list wrapped across lines — does not match it. A handler
    # authenticating through a local variable, a helper, a splat or any unpredicted spelling was
    # silently OUTSIDE a rule whose whole point is that no axis escapes it. Worse, it left no trace
    # when it dropped one: a smaller covered set produces FEWER violations, so the suite goes greener
    # as the instrument goes blinder.
    #
    # Human-authorization is now decided by WHAT THE COMMAND DID: it is human-authorized when
    # `CommandAuthorizer#authenticate` RAN during it. That is the act the rule is actually about —
    # this command acted on a person's Session rather than on a durable action the platform minted —
    # it is observed at the CALLEE, and no spelling at the call site changes whether the callee ran.
    # A HANDLER JOINS THIS RULE BY BEING ONE, NOT BY WHERE ITS FILE SITS (round-15 architecture
    # finding A15-2).
    #
    # WHAT WAS OPEN. The set came from `Dir[app/workflows/wf005/handlers/*.rb]` — a NON-RECURSIVE
    # glob — plus a `File.basename.camelize` constant derivation. Measured: the same handler class
    # placed one directory deeper (`handlers/admin/`) was NOT discovered, so it authenticated a
    # Session, committed a protected side effect, re-read no authority, presented no attestation, and
    # the run was GREEN. The instrument also prepended into the INSTANCE ancestry alone, so a handler
    # exposing `def self.call` was never observed either. Both escapes are silent and both make the
    # suite greener, which is the direction nothing notices.
    #
    # THE SET IS NOW THE NAMESPACE, WALKED. Everything under `Workflows::Wf005::Handlers` that can be
    # CALLED — however deeply nested, nested inside another handler, whatever its file is named and
    # wherever it lives, and whichever ancestry exposes `call`. Eager loading is what makes the walk
    # complete rather than dependent on what earlier examples happened to autoload.
    def observed_handlers
      @observed_handlers ||= begin
        Rails.application.eager_load!
        handlers_under(Workflows::Wf005::Handlers).uniq.sort_by(&:name)
      end
    end

    # RECURSES INTO CLASSES TOO, AND DECIDES BY WHAT A CONSTANT CAN DO (round-16 architecture
    # observation O-1). The first version stopped at the first `Class`, so a handler nested INSIDE a
    # handler class escaped — the same shape as the directory glob that did not recurse, one level
    # in. A constant joins the rule when it answers `call` in either ancestry, which is what being an
    # entry point means; a namespace that answers nothing is walked through rather than collected.
    def handlers_under(namespace, seen = Set.new)
      namespace.constants.flat_map do |name|
        value = begin
          namespace.const_get(name)
        rescue NameError
          nil
        end
        next [] unless value.is_a?(Module)
        next [] unless seen.add?(value)

        nested = handlers_under(value, seen)
        entry_point?(value) ? [value, *nested] : nested
      end
    end

    def entry_point?(value)
      value.respond_to?(:call) || (value.is_a?(Class) && value.method_defined?(:call))
    end

    def arm!
      return if armed?

      PG::Connection.prepend(StatementObserver)
      IdentityAccess::Authorization::CommandAuthorizer.singleton_class.prepend(RecheckObserver)
      # THE HUMAN DOOR. Without this line `note_authentication` is never called, `f[:human]` is never
      # true, and `judge` returns at its first guard for EVERY command — the sentinel evaluates its
      # rule zero times while reporting no violations. It was missing, and the whole-suite emptiness
      # check below now covers the human predicate for exactly that reason.
      IdentityAccess::Authorization::CommandAuthorizer.prepend(AuthenticationObserver)
      Workflows::Wf005::AuthorityAttestation.singleton_class.prepend(AttestationObserver)
      observed_handlers.each { |handler| install_observer(handler) }
      @armed = true
    end

    # BOTH ANCESTRIES. `#call` and `def self.call` are both ways to be the entry point, and this
    # instrument used to see only the first — measured, a handler exposing the second ran entirely
    # unobserved (A15-2). Prepending to both costs nothing when a handler has only one.
    #
    # IT IS A METHOD SO IT CAN BE PROVED (round-17 architecture observation O-4). Inline in `arm!`,
    # the singleton half was bound by nothing: deleting it left the whole architecture suite green,
    # because every proof of the escape tested DISCOVERY rather than OBSERVATION. A spec can now
    # install the observer exactly as production does and drive a singleton entry point through it.
    def install_observer(handler)
      handler.prepend(CommandObserver)
      handler.singleton_class.prepend(CommandObserver)
    end

    # ACCOUNTING IS PER THREAD, NOT PER PROCESS (D5 family 4, R10-11).
    #
    # The counters lived in module state. Sidekiq drives handlers on worker threads and this
    # tranche's own concurrency proofs run two commands at once, so one thread's `ensure` restored
    # the other thread's frame: writes were attributed to the wrong command and, worse, a real
    # violation could be ERASED by a concurrent well-behaved command resetting the counters. A
    # sentinel whose accounting races reports whatever the scheduler chose.
    def frame = (Thread.current[:authority_sentinel_frame] ||= { depth: 0 })

    # NON-VACUITY COUNTERS, kept per process on purpose: they answer "did this instrument observe
    # anything at all across the run", which is a property of the run rather than of a thread.
    def observed_commands = (@observed_commands ||= 0)
    def observed_statements = (@observed_statements ||= 0)
    # Statements whose PLAN modifies a guarded relation. Counted separately from statements because
    # the antecedent is about protected side effects and the previous door could not tell the two
    # apart — it counted a `FOR UPDATE` lock as a write.
    def observed_governed_writes = (@observed_governed_writes ||= 0)
    # EVERY relation-modifying effect, governed or not. Counted separately so a proof can assert that
    # the two numbers DIFFER: an antecedent that counted its whole traffic would satisfy "at least one
    # protected side effect" forever while being exactly the over-broad rule D7 removed.
    def observed_effects = (@observed_effects ||= 0)
    # Commands judged HUMAN-AUTHORIZED. Counted separately because a sentinel that observes commands
    # and writes but never recognises a human one has an antecedent nothing satisfies, so its rule is
    # never evaluated and its silence means nothing.
    def observed_human_commands = (@observed_human_commands ||= 0)
    # WHICH HANDLERS ACTUALLY RAN. The rule is derived from EXECUTION, so a handler no example drives
    # is invisible to it by construction — a new handler could wait, write and never re-read authority
    # and this instrument would say nothing, which is exactly what PROOF 193's static census used to
    # catch. Requiring every discovered handler to have executed closes that without enumerating one.
    def executed_handlers = (@executed_handlers ||= Set.new)
    # Handlers observed to be human-authorized at least once, and those observed committing at least
    # one protected side effect. The gap between the two sets is the antecedent going unreached.
    def human_handlers = (@human_handlers ||= Set.new)
    def governed_writing_handlers = (@governed_writing_handlers ||= Set.new)

    # THE CENSUS. Every (handler, relation, operation, governed?, succeeded?) the run executed, with
    # a count. It is what makes the classification an OBSERVATION rather than a claim: after a run it
    # says exactly which relations each WF-005 command modified and how each was classified, and the
    # architecture gate reads it back against the catalogue.
    def census = (@census ||= Hash.new(0))

    def note_statement(sql)
      @observed_statements = observed_statements + 1
      effects = ProtectedEffectDoor.effects_of(sql)
      effects.nil? ? :unknown : effects
    end

    # THE SECOND ENTRY POINT, AND WHY THE DOOR NEEDED ONE (FU-51).
    #
    # Classification happens BEFORE execution — `StatementObserver` plans, then calls `super` — so the
    # only thing that can answer for a statement PostgreSQL would not plan, the command tag of the
    # statement that RAN, does not exist yet when `note_statement` is called. The plan verdict is
    # therefore carried across `super` and resolved here.
    def note_execution(sql, verdict, tag)
      verdict = resolve_by_tag(sql, tag) if verdict == ProtectedEffectDoor::NOT_PLANNABLE
      return if verdict == :outside_subject

      verdict == :unknown ? ProtectedEffectDoor.note_unplannable(sql, tag) : note_effects(verdict)
    end

    # WHERE THE UNPLANNABLE STATEMENT WAS EXECUTED DECIDES WHAT IT MEANS, and this is the judgement
    # FU-51 said would be the hard part of the repair.
    #
    # The invariant's subject is "a statement a WF-005 command executed". `note_effects` has been
    # frame-scoped since D5 for exactly that reason, and this limb is scoped the same way. The harness
    # runs `TRUNCATE ... RESTART IDENTITY CASCADE` over 26 tables after almost every example and would
    # otherwise report thousands of blind spots for its own reset — turning a repair that closes a
    # hole into a gate nothing can pass, which is how an instrument gets reverted rather than fixed.
    #
    # THE PRE-EXISTING BLIND SPOT KEEPS ITS GLOBAL SCOPE. A statement that executed but could not be
    # planned for a reason OTHER than "not optimizable" says the instrument itself is broken, not that
    # a statement was unclassifiable, so it still fails the run wherever it happens. Only the new
    # tag-decided limb is frame-scoped.
    def resolve_by_tag(sql, tag)
      case ProtectedEffectDoor.tag_verdict(tag)
      when :benign then []
      when :schema then frame[:depth].positive? ? :unknown : []
      else
        return :unknown if frame[:depth].positive?

        ProtectedEffectDoor.note_unclassified(tag)
        :outside_subject
      end
    end

    # Called only once the statement has actually executed: a statement PostgreSQL refused never
    # committed anything, and a plan is not an effect.
    #
    # EVERY effect is recorded, not only the governed ones — the census is what the architecture gate
    # reads back to check the classification, and a census holding only one side of a partition
    # cannot show the other side is right.
    def note_effects(effects)
      f = frame
      return unless f[:depth].positive?
      return if effects.empty?

      @observed_effects = observed_effects + effects.length
      governed = effects.count { |e| ProtectedEffectDoor.governed?(e.relation) }
      @observed_governed_writes = observed_governed_writes + governed
      f[:governed] += governed
      effects.each { |e| f[:relations] << [e.relation, e.operation] }
    end

    def command_tag(result)
      result.cmd_status if result.respond_to?(:cmd_status)
    rescue PG::Error
      nil
    end

    def note_authentication
      f = frame
      return unless f[:depth].positive?
      return if f[:human]

      f[:human] = true
      @observed_human_commands = observed_human_commands + 1
    end

    def note_recheck
      f = frame
      f[:evaluated] = true if f[:depth].positive?
    end

    def note_attestation
      f = frame
      f[:attested] = true if f[:depth].positive?
    end

    # One command execution, from entry to result, on this thread alone.
    def around_command(handler)
      f = frame
      outer = f.dup
      @observed_commands = observed_commands + 1
      executed_handlers << handler.name
      f.merge!(depth: f[:depth] + 1, governed: 0, evaluated: false, attested: false, human: false,
               relations: [])
      result = yield
      judge(handler, result, f)
      result
    ensure
      f.replace(outer)
    end

    # AN EMPTY CENSUS IS NOT SUCCESS, and this is callable so it can be proved directly rather than
    # only observed at suite end. Blinding the instrument makes the suite GREENER — a sentinel that
    # observes nothing records no violations — so a blind run must FAIL rather than quieten.
    def assert_observed!(commands: observed_commands, statements: observed_statements,
                         governed: observed_governed_writes, human: observed_human_commands,
                         undriven: observed_handlers.map(&:name) - executed_handlers.to_a,
                         unreached: unreached_handlers,
                         unplannable: ProtectedEffectDoor.unplannable,
                         unclassified: ProtectedEffectDoor.unclassified_tags,
                         mislabelled: lifecycle_but_unguarded)
      if human.zero?
        raise "AuthoritySentinel judged ZERO commands human-authorized across the entire suite; its " \
              "antecedent is never satisfied, `judge` returns at its first guard every time, and its " \
              "'no violations' result means nothing. The `AuthenticationObserver` door was missing " \
              "once and this is the check that would have said so."
      end
      unless undriven.empty?
        raise "#{undriven.length} WF-005 handler(s) were never executed by any example, so this " \
              "instrument — which derives its rule from EXECUTION — cannot have judged them: " \
              "#{undriven.join(', ')}. A handler that waits, writes and never re-reads authority " \
              "would be invisible here, which is the obligation PROOF 193's static census carried."
      end
      if commands.zero?
        raise "AuthoritySentinel observed ZERO WF-005 command executions across the entire suite; " \
              "its handler discovery is blind and its 'no violations' result means nothing"
      end
      if statements.zero?
        raise "AuthoritySentinel observed ZERO statements across the entire suite; its door is " \
              "blind and its 'no violations' result means nothing"
      end
      # THE ANTECEDENT MUST BE REACHED, NOT MERELY DEFINED. Narrowing "wrote" to "committed a
      # protected side effect" is only an improvement if the narrower antecedent is still satisfied
      # by the real transitions. Zero governed writes means the rule was never evaluated and the
      # narrowing turned the invariant off.
      if governed.zero?
        raise "AuthoritySentinel observed ZERO protected side effects across the entire suite; the " \
              "antecedent is never satisfied, so narrowing it from 'wrote' has switched the " \
              "invariant off rather than sharpened it"
      end
      unless unreached.empty?
        raise "#{unreached.length} human-authorized WF-005 handler(s) were never observed committing " \
              "a protected side effect: #{unreached.join(', ')}. Either the handler's transition is " \
              "never driven, or the door cannot see the relation it writes — and both make this " \
              "instrument silent about exactly the command the rule exists for."
      end
      unless unplannable.empty?
        raise "#{unplannable.length} statement(s) executed successfully that PostgreSQL could not " \
              "plan, so the door has no answer for them and 'no protected side effect' is a guess:\n" \
              "#{unplannable.keys.join("\n")}"
      end
      # THE FU-51 LIMB IS REACHED, NOT MERELY WRITTEN. Before the repair every statement PostgreSQL
      # refused to plan was returned as `[]` — "no write" — including `TRUNCATE`, which is how the
      # harness empties 26 governed tables between examples. If this census is EMPTY across a whole
      # suite then no unplannable statement was ever resolved by its command tag, which means either
      # the tag path is unreachable or the allowlist swallowed everything, and in both cases the
      # repair is decorative. The suite executes thousands of `TRUNCATE`s, so an empty census here is
      # a broken instrument rather than a quiet one.
      if unclassified.empty?
        raise "AuthoritySentinel resolved ZERO unplannable statements by command tag across the " \
              "entire suite, so the limb that stopped the door reading 'no plan' as 'no write' was " \
              "never reached and cannot be shown to work"
      end
      return if mislabelled.empty?

      # THE CLASSIFICATION'S OWN CHECK, AGAINST A PROPERTY IT DOES NOT USE. Governed is derived from
      # `pg_trigger`; this reads `pg_attribute`. A relation a WF-005 command wrote that carries a
      # `state` lifecycle and NO PostgreSQL guard is a product aggregate the derivation would call
      # command evidence — and that direction is silent, because a narrower antecedent makes the run
      # greener rather than louder.
      raise "#{mislabelled.length} relation(s) written by WF-005 carry product lifecycle state and " \
            "no PostgreSQL guard, so the catalogue derivation classifies them as command evidence: " \
            "#{mislabelled.join(', ')}"
    end

    def lifecycle_but_unguarded
      observed_relations(governed: false).select { |r| ProtectedEffectDoor.lifecycle?(r) }
    end

    # HANDLERS THE ANTECEDENT NEVER REACHED, narrowed to the ones DISCOVERY FOUND. `around_command` is callable directly, and this instrument's own proofs call it with
    # synthetic doubles to exercise the frame — those are not WF-005 handlers and have no transition
    # to commit, so including them made the whole-suite check fail on a test double rather than on a
    # production path. The narrowing is derived from the same discovery the rule uses — the namespace
    # walk, not the directory it used to be — rather than from a list of names to excuse. (The narrowing is derived from the same discovery the rule uses,
    # which is now the namespace walk rather than the directory it used to be.)
    def unreached_handlers
      (human_handlers & observed_handlers.map(&:name).to_set).to_a - governed_writing_handlers.to_a
    end

    # Relations the run observed on each side of the classification, for the architecture gate that
    # checks the catalogue derivation against the complementary column shape. Derived from the census
    # rather than listed, so the gate reads what the repository actually executed.
    def observed_relations(governed:)
      census.keys.select { |(_h, _r, _o, g, _s)| g == governed }.map { |k| k[1] }.uniq.sort
    end

    def judge(handler, result, f)
      succeeded = result.respond_to?(:success?) && result.success?
      f[:relations].uniq.each do |(relation, operation)|
        census[[handler.name, relation, operation, ProtectedEffectDoor.governed?(relation), succeeded]] += 1
      end
      # NOT HUMAN-AUTHORIZED: a platform-minted action (a `crawl_fetch_due` delivery) carries no
      # Session, so `authenticate` never ran and :335 does not govern it.
      return unless f[:human]

      human_handlers << handler.name
      governed_writing_handlers << handler.name if f[:governed].positive?
      return unless succeeded
      return unless f[:governed].positive?
      return if f[:evaluated] && f[:attested]

      violations << Violation.new(handler: handler.name, evaluated_recheck: f[:evaluated],
                                  attested: f[:attested], writes: f[:governed],
                                  relations: f[:relations].map(&:first).uniq)
    end
  end

  # PREPENDED INTO BOTH ANCESTRIES, so `#call` and `def self.call` are both observed. `self` is the
  # INSTANCE in the first case and the handler itself in the second, and the frame is labelled with
  # the handler either way.
  #
  # `is_a?(Module)`, NOT `is_a?(Class)` (round-17). A handler exposing `def self.call` on a MODULE
  # took the instance branch, so the frame was labelled `Module` — the observer fired, the census
  # recorded a handler called "Module", and `executed_handlers` never contained the real name, which
  # is the completeness limb that would have noticed the handler was never driven.
  module CommandObserver
    def call(...)
      AuthoritySentinel.around_command(is_a?(Module) ? self : self.class) { super }
    end
  end

  # BOTH DOORS THE REPOSITORY USES, AND THE PLAN IS TAKEN BEFORE THE STATEMENT RUNS. `exec_params`
  # carries every store statement; `exec` carries `txid_current()` and `clock_timestamp()`. Planning
  # first and counting after means a statement PostgreSQL REFUSED is never counted as an effect,
  # while a statement it could not plan at all is recorded as a blind spot rather than as a read.
  # THE PLAN IS TAKEN BEFORE THE STATEMENT RUNS AND THE TAG IS READ AFTER IT (FU-51). Planning first
  # and counting after means a statement PostgreSQL REFUSED is never counted as an effect; reading the
  # tag after means a statement PostgreSQL would not PLAN is still answered, by the statement itself,
  # instead of being assumed to be a read.
  #
  # `cmd_status` IS READ DEFENSIVELY AND ITS ABSENCE IS LOUD. `PG::Connection#exec` returns the
  # BLOCK's value when handed one, so a caller using the block form would leave no `PG::Result` here.
  # No caller in this repository does, and rather than wrap a block — which would change when PG
  # clears the result, an instrument altering what it observes — a value that cannot report a tag
  # yields `nil`, which `tag_verdict` calls `:unknown`. That is the fail-safe direction: a blind spot
  # inside a command frame, never a silent "no write".
  module StatementObserver
    def exec_params(sql, *, &)
      return super if ProtectedEffectDoor.classifying?

      effects = AuthoritySentinel.note_statement(sql)
      result = super
      AuthoritySentinel.note_execution(sql, effects, AuthoritySentinel.command_tag(result))
      result
    end

    def exec(sql, *, &)
      return super if ProtectedEffectDoor.classifying?

      effects = AuthoritySentinel.note_statement(sql)
      result = super
      AuthoritySentinel.note_execution(sql, effects, AuthoritySentinel.command_tag(result))
      result
    end
  end

  # HUMAN-AUTHORIZATION, OBSERVED AT THE CALLEE. No call-site spelling changes whether this ran.
  module AuthenticationObserver
    def authenticate(...)
      AuthoritySentinel.note_authentication
      super
    end
  end

  module RecheckObserver
    def authority_current?(...)
      AuthoritySentinel.note_recheck
      super
    end
  end

  module AttestationObserver
    def require!(...)
      AuthoritySentinel.note_attestation
      super
    end
  end
end

RSpec.configure do |config|
  config.before(:suite) { AuthoritySentinel.arm! }

  # JUDGED OVER THE WHOLE SUITE, outside any one example — because the defect this catches is a path
  # nobody wrote an example for, so no example can be the thing that looks for it.
  # AN EMPTY CENSUS IS NOT SUCCESS. If the instrument observed no commands or no protected side
  # effects across the whole run it did not check anything, and reporting "no violations" would be a
  # green result from a gate that never looked. Removing either observer makes the run FAIL here
  # rather than pass.
  config.after(:suite) do
    # A WHOLE-SUITE PROPERTY. A run of one spec file legitimately drives no WF-005 command, so the
    # emptiness check applies only when the whole suite was loaded — otherwise every narrow gate in
    # the manifest would fail for having been narrow. The blindness this catches is a property of the
    # RUN that certifies the tranche, and that run is always the full suite.
    if AuthoritySentinel.armed? &&
       RSpec.configuration.files_to_run.length >= Dir[Rails.root.join("spec/**/*_spec.rb")].length
      AuthoritySentinel.assert_observed!
    end

    next if AuthoritySentinel.violations.empty?

    raise ":335/SEC-REQ-004/005 — #{AuthoritySentinel.violations.length} human-authorized WF-005 " \
          "command(s) succeeded and committed a protected side effect without re-reading current " \
          "authority:\n#{AuthoritySentinel.violations.map(&:to_s).uniq.join("\n")}"
  end
end
