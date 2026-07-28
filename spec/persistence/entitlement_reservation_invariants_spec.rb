# frozen_string_literal: true

require "rails_helper"

# F-05 entitlement reservation subsystem database invariants (schemas/POSTGRESQL_SCHEMA.md :418-424;
# WORKFLOW_SPECIFICATIONS.md :513-554; DECISIONS ADR-069). Forced tenant RLS on all five tables, the
# least-privilege runtime matrix (immutable decisions/heartbeats never UPDATE; no DELETE anywhere), the
# reservation state machine the guard enforces, and the immutability/uniqueness backstops. Exercised via
# the BYPASSRLS superuser connection (the runtime role and even the schema owner are subject to FORCE RLS).
RSpec.describe "Entitlement reservation invariants", type: :model do
  self.use_transactional_tests = false
  after { ReceiptMinter.truncate_all }

  let(:org) { TenantSeeder.create_organization(display_name: "Acme Org") }
  def conn = DbInspector.connection

  def window(organization_id: org, soft: 3, hard: 4, group: "crawl.start")
    id = SecureRandom.uuid_v7
    conn.exec_params(<<~SQL, [id, organization_id, group, soft, hard])
      INSERT INTO entitlement_counter_windows
        (id, state_version, created_at, updated_at, correlation_id, organization_id, counter_group,
         window_start, window_end, soft_limit, hard_limit, reserved_units, committed_units, low_cost_units,
         policy_version, reconciliation_state)
      VALUES ($1::uuid,0,now(),now(),gen_random_uuid(),$2::uuid,$3,
              '2026-07-27T00:00:00Z','2026-07-28T00:00:00Z',$4,$5,0,0,0,'entitlement-interim-v1','authoritative')
    SQL
    id
  end

  def decision(window_id, organization_id: org, dec: "allow", account: SecureRandom.uuid_v7, service: nil)
    id = SecureRandom.uuid_v7
    conn.exec_params(<<~SQL, [id, organization_id, account, service, window_id, dec])
      INSERT INTO entitlement_decisions
        (id, created_at, decided_at, correlation_id, organization_id, account_id, service_identity_id,
         operation, usage_unit, requested_units, counter_window_id, window_start, window_end, policy_version,
         plan_version, soft_limit, hard_limit, committed_before, committed_after, active_reserved_before,
         active_reserved_after, reservation_id, decision, reason_code, recovery_action)
      VALUES ($1::uuid,now(),now(),gen_random_uuid(),$2::uuid,$3::uuid,$4::uuid,'crawl.start','crawl_run',1,
              $5::uuid,'2026-07-27T00:00:00Z','2026-07-28T00:00:00Z','entitlement-interim-v1','interim-baseline-plan-v1',
              3,4,0,0,0,1,NULL,$6,'within_limit','none')
    SQL
    id
  end

  def reservation(window_id, decision_id, organization_id: org, state: "reserved")
    id = SecureRandom.uuid_v7
    terminal = %w[committed released expired].include?(state) ? "now()" : "NULL"
    started = state == "reserved" ? "NULL" : "now()"
    conn.exec_params(<<~SQL, [id, organization_id, decision_id, window_id, state])
      INSERT INTO entitlement_reservations
        (id, state_version, created_at, updated_at, correlation_id, organization_id, decision_id,
         counter_window_id, units, lease_generation, lease_due, last_heartbeat_at, started_at, state,
         terminal_at, terminal_reason)
      VALUES ($1::uuid,0,now(),now(),gen_random_uuid(),$2::uuid,$3::uuid,$4::uuid,1,0,now()+interval '15 min',
              NULL,#{started},$5,#{terminal},NULL)
    SQL
    id
  end

  describe "tenancy and least privilege" do
    grants = { "entitlement_counter_windows" => %w[INSERT SELECT UPDATE], "entitlement_decisions" => %w[INSERT SELECT],
               "entitlement_reservations" => %w[INSERT SELECT UPDATE], "entitlement_lease_heartbeats" => %w[INSERT SELECT],
               "entitlement_commit_intents" => %w[INSERT SELECT UPDATE] }
    grants.each do |table, privs|
      it "forces RLS on #{table} with the tenant-context policy" do
        rel = DbInspector.one("SELECT relrowsecurity AS e, relforcerowsecurity AS f FROM pg_class WHERE relname = $1", [table])
        expect([rel["e"], rel["f"]]).to eq(%w[t t])
        pol = DbInspector.one("SELECT qual FROM pg_policies WHERE tablename = $1 AND policyname = $2", [table, "#{table}_context"])
        expect(pol["qual"]).to include("f1_current_context_org")
      end

      it "grants the runtime role exactly #{privs.join('/')} on #{table} (never DELETE)" do
        actual = DbInspector.all(<<~SQL, [table]).map { |r| r["privilege_type"] }.sort
          SELECT privilege_type FROM information_schema.role_table_grants WHERE table_name = $1 AND grantee = 'f1_runtime'
        SQL
        expect(actual).to eq(privs)
        expect(actual).not_to include("DELETE")
      end
    end
  end

  describe "immutable records (T-IMM)" do
    it "refuses UPDATE and DELETE on entitlement_decisions" do
      d = decision(window)
      expect { conn.exec_params("UPDATE entitlement_decisions SET reason_code='soft_limit_reached' WHERE id=$1::uuid", [d]) }
        .to raise_error(PG::RaiseException, /entitlement_decision_immutable/)
      expect { conn.exec_params("DELETE FROM entitlement_decisions WHERE id=$1::uuid", [d]) }
        .to raise_error(PG::RaiseException, /entitlement_decision_immutable/)
    end

    it "enforces the actor/service XOR on a Decision" do
      w = window
      expect { decision(w, account: SecureRandom.uuid_v7, service: SecureRandom.uuid_v7) }
        .to raise_error(PG::CheckViolation, /entitlement_decisions_subject_xor/)
      expect { decision(w, account: nil, service: nil) }
        .to raise_error(PG::CheckViolation, /entitlement_decisions_subject_xor/)
    end
  end

  describe "the reservation state machine (guard-enforced)" do
    it "permits the legal edges and refuses illegal ones; refuses DELETE and identity edits" do
      w = window
      r = reservation(w, decision(w))
      expect { conn.exec_params("DELETE FROM entitlement_reservations WHERE id=$1::uuid", [r]) }
        .to raise_error(PG::RaiseException, /entitlement_reservation_immutable/)
      expect { conn.exec_params("UPDATE entitlement_reservations SET units=9 WHERE id=$1::uuid", [r]) }
        .to raise_error(PG::RaiseException, /entitlement_reservation_facts_immutable/)
      # illegal: reserved -> committed
      expect { conn.exec_params("UPDATE entitlement_reservations SET state='committed', terminal_at=now() WHERE id=$1::uuid", [r]) }
        .to raise_error(PG::RaiseException, /entitlement_reservation_transition_unavailable/)
      # legal: reserved -> executing
      expect { conn.exec_params("UPDATE entitlement_reservations SET state='executing', started_at=now() WHERE id=$1::uuid", [r]) }
        .not_to raise_error
      # illegal from a terminal state: executing -> expired
      expect { conn.exec_params("UPDATE entitlement_reservations SET state='expired', terminal_at=now() WHERE id=$1::uuid", [r]) }
        .to raise_error(PG::RaiseException, /entitlement_reservation_transition_unavailable/)
      # legal: executing -> committed
      expect { conn.exec_params("UPDATE entitlement_reservations SET state='committed', terminal_at=now() WHERE id=$1::uuid", [r]) }
        .not_to raise_error
    end

    it "permits at most one reservation per Decision" do
      w = window
      d = decision(w)
      reservation(w, d)
      expect { reservation(w, d) }.to raise_error(PG::UniqueViolation, /entitlement_reservations_decision_unique/)
    end
  end

  describe "counter windows and commit intents" do
    it "freezes a window's identity + limits but permits the counter columns to move" do
      w = window
      expect { conn.exec_params("UPDATE entitlement_counter_windows SET hard_limit=99 WHERE id=$1::uuid", [w]) }
        .to raise_error(PG::RaiseException, /entitlement_counter_window_facts_immutable/)
      expect { conn.exec_params("UPDATE entitlement_counter_windows SET reserved_units=2, committed_units=1 WHERE id=$1::uuid", [w]) }
        .not_to raise_error
      expect { conn.exec_params("DELETE FROM entitlement_counter_windows WHERE id=$1::uuid", [w]) }
        .to raise_error(PG::RaiseException, /entitlement_counter_window_immutable/)
    end

    it "enforces the one-active-window-per-(org,group,day) unique" do
      window
      expect { window }.to raise_error(PG::UniqueViolation, /entitlement_counter_windows_slot_unique/)
    end

    it "permits pending -> committed on a commit intent but refuses a reopen" do
      w = window
      r = reservation(w, decision(w))
      cid = SecureRandom.uuid_v7
      conn.exec_params(<<~SQL, [cid, org, r])
        INSERT INTO entitlement_commit_intents
          (id, state_version, created_at, updated_at, correlation_id, organization_id, reservation_id,
           durable_output_type, durable_output_id, state)
        VALUES ($1::uuid,0,now(),now(),gen_random_uuid(),$2::uuid,$3::uuid,'crawl',gen_random_uuid(),'pending')
      SQL
      expect { conn.exec_params("UPDATE entitlement_commit_intents SET state='committed', terminal_at=now() WHERE id=$1::uuid", [cid]) }
        .not_to raise_error
      expect { conn.exec_params("UPDATE entitlement_commit_intents SET state='pending', terminal_at=NULL WHERE id=$1::uuid", [cid]) }
        .to raise_error(PG::RaiseException, /entitlement_commit_intent_transition_unavailable/)
    end
  end
end
