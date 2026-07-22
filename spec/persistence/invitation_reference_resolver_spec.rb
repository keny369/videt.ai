# frozen_string_literal: true

require "rails_helper"

# The public invitation-reference resolver, whose expiry decision is now
# PostgreSQL's alone.
#
# `f1_resolve_invitation_reference` previously took the effective current instant
# from its caller and was granted to `f1_web`, so a caller supplying a HISTORICAL
# instant could resolve a reference PostgreSQL already considered expired.
# WORKFLOW_SPECIFICATIONS.md:242 fixes the rule — "Active expiry is exactly seven
# days after activation, and at equality expiry wins over acceptance or decline" —
# and schemas/POSTGRESQL_SCHEMA.md:179 requires the resolver to return the binding
# "ONLY for an active, unexpired, byte-consistent locator", with "All misses,
# nonactive/terminal rows, expiry equality, digest mismatch and synchronization
# failure return the same null binding".
#
# Equality is proved exactly rather than approximately: inside one transaction
# `transaction_timestamp()` is constant, so a registry row whose `expires_at` IS
# that instant tests `now >= expires_at` at true equality.
RSpec.describe "invitation reference resolution", type: :model do
  self.use_transactional_tests = false

  after { ReceiptMinter.truncate_all }

  let(:org) { TenantSeeder.create_organization }

  def owner = DbInspector.connection
  def digest_param(bytes) = { value: bytes, format: 1 }

  def resolve(reference_digest, connection: ActiveRecord::Base.connection.raw_connection)
    connection.exec_params("SELECT organization_id, invitation_id FROM f1_resolve_invitation_reference($1)",
                           [digest_param(reference_digest)]).to_a
  end

  describe "signature and grants" do
    it "exposes exactly one overload, taking only the reference digest" do
      overloads = DbInspector.all(<<~SQL)
        SELECT pg_get_function_arguments(p.oid) AS args,
               has_function_privilege('public', p.oid, 'EXECUTE') AS public_exec,
               has_function_privilege('f1_web', p.oid, 'EXECUTE') AS web_exec
        FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
        WHERE n.nspname = 'public' AND p.proname = 'f1_resolve_invitation_reference'
      SQL
      expect(overloads.size).to eq(1)
      expect(overloads.first["args"]).to eq("p_reference_digest bytea")
      expect(overloads.first["public_exec"]).to eq("f")
      expect(overloads.first["web_exec"]).to eq("t")
    end

    it "leaves the runtime no resolver overload that accepts a timestamp" do
      timed = DbInspector.all(<<~SQL)
        SELECT p.proname, pg_get_function_arguments(p.oid) AS args
        FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
        WHERE n.nspname = 'public' AND p.proname LIKE 'f1_resolve_invitation%'
          AND 'timestamptz'::regtype = ANY (p.proargtypes::oid[])
      SQL
      expect(timed).to be_empty
    end

    it "refuses a request-path call that tries to supply its own clock" do
      inv = TenantSeeder.create_invitation(organization_id: org)
      expect do
        ScheduledActionHarness.as_role("f1_web") do |pg|
          pg.exec_params("SELECT * FROM f1_resolve_invitation_reference($1, now())", [digest_param(inv[:reference_digest])])
        end
      end.to raise_error(PG::UndefinedFunction, /does not exist/i)
    end
  end

  describe "resolution under PostgreSQL time" do
    it "resolves an active, unexpired reference" do
      inv = TenantSeeder.create_invitation(organization_id: org)
      expect(resolve(inv[:reference_digest]).first)
        .to eq("organization_id" => org, "invitation_id" => inv[:invitation_id])
    end

    it "does not resolve an expired reference, and no historical instant revives it" do
      inv = TenantSeeder.create_invitation(organization_id: org, activated_at: Time.utc(2026, 6, 1, 10, 0, 0))
      expect(resolve(inv[:reference_digest])).to be_empty

      # The whole point: even a caller that knows the exact instant at which the
      # reference was still live has no way to present it.
      expect do
        ActiveRecord::Base.connection.raw_connection.exec_params(
          "SELECT * FROM f1_resolve_invitation_reference($1, $2::timestamptz)",
          [digest_param(inv[:reference_digest]), (inv[:expires_at] - 1).iso8601(6)]
        )
      end.to raise_error(PG::UndefinedFunction)
    end

    it "stops resolving at exact equality: now = expires_at yields no binding" do
      inv = TenantSeeder.create_invitation(organization_id: org)
      conn = owner
      conn.exec("BEGIN")
      begin
        # Inside this transaction transaction_timestamp() is constant, so setting
        # expires_at to it makes the comparison an exact equality test.
        conn.exec_params(<<~SQL, [digest_param(inv[:reference_digest])])
          UPDATE invitation_reference_registry SET expires_at = transaction_timestamp()
          WHERE opaque_reference_sha256 = $1
        SQL
        at_equality = conn.exec_params(
          "SELECT * FROM f1_resolve_invitation_reference($1)", [digest_param(inv[:reference_digest])]
        ).to_a
        expect(at_equality).to be_empty

        conn.exec_params(<<~SQL, [digest_param(inv[:reference_digest])])
          UPDATE invitation_reference_registry
          SET expires_at = transaction_timestamp() + interval '1 microsecond'
          WHERE opaque_reference_sha256 = $1
        SQL
        one_microsecond_before = conn.exec_params(
          "SELECT * FROM f1_resolve_invitation_reference($1)", [digest_param(inv[:reference_digest])]
        ).to_a
        expect(one_microsecond_before.size).to eq(1)
      ensure
        conn.exec("ROLLBACK")
      end
    end

    %w[accepted declined rejected revoked expired].each do |state|
      it "does not resolve a #{state} reference" do
        inv = TenantSeeder.create_invitation(organization_id: org, state:)
        expect(resolve(inv[:reference_digest])).to be_empty
      end
    end

    it "does not resolve a pending-approval reference" do
      inv = TenantSeeder.create_invitation(organization_id: org, state: "pending_approval")
      expect(resolve(inv[:reference_digest])).to be_empty
    end

    it "returns the same empty binding for an unknown digest, disclosing nothing" do
      TenantSeeder.create_invitation(organization_id: org)
      expect(resolve(Digest::SHA256.digest("no such reference"))).to be_empty
    end

    it "resolves without any Organization context and never scans a tenant table" do
      other = TenantSeeder.create_organization
      mine = TenantSeeder.create_invitation(organization_id: org)
      theirs = TenantSeeder.create_invitation(organization_id: other)

      # No context is established; the resolver is the pre-context locator and
      # each reference resolves to its own Organization and no other.
      expect(resolve(mine[:reference_digest]).first["organization_id"]).to eq(org)
      expect(resolve(theirs[:reference_digest]).first["organization_id"]).to eq(other)
      expect(ActiveRecord::Base.connection.select_value("SELECT count(*) FROM invitations")).to eq(0)
    end
  end

  describe "the any-state replay locator is unchanged" do
    it "still resolves a terminal reference for the restricted replay path only, and takes no time" do
      inv = TenantSeeder.create_invitation(organization_id: org, state: "accepted")
      row = ActiveRecord::Base.connection.raw_connection.exec_params(
        "SELECT organization_id, invitation_id FROM f1_resolve_invitation_org($1)",
        [digest_param(inv[:reference_digest])]
      ).to_a.first

      expect(row["invitation_id"]).to eq(inv[:invitation_id])
      expect(resolve(inv[:reference_digest])).to be_empty
    end
  end
end
