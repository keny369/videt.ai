# frozen_string_literal: true

# F-05 review hardening (ADR-026; DECISIONS ADR-075). Three defence-in-depth schema tightenings the
# five-lens review surfaced on 20260727120120:
#   1. concurrency lens — a DB hard-cap backstop so reserved + committed can never exceed the window's
#      hard limit even if a future write path bypassed the advisory lock + InterimPolicy.classify
#      (today the hard limit is enforced only in application code).
#   2. contract/architecture lenses — WORKFLOW :543 mandates the Entitlement Decision's idempotency key
#      is "always nonnull"; make the column NOT NULL (F-05 records the consuming command's key for lineage).
#   3. schema lens — the (reservation, generation, renewed_at) unique index is strictly redundant with
#      (reservation, generation); drop the dead index-maintenance weight.
class HardenEntitlementReservationSubsystem < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL
      ALTER TABLE entitlement_counter_windows
        ADD CONSTRAINT entitlement_counter_windows_within_hard
        CHECK (reserved_units + committed_units <= hard_limit);
      ALTER TABLE entitlement_decisions ALTER COLUMN idempotency_key_digest SET NOT NULL;
      DROP INDEX entitlement_lease_heartbeats_generation_time_unique;
    SQL
  end

  def down
    execute <<~SQL
      CREATE UNIQUE INDEX entitlement_lease_heartbeats_generation_time_unique
        ON entitlement_lease_heartbeats (entitlement_reservation_id, heartbeat_generation, renewed_at);
      ALTER TABLE entitlement_decisions ALTER COLUMN idempotency_key_digest DROP NOT NULL;
      ALTER TABLE entitlement_counter_windows DROP CONSTRAINT entitlement_counter_windows_within_hard;
    SQL
  end
end
