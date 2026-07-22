# frozen_string_literal: true

require "rails_helper"

# The S-02 genesis invariants, asserted at the strongest layer that can hold
# them: a database constraint, trigger or forced RLS wherever the database can
# refuse it, against the raw owner connection rather than the application (user
# Scope K). An invariant proved only by "the command declines to try" is a
# convention; these are refusals the database makes.
RSpec.describe "WF-001 bootstrap invariants", type: :acceptance,
               acceptance_ids: ["AC-CAP-002", "AC-PRULE-002"],
               test_types: %w[TYP-SEC TYP-DATA] do
  self.use_transactional_tests = false

  after { ReceiptMinter.truncate_all }

  def owner = DbInspector.connection
  def t = Time.utc(2026, 7, 20, 10, 0, 0).iso8601(6)

  # An Organization plus its BillingEntity, arranged directly through the owner
  # connection (RLS-forced, so a proved context is entered first).
  let(:org) { TenantSeeder.create_organization }

  def in_org(&) = ScheduledActionHarness.in_context(org) { |_s, _c| yield }

  def billing_entity(state: "active", plan: true)
    id = SecureRandom.uuid_v7
    plan_id = plan ? SecureRandom.uuid_v7 : nil
    owner.exec_params(<<~SQL, [id, org, state, plan_id])
      INSERT INTO billing_entities
        (id, state_version, lock_version, created_at, updated_at, correlation_id, organization_id,
         internal_contract_reference, state, active_plan_assignment_id, effective_at, activated_at)
      VALUES ($1,0,0,now(),now(),gen_random_uuid(),$2::uuid,'ref',$3,$4::uuid,now(),
              CASE WHEN $3 = 'active' THEN now() END)
    SQL
    id
  end

  def plan_assignment(billing_id, state: "active", organization: org)
    id = SecureRandom.uuid_v7
    owner.exec_params(<<~SQL, [id, organization, billing_id, state, t])
      INSERT INTO plan_assignments
        (id, state_version, lock_version, created_at, updated_at, correlation_id, organization_id,
         billing_entity_id, plan_version, approval_version, policy_version, content_sha256, effective_at, state)
      VALUES ($1,0,0,now(),now(),gen_random_uuid(),$2::uuid,$3::uuid,'interim-baseline-plan-v1',
              'plan-approval-interim-baseline-v1','entitlement-interim-v1',decode(repeat('00',32),'hex'),$5::timestamptz,$4)
    SQL
    id
  end

  describe "BillingEntity" do
    it "belongs to exactly one Organization and cannot be moved" do
      id = billing_entity
      expect { owner.exec_params("UPDATE billing_entities SET organization_id = gen_random_uuid() WHERE id = $1::uuid", [id]) }
        .to raise_error(PG::RaiseException, /billing_entity_genesis_immutable/)
    end

    it "enforces one nonclosed BillingEntity per Organization" do
      billing_entity
      expect { billing_entity }.to raise_error(PG::UniqueViolation, /one_nonclosed_billing_entity_per_org/)
    end

    it "refuses the reserved past_due and suspended states, keeping them unreachable" do
      %w[past_due suspended].each do |reserved|
        expect { billing_entity(state: reserved, plan: false) }
          .to raise_error(PG::RaiseException, /billing_entity_reserved_state_unreachable/)
      end
    end

    it "refuses an illegal BillingEntity transition" do
      id = billing_entity
      expect { owner.exec_params("UPDATE billing_entities SET state = 'pending' WHERE id = $1::uuid", [id]) }
        .to raise_error(PG::RaiseException, /billing_entity_illegal_transition/)
    end
  end

  describe "Plan Assignment" do
    it "enforces one active Plan Assignment per Organization" do
      billing = billing_entity
      plan_assignment(billing)
      expect { plan_assignment(billing) }.to raise_error(PG::UniqueViolation, /one_active_plan_assignment_per_org/)
    end

    it "refuses a cross-Organization BillingEntity link" do
      billing = billing_entity
      other = TenantSeeder.create_organization
      expect { plan_assignment(billing, organization: other) }
        .to raise_error(PG::ForeignKeyViolation, /plan_assignment_billing_same_org/)
    end
  end

  describe "first-administrator" do
    it "enforces one bootstrap administrator per Organization" do
      account = TenantSeeder.create_account(organization_id: org, issuer_key: "https://id.example/oidc",
                                            subject: "a-#{SecureRandom.hex(4)}")
      other = TenantSeeder.create_account(organization_id: org, issuer_key: "https://id.example/oidc",
                                          subject: "b-#{SecureRandom.hex(4)}")
      TenantSeeder.create_role_assignment(organization_id: org, account_id: account,
                                          canonical_role: "OrganizationAdmin", bootstrap_admin_exception: true)
      expect do
        TenantSeeder.create_role_assignment(organization_id: org, account_id: other,
                                            canonical_role: "OrganizationAdmin", bootstrap_admin_exception: true)
      end.to raise_error(PG::UniqueViolation, /one_bootstrap_admin_per_organization/)
    end
  end

  describe "isolation" do
    it "keeps RLS forced on every genesis root" do
      forced = DbInspector.all(<<~SQL)
        SELECT relname, relrowsecurity, relforcerowsecurity FROM pg_class
        WHERE relname IN ('billing_entities','plan_assignments','entitlement_policies','projects')
        ORDER BY relname
      SQL
      expect(forced.size).to eq(4)
      forced.each do |row|
        expect(row["relrowsecurity"]).to eq("t")
        expect(row["relforcerowsecurity"]).to eq("t")
      end
    end

    it "keeps the genesis roots away from the platform worker" do
      %w[billing_entities plan_assignments entitlement_policies projects].each do |table|
        expect do
          ScheduledActionHarness.as_role("f1_platform_worker") { |pg| pg.exec("SELECT count(*) FROM #{table}") }
        end.to raise_error(PG::InsufficientPrivilege, /permission denied/i)
      end
    end

    it "gives f1_web no DELETE on any genesis root" do
      %w[organizations billing_entities plan_assignments entitlement_policies access_policies projects].each do |table|
        expect(DbInspector.one("SELECT has_table_privilege('f1_web','#{table}','DELETE') AS d")["d"]).to eq("f")
      end
    end
  end
end
