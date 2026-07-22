# frozen_string_literal: true

require "rails_helper"

# The durable timer authority: identity, creation replay, the database-enforced
# state machine and immutable identity, and the runtime's privilege posture
# (BACKGROUND_PROCESSING.md § Durable Scheduling :88-121; schemas/
# POSTGRESQL_SCHEMA.md `scheduled_actions` :222 with G-MUT :115 / LINEAGE :121 /
# WORK-CLAIM :122).
#
# Nothing here is invitation-specific. The subsystem sees an opaque
# `(target_type, target_id)` and a catalogued `action_kind`; the Invitation
# appears only as the value of a target id.
RSpec.describe Platform::ScheduledActions::Store, type: :model do
  self.use_transactional_tests = false

  after { ReceiptMinter.truncate_all }

  let(:org) { TenantSeeder.create_organization }
  let(:target) { SecureRandom.uuid_v7 }
  let(:due) { Time.utc(2026, 7, 25, 10, 0, 0) }
  let(:owner) { SecureRandom.uuid_v7 }

  def create(**overrides)
    ScheduledActionHarness.create(organization_id: org, target_id: target, due_at: due, **overrides)
  end

  describe "creation under the proved Organization context" do
    it "creates one pending action carrying the canonical identity preimage and digest" do
      result = create
      row = ScheduledActionHarness.row(result[:id])

      expect(result[:replayed]).to be(false)
      expect(row["status"]).to eq("pending")
      expect(row["action_kind"]).to eq("invitation_expire")
      expect(row["target_type"]).to eq("invitation")
      expect(row["target_id"]).to eq(target)
      expect(row["claim_generation"].to_i).to eq(0)
      expect(row["claim_owner"]).to be_nil
      expect(row["executing_service_identity_id"]).to eq(Platform::ServiceIdentity.scheduled_action_executor)

      expected = Platform::ScheduledActions::Identity.preimage(
        action_kind: "invitation_expire", action_schema_version: "1.0", organization_id: org,
        project_id: nil, target_type: "invitation", target_id: target,
        product_generation: 0, schedule_generation: 1, due_at: due
      )
      expect(row["identity_preimage"].delete_prefix("\\x")).to eq(expected.unpack1("H*"))
      expect(row["identity_sha256"].delete_prefix("\\x"))
        .to eq(Digest::SHA256.hexdigest(expected))
    end

    it "returns the existing row for an exact creation replay and writes no second action" do
      first = create
      second = create

      expect(second[:id]).to eq(first[:id])
      expect(second[:replayed]).to be(true)
      expect(ScheduledActionHarness.count).to eq(1)
    end

    it "creates a distinct action for a different schedule generation of the same target" do
      first = create
      second = create(schedule_generation: 2)

      expect(second[:id]).not_to eq(first[:id])
      expect(ScheduledActionHarness.count).to eq(2)
    end

    it "leaves no action when the scheduling transaction rolls back" do
      expect do
        ScheduledActionHarness.in_context(org) do |store, correlation_id|
          store.create(id: SecureRandom.uuid_v7, action_kind: "invitation_expire", action_schema_version: "1.0",
                       organization_id: org, target_type: "invitation", target_id: target, due_at: due,
                       now: Time.utc(2026, 7, 18), correlation_id:, causation_id: correlation_id,
                       executing_service_identity_id: Platform::ServiceIdentity.scheduled_action_executor)
          raise ActiveRecord::Rollback.new("scheduling command failed after creating the action")
        end
      end.not_to change { ScheduledActionHarness.count }.from(0)
    end
  end

  describe "row level security and runtime privileges" do
    it "hides another Organization's action from the runtime" do
      other_org = TenantSeeder.create_organization
      create
      digest = Platform::ScheduledActions::Identity.digest(
        Platform::ScheduledActions::Identity.preimage(
          action_kind: "invitation_expire", action_schema_version: "1.0", organization_id: org,
          project_id: nil, target_type: "invitation", target_id: target,
          product_generation: 0, schedule_generation: 1, due_at: due
        )
      )

      own = ScheduledActionHarness.in_context(org) { |store, _| store.find_by_identity(action_kind: "invitation_expire", identity_sha256: digest) }
      other = ScheduledActionHarness.in_context(other_org) { |store, _| store.find_by_identity(action_kind: "invitation_expire", identity_sha256: digest) }

      expect(own).not_to be_nil
      expect(other).to be_nil
      expect(ScheduledActionHarness.count).to eq(1)
    end

    it "refuses a runtime INSERT for another Organization (policy WITH CHECK)" do
      other_org = TenantSeeder.create_organization
      expect do
        ScheduledActionHarness.in_context(org) do |store, correlation_id|
          store.create(id: SecureRandom.uuid_v7, action_kind: "invitation_expire", action_schema_version: "1.0",
                       organization_id: other_org, target_type: "invitation", target_id: target, due_at: due,
                       now: Time.utc(2026, 7, 18), correlation_id:, causation_id: correlation_id,
                       executing_service_identity_id: Platform::ServiceIdentity.scheduled_action_executor)
        end
      end.to raise_error(PG::Error, /row-level security/i)
    end

    it "grants the runtime no direct UPDATE or DELETE on the timer table" do
      privileges = DbInspector.one(<<~SQL)
        SELECT has_table_privilege('f1_web','public.scheduled_actions','SELECT') AS sel,
               has_table_privilege('f1_web','public.scheduled_actions','INSERT') AS ins,
               has_table_privilege('f1_web','public.scheduled_actions','UPDATE') AS upd,
               has_table_privilege('f1_web','public.scheduled_actions','DELETE') AS del
      SQL
      expect(privileges.values_at("sel", "ins", "upd", "del")).to eq(%w[t t f f])
    end

    it "keeps every restricted transport function SECURITY DEFINER with a fixed search_path and no PUBLIC execute" do
      functions = DbInspector.all(<<~SQL)
        SELECT p.proname, p.prosecdef, array_to_string(p.proconfig, ';') AS config,
               has_function_privilege('public', p.oid, 'EXECUTE') AS public_exec,
               has_function_privilege('f1_web', p.oid, 'EXECUTE') AS runtime_exec
        FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
        WHERE n.nspname = 'public' AND p.proname LIKE '%scheduled_action%'
          AND p.prorettype <> 'trigger'::regtype::oid
        ORDER BY p.proname
      SQL
      expect(functions.map { |f| f["proname"] }).to contain_exactly(
        "f1_cancel_scheduled_action", "f1_claim_due_scheduled_actions", "f1_dispatch_scheduled_action",
        "f1_release_expired_scheduled_action_leases", "f1_release_scheduled_action_claim",
        "f1_settle_scheduled_action"
      )
      functions.each do |f|
        expect(f["prosecdef"]).to eq("t"), "#{f['proname']} is not SECURITY DEFINER"
        expect(f["config"]).to eq("search_path=pg_catalog, public"), "#{f['proname']} search_path"
        expect(f["public_exec"]).to eq("f"), "#{f['proname']} is PUBLIC executable"
        expect(f["runtime_exec"]).to eq("t"), "#{f['proname']} is not runtime executable"
      end
    end
  end

  describe "the state machine, enforced at the database boundary" do
    def claim
      ScheduledActionHarness.transport_store do |store|
        store.claim_due(owner:, limit: 10, now: due).first
      end
    end

    it "runs pending -> claimed -> dispatched -> completed and clears the claim at each terminal" do
      id = create[:id]
      action = claim
      expect(ScheduledActionHarness.row(id).values_at("status", "claim_phase")).to eq(%w[claimed scheduler])
      expect(action.claim_generation).to eq(1)

      worker = SecureRandom.uuid_v7
      dispatched = ScheduledActionHarness.transport_store do |store|
        store.dispatch(action_id: id, expected_owner: owner, expected_generation: 1,
                       worker_owner: worker, now: due)
      end
      expect(dispatched).not_to be_nil
      expect(ScheduledActionHarness.row(id).values_at("status", "claim_phase")).to eq(%w[dispatched worker])

      settled = ScheduledActionHarness.transport_store do |store|
        store.settle(action_id: id, owner: worker, generation: 1, status: "completed", now: due)
      end
      row = ScheduledActionHarness.row(id)
      expect(settled).to be(true)
      expect(row["status"]).to eq("completed")
      expect(row["completed_at"]).not_to be_nil
      expect(row.values_at("claim_owner", "claimed_at", "lease_expires_at", "claim_phase")).to all(be_nil)
    end

    it "rejects reopening a terminal action even from a superuser connection" do
      id = create[:id]
      action = claim
      worker = SecureRandom.uuid_v7
      ScheduledActionHarness.transport_store do |store|
        store.dispatch(action_id: id, expected_owner: owner, expected_generation: action.claim_generation,
                       worker_owner: worker, now: due)
        store.settle(action_id: id, owner: worker, generation: action.claim_generation,
                     status: "completed", now: due)
      end

      expect do
        ScheduledActionHarness.owner_exec(
          "UPDATE scheduled_actions SET status = 'pending' WHERE id = $1::uuid", [id]
        )
      end.to raise_error(PG::Error, /illegal_transition/)
      expect do
        ScheduledActionHarness.owner_exec(
          "UPDATE scheduled_actions SET completed_at = NULL WHERE id = $1::uuid", [id]
        )
      end.to raise_error(PG::Error, /terminal_timestamp_rewritten/)
      expect(ScheduledActionHarness.row(id)["status"]).to eq("completed")
    end

    it "rejects a change to any immutable identity column" do
      id = create[:id]
      {
        "due_at = $2::timestamptz" => (due + 60).iso8601(6),
        "target_id = $2::uuid" => SecureRandom.uuid_v7,
        "action_kind = $2" => "session_expire",
        "identity_sha256 = decode($2,'hex')" => Digest::SHA256.hexdigest("other"),
        "organization_id = $2::uuid" => SecureRandom.uuid_v7
      }.each do |assignment, value|
        expect do
          ScheduledActionHarness.owner_exec(
            "UPDATE scheduled_actions SET #{assignment} WHERE id = $1::uuid", [id, value]
          )
        end.to raise_error(PG::Error, /immutable_field_changed/), assignment
      end
    end

    it "rejects a regressed claim generation" do
      id = create[:id]
      claim
      expect do
        ScheduledActionHarness.owner_exec(
          "UPDATE scheduled_actions SET claim_generation = 0 WHERE id = $1::uuid", [id]
        )
      end.to raise_error(PG::Error, /claim_generation_regressed/)
    end

    it "rejects an action_kind outside the ratified catalogue" do
      expect { create(action_kind: "invitation_expire_v2") }
        .to raise_error(PG::Error, /action_kind_check|violates check constraint/i)
    end

    it "rejects a reason that is not a bounded classification token" do
      id = create[:id]
      expect do
        ScheduledActionHarness.owner_exec(
          "UPDATE scheduled_actions SET reason = $2 WHERE id = $1::uuid",
          [id, "PG::UndefinedTable: ERROR: relation does not exist\n/app/foo.rb:12:in 'call'"]
        )
      end.to raise_error(PG::Error, /violates check constraint/i)
    end
  end
end
