# frozen_string_literal: true

require "rails_helper"

# S-07-005 host-gate database invariants (schemas/POSTGRESQL_SCHEMA.md :296;
# WORKFLOW_SPECIFICATIONS.md :442/:448). The properties that must hold in the database itself:
# forced tenant RLS, the least-privilege runtime matrix, the one-gate-per-host unique, the robots
# state machine and its WRITE-ONCE terminal decision, and the shape CHECKs.
RSpec.describe "Crawl host-gate invariants", type: :model do
  self.use_transactional_tests = false
  after { ReceiptMinter.truncate_all }

  let(:org) { TenantSeeder.create_organization(display_name: "Acme Org") }
  def conn = DbInspector.connection

  def draft_project(organization_id: org)
    id = SecureRandom.uuid_v7
    conn.exec_params(<<~SQL, [id, organization_id])
      INSERT INTO projects
        (id, state_version, lock_version, created_at, updated_at, correlation_id, organization_id,
         display_name, locale, time_zone, objective, state, source_set_version)
      VALUES ($1,0,0,now(),now(),gen_random_uuid(),$2,'P','en-AU','UTC','discoverability_assessment','draft',0)
    SQL
    id
  end

  def insert_crawl(pid, organization_id: org)
    id = SecureRandom.uuid_v7
    conn.exec_params(<<~SQL, [id, organization_id, pid])
      INSERT INTO crawls
        (id, state_version, created_at, updated_at, correlation_id, organization_id, project_id, kind,
         requested_entitlement_policy_id, requested_entitlement_policy_version, trigger_kind, queued_at, state)
      VALUES ($1,0,now(),now(),gen_random_uuid(),$2::uuid,$3::uuid,'root',
              gen_random_uuid(),'entitlement-interim-v1','manual',now(),'queued')
    SQL
    id
  end

  def insert_gate(ctx, host: "h#{SecureRandom.hex(3)}.example", state: "pending", terminal_at: nil,
                  reason: nil, rules: nil)
    id = SecureRandom.uuid_v7
    params = [id, ctx[:org], ctx[:project], ctx[:crawl], host,
              { value: Digest::SHA256.digest(host), format: 1 }, state, terminal_at, reason, rules]
    conn.exec_params(<<~SQL, params)
      INSERT INTO crawl_host_gates
        (id, state_version, created_at, updated_at, correlation_id, organization_id, project_id,
         crawl_id, canonical_host, canonical_host_sha256, robots_state, robots_terminal_at,
         robots_terminal_reason, robots_rules)
      VALUES ($1,0,now(),now(),gen_random_uuid(),$2::uuid,$3::uuid,
              $4::uuid,$5,$6,$7,$8::timestamptz,$9,$10::jsonb)
    SQL
    id
  end

  def context
    pid = draft_project
    { org:, project: pid, crawl: insert_crawl(pid) }
  end

  # Every UPDATE must advance the version by exactly one — it is the CAS defence for the claim.
  def update_gate(id, set)
    conn.exec_params("UPDATE crawl_host_gates SET state_version = state_version + 1, #{set} WHERE id = $1::uuid", [id])
  end

  describe "tenancy and least privilege" do
    it "forces row level security with the tenant-context policy" do
      rel = DbInspector.one("SELECT relrowsecurity AS e, relforcerowsecurity AS f FROM pg_class WHERE relname = $1",
                            ["crawl_host_gates"])
      expect(rel["e"]).to eq("t")
      expect(rel["f"]).to eq("t")
      policy = DbInspector.one("SELECT qual, with_check FROM pg_policies WHERE tablename = $1 AND policyname = $2",
                               %w[crawl_host_gates crawl_host_gates_context])
      expect(policy["qual"]).to include("f1_current_context_org")
      expect(policy["with_check"]).to include("f1_current_context_org")
    end

    it "grants the runtime role exactly SELECT/INSERT/UPDATE (never DELETE)" do
      privs = DbInspector.all(<<~SQL, ["crawl_host_gates"]).map { |r| r["privilege_type"] }.sort
        SELECT privilege_type FROM information_schema.role_table_grants
        WHERE table_name = $1 AND grantee = 'f1_runtime'
      SQL
      expect(privs).to eq(%w[INSERT SELECT UPDATE])
    end

    it "rejects a gate naming a Crawl from another Project of the same Organization" do
      c = context
      other = context
      expect { insert_gate(c.merge(crawl: other[:crawl])) }
        .to raise_error(PG::ForeignKeyViolation, /crawl_host_gates_crawl_fk/)
    end
  end

  describe "host identity" do
    it "permits at most one gate per (crawl, canonical host digest)" do
      c = context
      insert_gate(c, host: "same.example")
      expect { insert_gate(c, host: "same.example") }
        .to raise_error(PG::UniqueViolation, /crawl_host_gates_host_unique/)
    end

    it "allows the same host under a different Crawl" do
      c = context
      insert_gate(c, host: "same.example")
      expect { insert_gate(context, host: "same.example") }.not_to raise_error
    end
  end

  describe "the robots state machine" do
    it "permits exactly pending -> in_progress -> terminal, and in_progress -> pending for a retry" do
      c = context
      a = insert_gate(c)
      expect { update_gate(a, "robots_state='in_progress'") }.not_to raise_error
      expect { update_gate(a, "robots_state='pending'") }.not_to raise_error
      expect { update_gate(a, "robots_state='in_progress'") }.not_to raise_error
      expect { update_gate(a, "robots_state='no_restrictions', robots_terminal_at=now()") }.not_to raise_error
    end

    it "refuses a jump straight from pending to a terminal state" do
      c = context
      %w[rules_applied no_restrictions unavailable].each do |target|
        a = insert_gate(c, host: "j#{target}.example")
        expect { update_gate(a, "robots_state='#{target}', robots_terminal_at=now(), robots_terminal_reason='x'") }
          .to raise_error(PG::RaiseException, /crawl_host_gate_robots_transition_unavailable pending -> #{target}/)
      end
    end

    it "makes the TERMINAL robots decision write-once" do
      c = context
      a = insert_gate(c, state: "in_progress")
      update_gate(a, "robots_state='unavailable', robots_terminal_at=now(), robots_terminal_reason='robots_unavailable_fail_closed'")
      {
        "robots_state" => "'no_restrictions'", "robots_terminal_reason" => "'other'",
        "robots_rules" => "'{}'::jsonb", "robots_agent_group" => "'*'",
        "robots_crawl_delay_ms" => "10", "robots_http_status" => "200",
        "robots_source_sha256" => "sha256('x')",
        "robots_sitemap_candidates" => %q{'["https://h.example/s.xml"]'::jsonb}
      }.each do |column, value|
        expect { update_gate(a, "#{column} = #{value}") }
          .to raise_error(PG::RaiseException, /crawl_host_gate_robots_decision_frozen/), "#{column} was rewritable"
      end
    end

    it "still permits the rate/concurrency columns to move after robots is terminal" do
      c = context
      a = insert_gate(c, state: "in_progress")
      update_gate(a, "robots_state='no_restrictions', robots_terminal_at=now()")
      expect { update_gate(a, "active_connection_count = 2, next_allowed_start_at = now()") }.not_to raise_error
    end

    it "requires exactly the terminal states to carry a terminal instant" do
      c = context
      expect { insert_gate(c, state: "pending", terminal_at: Time.now.utc) }
        .to raise_error(PG::CheckViolation, /crawl_host_gates_robots_terminal_shape/)
      expect { insert_gate(c, state: "no_restrictions", terminal_at: nil) }
        .to raise_error(PG::CheckViolation, /crawl_host_gates_robots_terminal_shape/)
    end

    it "requires a fail-closed outcome to name its reason" do
      c = context
      expect { insert_gate(c, state: "unavailable", terminal_at: Time.now.utc, reason: nil) }
        .to raise_error(PG::CheckViolation, /crawl_host_gates_robots_unavailable_reason/)
    end

    it "permits rules only on the rules_applied state" do
      c = context
      expect { insert_gate(c, state: "no_restrictions", terminal_at: Time.now.utc, rules: "{}") }
        .to raise_error(PG::CheckViolation, /crawl_host_gates_robots_rules_shape/)
    end

    it "refuses an unknown robots state" do
      expect { insert_gate(context, state: "guessed") }.to raise_error(PG::CheckViolation, /robots_state/)
    end
  end

  describe "identity, versioning and deletion" do
    it "freezes identity for life and refuses DELETE" do
      c = context
      a = insert_gate(c, host: "frozen.example")
      { "canonical_host" => "'other.example'", "crawl_id" => "gen_random_uuid()",
        "canonical_host_sha256" => "sha256('other')", "correlation_id" => "gen_random_uuid()" }.each do |column, value|
        expect { update_gate(a, "#{column} = #{value}") }
          .to raise_error(PG::RaiseException, /crawl_host_gate_facts_immutable/), "#{column} was mutable"
      end
      expect { conn.exec_params("DELETE FROM crawl_host_gates WHERE id = $1::uuid", [a]) }
        .to raise_error(PG::RaiseException, /crawl_host_gate_immutable/)
    end

    it "requires every mutation to advance state_version by exactly one" do
      c = context
      a = insert_gate(c)
      expect { conn.exec_params("UPDATE crawl_host_gates SET active_connection_count = 1 WHERE id = $1::uuid", [a]) }
        .to raise_error(PG::RaiseException, /crawl_host_gate_version_invalid/)
      expect { conn.exec_params("UPDATE crawl_host_gates SET state_version = 99 WHERE id = $1::uuid", [a]) }
        .to raise_error(PG::RaiseException, /crawl_host_gate_version_invalid/)
    end

    it "refuses a negative connection count or crawl delay" do
      c = context
      a = insert_gate(c)
      expect { update_gate(a, "active_connection_count = -1") }.to raise_error(PG::CheckViolation, /active_connection_count/)
      expect { update_gate(a, "robots_crawl_delay_ms = -1") }.to raise_error(PG::CheckViolation, /robots_crawl_delay_ms/)
    end
  end
end
