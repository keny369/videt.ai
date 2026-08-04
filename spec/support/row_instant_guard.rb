# frozen_string_literal: true

# ONE DECODER AND ONE BOUNDARY, ENFORCED ON THE VALUE RATHER THAN ON THE SYNTAX (round 9, R9-5, R9-7).
#
# THREE ROUNDS OF SYNTAX RULES, THREE ESCAPES. Round 6 banned four AST spellings and round 7 walked
# nine forms past it. Round 7 banned two NAMES and round 8 walked thirty-of-forty-one forms past it.
# Round 8 banned a receiver SHAPE and round 9 walked four binding classes past it — multiple
# assignment, block-pass symbol procs, container laundering, and receivers the analysis had no case
# for. Round 9 also defeated the boundary's single-owner rule with one method indirection, because
# that rule was a per-line text scan and an endpoint method severs a text scan.
#
# THE PATTERN IS NOT THAT THE LISTS WERE TOO SHORT. It is that syntax was being asked to decide a
# question about VALUES: where did this instant come from, and who is allowed to interpret it. Ruby
# has unbounded ways to move a value from one name to another, so any rule phrased over spellings has
# unbounded escapes.
#
# SO THE RULE MOVES ONTO THE VALUE. A `timestamptz` read by WF-005 code arrives wrapped, and the
# wrapper answers exactly two audiences:
#
#   * `Platform::PgInstant`, the one authorised decoder, which unwraps it;
#   * everything else, which gets an exception naming the contract.
#
# Assignment, multiple assignment, `&:symbol`, containers, aliases, helper methods, method
# indirection, a receiver form nobody has thought of — none of them matter, because the taint IS the
# object and travels wherever the object travels. Comparison operators raise for the same reason:
# `:442`'s boundary has one owner (`PgInstant.expired?`), and a caller that reimplements it — however
# many helpers it hides behind — is comparing a wrapper and raises.
#
# THIS IS A TEST-MODE INVARIANT, NOT PRODUCTION BEHAVIOUR. It wraps what the connection returns to
# WF-005 code only while the suite runs, so production carries no wrapper and no cost; what the suite
# proves is that no WF-005 path DEPENDS on interpreting a row instant itself.
module RowInstantGuard
  class Violation < StandardError; end

  # The WF-005 corpus, whose contract this is. A read issued from anywhere else is untouched.
  WF005_SOURCE = %r{/app/workflows/wf005/}
  # The authorised decoder, allowed to unwrap.
  DECODER = %r{/app/platform/pg_instant\.rb}
  # THE DEADLINE HAS A NARROWER OWNER STILL. Every other instant may be decoded by `PgInstant`, but
  # `deadline_at` may only be interpreted by `Platform::RunDeadline`, which exposes :442's three
  # questions and no comparison. That is what closes round 9's R9-7: the lens defeated the previous
  # single-owner rule by hiding the decode behind one helper method, and there is now no decode to
  # hide — a caller that reaches for the raw deadline raises, however many helpers it reaches through.
  DEADLINE_COLUMN = "deadline_at"
  DEADLINE_OWNER = %r{/app/platform/run_deadline\.rb}
  # PostgreSQL's own type oid for `timestamp with time zone`.
  TIMESTAMPTZ_OID = 1184

  # A `timestamptz` value on its way to WF-005 code.
  #
  # It is deliberately NOT a delegator: anything not explicitly answered raises, so a form nobody
  # anticipated fails closed. That is the inversion three rounds of allowlists never achieved.
  class RowInstant < BasicObject
    def initialize(raw, column) = (@raw = raw; @column = column)

    # `PgInstant` unwraps by asking for the raw value. Any other caller reaching for it is decoding.
    def __raw__
      ::RowInstantGuard.owner_calling?(@column) or
        ::Kernel.raise(::RowInstantGuard::Violation,
                       "#{@column} was decoded outside its owner")
      @raw
    end

    def nil? = false
    def is_a?(klass) = @raw.is_a?(klass)
    def kind_of?(klass) = @raw.is_a?(klass)
    def instance_of?(klass) = @raw.instance_of?(klass)
    def class = @raw.class
    def frozen? = true
    def inspect = "#<RowInstant #{@column}>"

    # EVERYTHING ELSE IS A DECODE OR A COMPARISON, and both belong to owners this value is not.
    def method_missing(name, *args, &block)
      if ::RowInstantGuard.owner_calling?(@column)
        return @raw.__send__(name, *args, &block)
      end

      ::Kernel.raise(
        ::RowInstantGuard::Violation,
        "#{@column} received ##{name} outside its owner. A PostgreSQL instant read by WF-005 has " \
        "ONE decoder (`Platform::PgInstant.utc`), and `deadline_at` has a narrower one still " \
        "(`Platform::RunDeadline`, which answers :442's three questions and exposes no comparison). " \
        "Interpreting or comparing the raw value here is the second implementation those owners " \
        "exist to prevent — including behind a helper method, which is how round 9 defeated the " \
        "rule this replaces."
      )
    end

    def respond_to_missing?(_name, _private = false) = true
  end

  class << self
    def armed? = @armed ||= false
    def violations = (@violations ||= [])

    # WHAT TO WRAP IS READ OFF THE WIRE, NOT NAMED HERE. `PG::Result` reports each field's TYPE oid
    # and the TABLE oid it came from, so the rule is "a `timestamptz` belonging to a WF-005 crawl
    # table" — derived per result, from PostgreSQL's own answer. A column added by a later migration
    # joins by existing; a same-named column on another subsystem's table (F-05's reservations carry
    # `started_at` too) is untouched, because the table oid is different.
    def crawl_table_oids
      @crawl_table_oids ||= DbInspector.all(<<~SQL).map { |r| r["oid"].to_i }.to_set.freeze
        SELECT c.oid::text AS oid
        FROM pg_class c
        JOIN pg_namespace n ON n.oid = c.relnamespace
        WHERE n.nspname = 'public' AND c.relkind = 'r' AND c.relname LIKE 'crawl%'
      SQL
    end

    def arm!
      return if armed?

      crawl_table_oids
      PG::Result.prepend(ResultWrapping)
      @armed = true
    end

    # Is the immediate caller the authorised decoder? Read from the live stack, so no flag can be
    # left set and no caller can claim to be `PgInstant` without being it.
    def owner_calling?(column)
      owner = column == DEADLINE_COLUMN ? DEADLINE_OWNER : DECODER
      (::Kernel.caller_locations(1, 14) || []).any? { |l| l.absolute_path.to_s.match?(owner) }
    end

    # Wrap only for reads issued by WF-005 code — the corpus whose contract this is.
    def wf005_reading?
      (::Kernel.caller_locations(1, 40) || []).any? { |l| l.absolute_path.to_s.match?(WF005_SOURCE) }
    end

    # NON-VACUITY IS COUNTED, not assumed: a guard that wrapped nothing would let every proof below
    # pass while observing nothing, which is the failure class this tranche exists to end.
    def wrapped = (@wrapped ||= 0)

    def wrap(value, column)
      return value if value.nil?

      @wrapped = wrapped + 1
      RowInstant.new(value, column)
    end
  end

  module ResultWrapping
    def to_a
      rows = super
      return rows unless RowInstantGuard.armed?

      # THE CHEAP QUESTION FIRST. Field metadata is already in hand; walking the call stack is not,
      # and this runs for every result the suite produces. Asking "does this result even contain a
      # guarded instant?" before "who is reading it?" keeps the guard off the hot path entirely for
      # the large majority of statements, which carry no `timestamptz` from a crawl table at all.
      wrapped = (0...nfields).filter_map do |i|
        next unless ftype(i) == RowInstantGuard::TIMESTAMPTZ_OID
        next unless RowInstantGuard.crawl_table_oids.include?(ftable(i))

        fname(i)
      end
      return rows if wrapped.empty?
      return rows unless RowInstantGuard.wf005_reading?

      rows.map do |row|
        next row unless row.is_a?(::Hash)

        row.each_with_object({}) do |(k, v), out|
          out[k] = wrapped.include?(k) ? RowInstantGuard.wrap(v, k) : v
        end
      end
    end
  end
end

RSpec.configure do |config|
  config.before(:suite) { RowInstantGuard.arm! }
end
