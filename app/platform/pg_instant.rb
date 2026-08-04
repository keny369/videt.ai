# frozen_string_literal: true

require "time"

module Platform
  # Read a PostgreSQL `timestamptz` whose Ruby encoding depends on the CONNECTION, not on the value.
  #
  # THIS IS `Platform::PgBool`'S SIBLING AND IT EXISTS FOR THE SAME REASON. An ActiveRecord-owned
  # connection carries type mapping and yields a `Time` with microsecond precision; a bare `PG.connect`
  # — the shape several test harnesses and the transport connection use — yields text. The rule was
  # already written down, twice, in F-04:
  #
  #   `Platform::ScheduledActions::Store#to_time` — "A pooled Rails connection decodes timestamps and
  #   bytea for us; a bare libpq connection returns text. Accept either."
  #
  # AND IT FAILS SILENTLY, WHICH IS WHY IT NEEDS AN OWNER. The idiom that ignores the rule is
  # `Time.parse(value.to_s)`. On text it is exact. On a `Time` it round-trips through `Time#to_s`,
  # which FORMATS TO WHOLE SECONDS — so the microseconds are gone before `parse` ever sees them, and
  # the result is a value that is correct in every test fixture and wrong in production. Every fixture
  # instant in this repository is a whole second, and `spec/support/db_inspector.rb` and
  # `spec/support/pg_test_connection.rb` open bare connections with no type map, so the truncating
  # branch is the one branch the suite systematically cannot reach.
  #
  # THE COST, MEASURED. `S-07-009_ACCEPTANCE_REVIEW.md` round 4 finding R4-1: comparing `now` against a
  # truncated `deadline_at` inverted BOTH halves of WORKFLOW_SPECIFICATIONS.md :458 at once — the
  # 60-minute tie never fired at the real boundary, and cancellations "committed strictly before" the
  # checkpoint were refused for up to 999,999 microseconds. Round 5 finding R5-2 then established that
  # the repair had fixed ONE of thirteen live sites and made its helper private, so a checkpoint could
  # still terminalize a still-running Crawl up to a second early.
  #
  # WHY THIS IS A MODULE FUNCTION AND NOT A METHOD ON A CLOCK. It decodes a value that already exists;
  # it reads no clock and injects nothing. `Platform::Clock` is an injected time SOURCE and is a
  # different concept — conflating them would give this rule a constructor it does not need and put a
  # decode behind a seam that exists for determinism.
  #
  # NOT USED BY F-04. `ScheduledActions::Store#to_time` and `ScheduledActions::Identity#instant` already
  # implement this correctly with the same type dispatch, and both are FROZEN paths
  # (`AutonomousBuild::FrozenContracts.frozen_path?` is true for `app/platform/scheduled_actions/`).
  # They are left exactly as they are: repointing a correct implementation on a frozen path would be a
  # mandatory human escalation spent on a defect that does not exist.
  module PgInstant
    module_function

    # The exact UTC instant, from either encoding. Nil in, nil out — a nullable column stays nullable.
    #
    # `getutc` rather than `utc`: `Time#utc` MUTATES its receiver, and these values are read straight
    # out of a result row that a caller may read again.
    def utc(value)
      return nil if value.nil?
      return value.getutc if value.respond_to?(:getutc)

      Time.parse(value.to_s).getutc
    end

    # THE INSTANT A DECISION IS MADE AT, AFTER THE TRANSACTION HAS WAITED FOR A LOCK (R6-1, R6-5,
    # R6-6; owner ruling 1 of the round-6 programme). PostgreSQL computes it; nothing here reads a
    # clock.
    #
    # WHY THIS EXISTS. `Admission`, `CancelCrawl` and `CompleteCrawl` each capture an instant, then
    # block on `crawl-frontier:<crawl>` or on `crawls FOR UPDATE`, then decide. The wait is unbounded
    # — it lasts as long as the transaction ahead of it holds the lock — and all three used the
    # instant they entered with. Round 6 reproduced the consequence on real PostgreSQL: a frontier
    # lock held until `clock_timestamp()` was past `deadline_at`, after which Admission still
    # admitted, claimed a frontier row and reserved 10,485,760 bytes. The same stale value let an
    # entitlement whose lease expired during the wait pass `reservation_executing?`, and let
    # `Entitlement::Service#commit` commit a reservation whose effective deadline the durable
    # terminal point had already passed. :442's "no new request starts", :458's boundary and :551's
    # strict-before lease rule are all decided by this one value.
    #
    # WHY IT IS AN ADVANCE AND NOT `clock_timestamp()` ITSELF, which is the subtle half. Every
    # instant this value is compared against was WRITTEN BY AN APPLICATION CLOCK: `crawls.deadline_at`
    # and `crawls.started_at` come from `CrawlStartStore#start`'s `now`, and
    # `entitlement_reservations.lease_due` from F-05's. `CrawlHostGateStore#reservation_executing?`
    # already states the rule this obeys — "F-05 owns the reservation lifecycle and is `now:`-driven
    # throughout, so this must agree with it; two surfaces judging one reservation against two
    # different clocks would disagree about whether a run is still metered." Substituting a raw
    # `clock_timestamp()` reading would judge an application-clock deadline on the database's own
    # axis, which is a SECOND clock rather than a corrected one, and it would make every deadline
    # boundary depend on host-to-database skew.
    #
    # So PostgreSQL measures the thing that was actually missing — HOW LONG THIS TRANSACTION WAITED —
    # and adds it, in the database, at microsecond precision, to the instant the caller entered with.
    # `transaction_timestamp()` is fixed at BEGIN and `clock_timestamp()` advances inside the
    # transaction, so their difference is exactly the elapsed time this transaction has spent alive,
    # which for a handler whose first act is to take its locks is the wait. One axis, one clock
    # reading, no application measurement of elapsed time.
    #
    # IT NEVER GOES BACKWARDS, because the difference is non-negative by construction. A handler that
    # did not wait gets its own instant back plus the microseconds it took to get here, so the
    # non-contended path is unchanged and no proof that depends on a fixed clock loses its anchor.
    #
    # THE ANCHOR IS AN ARGUMENT, NOT `transaction_timestamp()` (round 7, C-1). The first version
    # measured from BEGIN, which silently assumed the caller captured its instant AT BEGIN. That is
    # true of `CancelCrawl` and `CompleteCrawl` and false of the one caller that matters most:
    # `CrawlDriver#advance` captures `now` at the top of the pass and then performs the robots fetch
    # and sitemap discovery OUTSIDE every transaction — up to eleven bounded requests by
    # `EnsureRobots`' own accounting — before handing that same instant to `Admission`. Round 7
    # reproduced the consequence: 1.5 seconds spent AFTER `BEGIN` correctly refused a run past its
    # deadline, while the identical 1.5 seconds spent BEFORE `BEGIN` admitted it and reserved
    # 10,485,760 bytes. Equivalent elapsed time must produce an equivalent decision, and it cannot
    # while the measurement starts at a boundary the caller may reach late.
    #
    # So `anchored_at` names WHERE `entered_with` WAS TRUE, and the elapsed span is measured from
    # there. `transaction_timestamp()` remains the default because it is the correct anchor for a
    # caller that captures its instant inside its own unit of work, which every command handler does;
    # it is a default, not an assumption, and `Admission` is proved to supply its own.
    def after_wait(connection, entered_with:, anchored_at: nil)
      value = connection.exec_params(
        "SELECT $1::timestamptz + (clock_timestamp() - COALESCE($2::timestamptz, transaction_timestamp())) " \
        "AS decided_at",
        [entered_with.getutc.iso8601(6), anchored_at&.getutc&.iso8601(6)]
      ).getvalue(0, 0)
      utc(value)
    end

    # THE DATABASE INSTANT A CALLER'S OWN `now` WAS TRUE AT, captured so a later `after_wait` can
    # measure the whole window rather than only the part inside a transaction. It is read from the same
    # clock `after_wait` later reads, so the two are on one axis and their difference is a real elapsed
    # span rather than a comparison across clocks.
    def anchor(connection)
      utc(connection.exec("SELECT clock_timestamp() AS anchored_at").getvalue(0, 0))
    end

    # HAS THIS DEADLINE PASSED? :442 SAYS "AT 60 ELAPSED MINUTES", SO EQUALITY IS EXPIRY (round 8, R8-9).
    #
    # THE COMPARISON HAD THREE COPIES AND NO PROOF. `Admission#wall_clock_expired?`,
    # `CrawlDriver#within_wall_clock?` and `DiscoverSitemaps`' deadline check each spelled out their
    # own `<=` or `>` against `deadline_at`, and weakening `Admission`'s from `<=` to `<` — which moves
    # :442's boundary in the direction of admitting a run that is over — survived the ENTIRE repository
    # suite. It survived because no proof could construct the case: the instant those three compare is
    # produced by `after_wait`, whose advance is a number of microseconds nobody can predict, so exact
    # equality is unreachable from outside. A boundary that cannot be constructed cannot be defended,
    # and three copies of it are three chances to get it wrong.
    #
    # So the boundary is ONE function, at the module that already owns what a PostgreSQL instant
    # means, and it is exactly testable: `spec/platform/pg_instant_spec.rb` drives microsecond-precise
    # operands straight at it, and `spec/acceptance/wf005_pass_anchor_spec.rb` drives a real pass
    # entering exactly AT its deadline through the real handler. Round 4's R4-1 found this same
    # boundary broken once already, by TRUNCATION rather than by comparison — hence `utc` on both
    # sides, which is the reason this module exists at all.
    #
    # NIL IS NOT EXPIRED. A run with no deadline has no boundary to cross; all three callers already
    # treated NULL that way, and the rule is now stated once instead of three times.
    def expired?(deadline, at:)
      return false if deadline.nil?

      utc(deadline) <= utc(at)
    end

    # Whole elapsed minutes between two instants, floored — :442's "60 elapsed minutes" measure.
    #
    # It lives here because both of its callers used to derive it from a TRUNCATED `started_at`, which
    # let a 59.99-minute run report 60. Given exact operands the floor is the only rounding, which is
    # what the contract asks for.
    def elapsed_minutes(from, to)
      started = utc(from)
      return 0 if started.nil?

      ((utc(to) - started) / 60).floor
    end
  end
end
