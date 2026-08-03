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
