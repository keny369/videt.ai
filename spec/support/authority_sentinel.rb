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
  # The call that makes a command human-authorized: it acts on a person's Session rather than on a
  # durable action minted by the platform.
  HUMAN_AUTHORIZATION = /authenticate\(session_id:/

  Violation = Struct.new(:handler, :evaluated_recheck, :attested, :writes, keyword_init: true) do
    def to_s
      "#{handler} SUCCEEDED and issued #{writes} write(s) with " \
        "authority_current? evaluated=#{evaluated_recheck} attestation_required=#{attested}"
    end
  end

  class << self
    def violations = (@violations ||= [])
    def armed? = @armed ||= false

    # Handlers that authenticate a Session, read from the source rather than named here.
    def human_authorized_handlers
      @human_authorized_handlers ||= Dir[Rails.root.join(HANDLER_DIR, "*.rb")].sort.filter_map do |file|
        next unless File.read(file).match?(HUMAN_AUTHORIZATION)

        constant_for(file)
      end
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
      human_authorized_handlers.each { |handler| handler.prepend(CommandObserver) }
      @armed = true
    end

    def note_write(sql)
      return unless @depth.to_i.positive?
      return unless sql.match?(/\A\s*(INSERT|UPDATE|DELETE)\b/i)

      @writes += 1
    end

    def note_recheck
      @evaluated = true if @depth.to_i.positive?
    end

    def note_attestation
      @attested = true if @depth.to_i.positive?
    end

    # One command execution, from entry to result.
    def around_command(handler)
      outer = [@depth, @writes, @evaluated, @attested]
      @depth = @depth.to_i + 1
      @writes = 0
      @evaluated = false
      @attested = false
      result = yield
      judge(handler, result)
      result
    ensure
      @depth, @writes, @evaluated, @attested = outer
    end

    def judge(handler, result)
      return unless result.respond_to?(:success?) && result.success?
      return unless @writes.positive?
      return if @evaluated && @attested

      violations << Violation.new(handler: handler.name, evaluated_recheck: @evaluated,
                                  attested: @attested, writes: @writes)
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
  config.after(:suite) do
    next if AuthoritySentinel.violations.empty?

    raise ":335/SEC-REQ-004/005 — #{AuthoritySentinel.violations.length} human-authorized WF-005 " \
          "command(s) succeeded and wrote without re-reading current authority:\n" \
          "#{AuthoritySentinel.violations.map(&:to_s).uniq.join("\n")}"
  end
end
