# frozen_string_literal: true

# NO HUMAN-AUTHORIZED WF-005 COMMAND COMMITS WITHOUT RE-READING AUTHORITY (round 9, R9-3).
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
#     a human-authorized WF-005 command that SUCCEEDS and WRITES
#       must have evaluated CommandAuthorizer.authority_current?
#       and must have presented an AuthorityAttestation at its protected write.
#
# A bypass keyed to any axis — a scope, a Source count, a supersede path, a state, one nobody has
# thought of — produces a successful writing command that evaluated neither. It does not matter which
# example drives it: the suite has 2000+ examples and this watches all of them at once. The axis is
# irrelevant, which is the property two rounds of matrices could not buy.
#
# A REPLAY IS CORRECTLY EXEMPT and is not special-cased: it returns the stored payload and WRITES
# NOTHING, so it never satisfies the antecedent. A denial is exempt because it is not a success.
#
# THE HANDLER SET IS DERIVED FROM THE SOURCE, not listed here: a WF-005 handler is human-authorized
# when it authenticates a Session. A handler added later joins this rule by being what it is.
module AuthoritySentinel
  HANDLER_DIR = "app/workflows/wf005/handlers"

  Violation = Struct.new(:handler, :evaluated_recheck, :attested, :writes, keyword_init: true) do
    def to_s
      "#{handler} SUCCEEDED and issued #{writes} write(s) with " \
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
    def observed_handlers
      @observed_handlers ||= Dir[Rails.root.join(HANDLER_DIR, "*.rb")].sort.filter_map { |f| constant_for(f) }
    end

    def constant_for(file)
      name = File.basename(file, ".rb").camelize
      Workflows::Wf005::Handlers.const_get(name)
    rescue NameError
      nil
    end

    def arm!
      return if armed?

      @depth = 0
      @writes = 0
      @evaluated = false
      @attested = false
      PG::Connection.prepend(WriteObserver)
      IdentityAccess::Authorization::CommandAuthorizer.singleton_class.prepend(RecheckObserver)
      Workflows::Wf005::AuthorityAttestation.singleton_class.prepend(AttestationObserver)
      observed_handlers.each { |handler| handler.prepend(CommandObserver) }
      @armed = true
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
    def observed_writes = (@observed_writes ||= 0)

    def note_write(sql)
      f = frame
      return unless sql.match?(/\A\s*(INSERT|UPDATE|DELETE)\b/i)

      @observed_writes = observed_writes + 1
      return unless f[:depth].positive?

      f[:writes] += 1
    end

    def note_authentication
      f = frame
      f[:human] = true if f[:depth].positive?
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
      f.merge!(depth: f[:depth] + 1, writes: 0, evaluated: false, attested: false, human: false)
      result = yield
      judge(handler, result, f)
      result
    ensure
      f.replace(outer)
    end

    # AN EMPTY CENSUS IS NOT SUCCESS, and this is callable so it can be proved directly rather than
    # only observed at suite end. Blinding the instrument makes the suite GREENER — a sentinel that
    # observes nothing records no violations — so a blind run must FAIL rather than quieten.
    def assert_observed!(commands: observed_commands, writes: observed_writes)
      if commands.zero?
        raise "AuthoritySentinel observed ZERO WF-005 command executions across the entire suite; " \
              "its handler discovery is blind and its 'no violations' result means nothing"
      end
      return unless writes.zero?

      raise "AuthoritySentinel observed ZERO writes across the entire suite; its write door is " \
            "blind and its 'no violations' result means nothing"
    end

    def judge(handler, result, f)
      # NOT HUMAN-AUTHORIZED: a platform-minted action (a `crawl_fetch_due` delivery) carries no
      # Session, so `authenticate` never ran and :335 does not govern it.
      return unless f[:human]
      return unless result.respond_to?(:success?) && result.success?
      return unless f[:writes].positive?
      return if f[:evaluated] && f[:attested]

      violations << Violation.new(handler: handler.name, evaluated_recheck: f[:evaluated],
                                  attested: f[:attested], writes: f[:writes])
    end
  end

  module CommandObserver
    def call(...)
      AuthoritySentinel.around_command(self.class) { super }
    end
  end

  # The same single door, with the same disclosed limitation as the census: a prepared-statement
  # write would be invisible. The corpus uses neither.
  module WriteObserver
    def exec_params(sql, *, &)
      AuthoritySentinel.note_write(sql.to_s)
      super
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
  # AN EMPTY CENSUS IS NOT SUCCESS. If the instrument observed no commands or no writes across the
  # whole run it did not check anything, and reporting "no violations" would be a green result from a
  # gate that never looked. Removing either observer makes the run FAIL here rather than pass.
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
          "command(s) succeeded and wrote without re-reading current authority:\n" \
          "#{AuthoritySentinel.violations.map(&:to_s).uniq.join("\n")}"
  end
end
