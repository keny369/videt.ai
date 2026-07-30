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
  # PostgreSQL transaction time is the due-time authority, so due-ness is
  # arranged by writing `due_at`, never by supplying an instant to the transport.
  let(:due) { ScheduledActionHarness.past }
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

    # The transport is platform-control authority, not request-serving authority
    # (POSTGRESQL_SCHEMA.md :136 f1_web is "registered browser/API tables and
    # functions only"; :166 scheduler leadership is `f1_platform_worker`
    # registered functions; :175 "granted only to `f1_platform_worker`").
    it "confines every restricted transport function to the platform worker, with a fixed search_path" do
      functions = DbInspector.all(<<~SQL)
        SELECT p.proname, p.prosecdef, array_to_string(p.proconfig, ';') AS config,
               has_function_privilege('public', p.oid, 'EXECUTE') AS public_exec,
               has_function_privilege('f1_web', p.oid, 'EXECUTE') AS web_exec,
               has_function_privilege('f1_worker', p.oid, 'EXECUTE') AS worker_exec,
               has_function_privilege('f1_platform_worker', p.oid, 'EXECUTE') AS platform_exec,
               ('timestamptz'::regtype = ANY (p.proargtypes::oid[])) AS takes_time
        FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
        WHERE n.nspname = 'public' AND p.proname LIKE '%scheduled_action%'
          AND p.prorettype <> 'trigger'::regtype::oid
        ORDER BY p.proname
      SQL
      expect(functions.map { |f| f["proname"] }).to contain_exactly(
        "f1_cancel_scheduled_action", "f1_claim_due_scheduled_actions", "f1_dispatch_scheduled_action",
        "f1_fail_scheduled_action_dispatch", "f1_heartbeat_scheduled_action",
        "f1_release_expired_scheduled_action_leases", "f1_release_scheduled_action_claim",
        "f1_settle_scheduled_action"
      )
      functions.each do |f|
        name = f["proname"]
        expect(f["prosecdef"]).to eq("t"), "#{name} is not SECURITY DEFINER"
        expect(f["config"]).to eq("search_path=pg_catalog, public"), "#{name} search_path"
        expect(f["public_exec"]).to eq("f"), "#{name} is PUBLIC executable"
        expect(f["web_exec"]).to eq("f"), "#{name} is executable by the request-serving role"
        expect(f["worker_exec"]).to eq("f"), "#{name} is executable by the tenant job role"
        expect(f["platform_exec"]).to eq("t"), "#{name} is not executable by the platform worker"
        # PostgreSQL transaction time is the sole due-time authority
        # (BACKGROUND_PROCESSING.md :114; verification gate 7 :519).
        expect(f["takes_time"]).to eq("f"), "#{name} accepts a caller-supplied instant"
      end
    end

    it "refuses a request-path attempt to claim scheduled work" do
      id = create[:id]
      expect { ScheduledActionHarness.as_role("f1_web") { |pg| pg.exec_params("SELECT * FROM f1_claim_due_scheduled_actions($1::uuid,10,30)", [owner]) } }
        .to raise_error(PG::InsufficientPrivilege, /permission denied/i)
      expect(ScheduledActionHarness.row(id)["status"]).to eq("pending")
    end

    it "refuses a request-path attempt to settle, release, sweep or cancel scheduled work" do
      id = create[:id]
      attempts = {
        "SELECT f1_settle_scheduled_action($1::uuid,$1::uuid,1,'completed',NULL)" => [id],
        "SELECT f1_release_scheduled_action_claim($1::uuid,$1::uuid,1,NULL)" => [id],
        "SELECT f1_release_expired_scheduled_action_leases(100)" => [],
        "SELECT f1_cancel_scheduled_action($1::uuid,NULL)" => [id]
      }
      attempts.each do |sql, params|
        expect { ScheduledActionHarness.as_role("f1_web") { |pg| pg.exec_params(sql, params) } }
          .to raise_error(PG::InsufficientPrivilege, /permission denied/i), sql
      end
      expect(ScheduledActionHarness.row(id)["status"]).to eq("pending")
    end

    # `p_now` is gone, so there is no argument through which any caller — trusted
    # or not — can move an action's due time forward.
    it "offers no overload through which a caller can supply its own clock" do
      overloads = DbInspector.all(<<~SQL).map { |r| r["args"] }
        SELECT pg_get_function_arguments(p.oid) AS args
        FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
        WHERE n.nspname = 'public' AND p.proname = 'f1_claim_due_scheduled_actions'
      SQL
      expect(overloads).to eq(["p_owner uuid, p_limit integer, p_lease_seconds integer"])
    end
  end

  describe "the state machine, enforced at the database boundary" do
    def claim
      ScheduledActionHarness.transport_store do |store|
        store.claim_due(owner:, limit: 10).first
      end
    end

    it "runs pending -> claimed -> dispatched -> completed and clears the claim at each terminal" do
      id = create[:id]
      action = claim
      expect(ScheduledActionHarness.row(id).values_at("status", "claim_phase")).to eq(%w[claimed scheduler])
      expect(action.claim_generation).to eq(1)

      worker = SecureRandom.uuid_v7
      dispatched = ScheduledActionHarness.transport_store do |store|
        store.dispatch(work_id: action.work_id, expected_generation: 1, worker_owner: worker)
      end
      expect(dispatched).not_to be_nil
      expect(ScheduledActionHarness.row(id).values_at("status", "claim_phase")).to eq(%w[dispatched worker])

      settled = ScheduledActionHarness.transport_store do |store|
        store.settle(action_id: id, owner: worker, generation: 1, status: "completed")
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
        store.dispatch(work_id: action.work_id, expected_generation: action.claim_generation,
                       worker_owner: worker)
        store.settle(action_id: id, owner: worker, generation: action.claim_generation,
                     status: "completed")
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
        "due_at = $2::timestamptz" => (due + 60).getutc.iso8601(6),
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

    # `service_identity_id` is an F1 row identity requiring a named FK/existence
    # check (POSTGRESQL_SCHEMA.md :43), and :202 gives the record a
    # ('active','suspended','revoked') status. A UUID that names no row cannot be
    # scheduled, and an identity that is no longer active stops executing.
    it "refuses an executing service identity that names no persisted row" do
      expect { create(executing_service_identity_id: SecureRandom.uuid_v7) }
        .to raise_error(PG::ForeignKeyViolation, /service_identit/i)
      expect(ScheduledActionHarness.count).to eq(0)
    end

    it "binds the reserved executor to a real, active, revocable Service Identity row" do
      row = DbInspector.one("SELECT * FROM service_identities WHERE id = $1::uuid",
                            [Platform::ServiceIdentity.scheduled_action_executor])
      expect(row["subject"]).to eq(Platform::ServiceIdentity::SCHEDULED_ACTION_EXECUTOR_SUBJECT)
      expect(row["status"]).to eq("active")
      expect(row["activated_at"]).not_to be_nil
    end

    it "stops claiming work for a suspended or revoked executing identity" do
      id = create[:id]
      %w[suspended revoked].each do |status|
        ScheduledActionHarness.owner_exec(<<~SQL, [Platform::ServiceIdentity.scheduled_action_executor, status])
          UPDATE service_identities
          SET status = $2, activated_at = NULL, revoked_at = CASE WHEN $2 = 'revoked' THEN now() END
          WHERE id = $1::uuid
        SQL
        claimed = ScheduledActionHarness.transport_store { |store| store.claim_due(owner:, limit: 10) }
        expect(claimed).to be_empty, "claimed work for a #{status} executor"
        expect(ScheduledActionHarness.row(id)["status"]).to eq("pending")
      end

      ScheduledActionHarness.owner_exec(<<~SQL, [Platform::ServiceIdentity.scheduled_action_executor])
        UPDATE service_identities SET status = 'active', activated_at = now(), revoked_at = NULL WHERE id = $1::uuid
      SQL
      expect(ScheduledActionHarness.transport_store { |store| store.claim_due(owner:, limit: 10) }.map(&:id)).to eq([id])
    end

    it "keeps the Service Identity register unreadable and unwritable by the runtime" do
      privileges = DbInspector.one(<<~SQL)
        SELECT has_table_privilege('f1_web','public.service_identities','SELECT') AS web_sel,
               has_table_privilege('f1_platform_worker','public.service_identities','SELECT') AS platform_sel,
               has_table_privilege('f1_web','public.service_identities','UPDATE') AS web_upd
      SQL
      expect(privileges.values_at("web_sel", "platform_sel", "web_upd")).to eq(%w[f f f])
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
