# frozen_string_literal: true

require "rails_helper"
require_relative "support/wf005_crawl_chain"

# THE TWO RESIDUES ON THE PROTECTED WRITES, MEASURED RATHER THAN ARGUED (FU-58, FU-53).
#
# Both records describe a control that is safe today for a reason OUTSIDE the statement — a caller
# census in one case, an RLS policy in the other — which is the "one deletion away from nothing" shape
# FU-48 exists to remove. Neither could be proved by the existing corpus, because the corpus drives
# the writes only through production callers, and production callers are exactly what makes them safe.
#
# SO BOTH ARE DRIVEN AT THE STORE, WITH THE THING THAT MAKES THEM SAFE REMOVED.
#
# FU-58 — `CommandAuthorizer#confers?` IS FOUR LIMBS AND THE CTE BOUND TWO. A capability in
# `PROTECTED` additionally requires the Assignment's bootstrap-admin exception or its APPROVED
# `protected_permission_allowlist`; `return true unless PROTECTED.key?(capability)` is a property of
# the Ruby evaluator with no analogue in SQL. The exposed surface is exactly two capabilities, and
# that is derived here rather than asserted: `CAPABILITIES.fetch` raises for every `PROTECTED` key it
# does not materialize, so the authority for those cannot be built at all.
#
# FU-53 — `cancel` JUDGED AUTHORITY AGAINST THE SESSION AND WROTE AGAINST AN UNQUALIFIED ID. The
# previous measurement recorded "only RLS stopped the write", which is an observation about the
# database's policy rather than about the statement. `DbInspector`'s connection is a BYPASSRLS
# superuser — the harness already relies on that to read cross-principal state — so driving the store
# on it removes the policy and leaves the statement to answer for itself.
RSpec.describe "WF-005 protected writes carry the whole baseline and write only inside their tenant",
               type: :acceptance, acceptance_ids: ["AC-WF-005", "AC-CAP-007"],
               test_types: %w[TYP-SEC] do
  include Wf005CrawlChain
  self.use_transactional_tests = false
  after { ReceiptMinter.truncate_all }

  def in_org(org)
    Platform::UnitOfWork.run do |conn|
      pg = conn.raw_connection
      pg.exec_params("SELECT f1_enter_org_context($1::uuid, $2::uuid)", [org, SecureRandom.uuid_v7])
      yield pg
    end
  end

  def actor_account(session_id)
    DbInspector.one("SELECT account_id FROM sessions WHERE id = $1::uuid", [session_id])["account_id"]
  end

  # An ORDINARY grant: active, effective, no bootstrap exception, empty allowlist. Seeded directly
  # rather than through WF-013, because WF-013 lands a protected role `pending` by design and a
  # pending Assignment would be refused by a conjunct that is not the one under test.
  def ordinary_grant(org, session_id, canonical_role)
    id = TenantSeeder.create_role_assignment(organization_id: org, account_id: actor_account(session_id),
                                             canonical_role:, permission_mode: "standard", persona: nil,
                                             status: "active", effective_at: Time.utc(2026, 1, 1),
                                             expires_at: nil)
    row = DbInspector.one(<<~SQL, [id])
      SELECT id, state_version, coalesce(encode(scope_sha256,'hex'), '') AS scope_hex,
             bootstrap_admin_exception, protected_permission_allowlist
      FROM role_assignments WHERE id = $1::uuid
    SQL
    raise "the #{canonical_role} grant was not seeded" if row.nil?

    row
  end

  def crawl_state(id) = DbInspector.one("SELECT state FROM crawls WHERE id = $1::uuid", [id])["state"]

  # ---- FU-58 ------------------------------------------------------------------------------------

  # DERIVED, NOT TRANSCRIBED. The record says "the exposed surface is exactly `role.manage` and
  # `invitation.approve`"; that is a consequence of two constants and it must stay a consequence.
  it "exposes exactly the capabilities that are in BOTH the materialized cell table and PROTECTED" do
    exposed = Platform::PermissionBaseline::CAPABILITIES.keys &
              Platform::PermissionBaseline::PROTECTED.keys
    expect(exposed).to contain_exactly("invitation.approve", "role.manage")

    # And the other sixteen really are unbuildable, which is the half that keeps the surface small.
    unexposed = Platform::PermissionBaseline::PROTECTED.keys - exposed
    expect(unexposed).not_to be_empty
    unexposed.each do |capability|
      expect { Platform::PermissionBaseline::CAPABILITIES.fetch(capability) }
        .to raise_error(KeyError), "#{capability} is materialized, so the exposed surface is wider " \
                                   "than this file measures"
    end
  end

  it "refuses a PROTECTED capability whose grant carries no allowlist entry, as Ruby already does" do
    ctx = running_crawl
    org = ctx[:g][:organization_id]
    grant = ordinary_grant(org, ctx[:g][:session_id], "OrganizationAdmin")
    # The premise of the whole example: an ordinary grant, with neither of the two things that would
    # legitimately satisfy the protected limb.
    expect(grant["bootstrap_admin_exception"]).to satisfy { |v| v == false || v == "f" }
    expect(JSON.parse(grant["protected_permission_allowlist"])).to be_empty

    authority = AuthorityFixture.build(organization_id: org, account_id: actor_account(ctx[:g][:session_id]),
                                       capability: "role.manage", grants: [grant])
    expect(authority.protected_capability).to be(true)

    # THE TWO SURFACES ARE COMPARED PER GRANT, WHICH IS THE LEVEL THE WRITE WORKS AT — AND FU-58'S
    # OWN MEASUREMENT IS CORRECTED HERE. The record says "Ruby `authorize` DENIES (`missing_authority`,
    # granting=0)". Driven, `authorize` ALLOWS for a bootstrapped actor, because it aggregates over
    # EVERY effective Assignment and the WF-001 bootstrap grant carries `bootstrap_admin_exception`,
    # which `confers?` accepts. The divergence is real and is PER GRANT, not per actor: the write
    # re-reads the grants the decision relied on, so what must hold is that a grant conferring nothing
    # is refused there. `confers?`'s protected limb is exactly these two reads, and both are false
    # for this Assignment.
    expect(Platform::PermissionBaseline.protected_grant?(
             "role.manage", JSON.parse(grant["protected_permission_allowlist"])
           )).to be(false), "this grant's allowlist confers `role.manage`, so there is no divergence " \
                            "for the write to reproduce and this example proves nothing"

    version = DbInspector.one("SELECT state_version FROM crawls WHERE id = $1::uuid",
                              [ctx[:crawl_id]])["state_version"].to_i
    outcome = in_org(org) do |pg|
      IdentityAccess::Infrastructure::CrawlStartStore.new(pg)
                                                     .cancel(ctx[:crawl_id], version, start_now, authority:)
    end

    expect(outcome[:capability_authorized]).to be(false),
                                               "the write authorized a PROTECTED capability that Ruby " \
                                               "denied: the CTE carries the baseline MINUS its " \
                                               "protected limb (FU-58)"
    expect(outcome[:moved]).to eq(0)
    expect(crawl_state(ctx[:crawl_id])).to eq("running")
  end

  it "admits the same PROTECTED capability once the Assignment's approved allowlist carries it" do
    # NON-VACUITY, AND THE OTHER HALF OF THE RULE. A limb that refused every protected capability
    # would pass the example above while making the allowlist meaningless. :314's "sorted explicit
    # protected-permission allowlist" is what the write must honour, not merely notice.
    ctx = running_crawl
    org = ctx[:g][:organization_id]
    # THE ALLOWLIST IS WRITTEN THE ONLY WAY THE DATABASE PERMITS, and that constraint is itself the
    # point: `f1_role_assignments_lifecycle_guard` raises `role_assignment_allowlist_immutable` for
    # any edit outside the `pending -> active` approval transition, because ":314's approved
    # protected authority is written once, by the transition that makes the grant effective". A first
    # draft of this example UPDATEd an active row and was refused, which is the guard working.
    id = TenantSeeder.create_role_assignment(organization_id: org, account_id: actor_account(ctx[:g][:session_id]),
                                             canonical_role: "OrganizationAdmin", permission_mode: "standard",
                                             persona: nil, status: "pending", effective_at: nil,
                                             expires_at: nil)
    DbInspector.connection.exec_params(<<~SQL, [id, Time.utc(2026, 1, 1), JSON.generate(["role.manage"])])
      UPDATE role_assignments
      SET status = 'active', effective_at = $2::timestamptz, protected_permission_allowlist = $3::jsonb
      WHERE id = $1::uuid
    SQL
    reloaded = DbInspector.one(<<~SQL, [id])
      SELECT id, state_version, coalesce(encode(scope_sha256,'hex'), '') AS scope_hex
      FROM role_assignments WHERE id = $1::uuid
    SQL

    authority = AuthorityFixture.build(organization_id: org, account_id: actor_account(ctx[:g][:session_id]),
                                       capability: "role.manage", grants: [reloaded])
    version = DbInspector.one("SELECT state_version FROM crawls WHERE id = $1::uuid",
                              [ctx[:crawl_id]])["state_version"].to_i
    outcome = in_org(org) do |pg|
      IdentityAccess::Infrastructure::CrawlStartStore.new(pg)
                                                     .cancel(ctx[:crawl_id], version, start_now, authority:)
    end

    expect(outcome[:capability_authorized]).to be(true),
                                               "an APPROVED protected grant was refused, so the new " \
                                               "limb is a blanket denial rather than :314's allowlist"
    expect(outcome[:moved]).to eq(1)
  end

  it "still admits an ordinary NON-protected capability, so the limb is inert where it should be" do
    # The third leg: `crawl.cancel` is not in `PROTECTED`, so the limb must not touch it. Without
    # this, a limb that refused whenever the allowlist was empty would pass both examples above and
    # break every production cancellation.
    ctx = running_crawl
    org = ctx[:g][:organization_id]
    authority = AuthorityFixture.for_session(ctx[:g][:session_id], capability: "crawl.cancel")
    expect(authority.protected_capability).to be(false)

    version = DbInspector.one("SELECT state_version FROM crawls WHERE id = $1::uuid",
                              [ctx[:crawl_id]])["state_version"].to_i
    outcome = in_org(org) do |pg|
      IdentityAccess::Infrastructure::CrawlStartStore.new(pg)
                                                     .cancel(ctx[:crawl_id], version, start_now, authority:)
    end
    expect(outcome[:capability_authorized]).to be(true)
    expect(outcome[:moved]).to eq(1)
  end

  # ---- FU-53 ------------------------------------------------------------------------------------

  it "refuses to cancel a Crawl outside the authority's Organization, with RLS out of the way" do
    # THE MEASUREMENT THE RECORD ASKED FOR. Round 19 drove this through a real session and recorded
    # "only RLS stopped the write". Driven on the BYPASSRLS connection the harness already uses for
    # cross-principal reads, the policy is not there to stop it, and what is left is the statement.
    victim = running_crawl
    victim_org = victim[:g][:organization_id]

    @identity = nil # a second, distinct founder — see the FU-50 spec for why this is how it is done
    attacker = bootstrap
    attacker_org = attacker[:organization_id]
    expect(attacker_org).not_to eq(victim_org)

    authority = AuthorityFixture.for_session(attacker[:session_id], capability: "crawl.cancel")
    expect(authority.organization_id).to eq(attacker_org)

    version = DbInspector.one("SELECT state_version FROM crawls WHERE id = $1::uuid",
                              [victim[:crawl_id]])["state_version"].to_i
    outcome = IdentityAccess::Infrastructure::CrawlStartStore.new(DbInspector.connection)
                                                            .cancel(victim[:crawl_id], version, start_now,
                                                                    authority:)

    # The attacker's OWN authority is entirely valid — that is the point. Both limbs answer about the
    # attacker's Organization and both say yes; only the target predicate refuses.
    expect(outcome[:epoch_authorized]).to be(true)
    expect(outcome[:capability_authorized]).to be(true)
    expect(outcome[:moved]).to eq(0),
                               "a Crawl in another Organization was cancelled by an actor with valid " \
                               "authority in their own: the UPDATE names no organization (FU-53), and " \
                               "`f1_crawls_guard` makes that terminal state unrecoverable"
    expect(crawl_state(victim[:crawl_id])).to eq("running")
  end

  it "still cancels a Crawl inside the authority's Organization on the same connection" do
    # NON-VACUITY for the predicate above: on the same BYPASSRLS connection, the legitimate case must
    # still apply, or the example above would pass because the statement refuses everything.
    ctx = running_crawl
    authority = AuthorityFixture.for_session(ctx[:g][:session_id], capability: "crawl.cancel")
    version = DbInspector.one("SELECT state_version FROM crawls WHERE id = $1::uuid",
                              [ctx[:crawl_id]])["state_version"].to_i

    outcome = IdentityAccess::Infrastructure::CrawlStartStore.new(DbInspector.connection)
                                                            .cancel(ctx[:crawl_id], version, start_now,
                                                                    authority:)
    expect(outcome[:moved]).to eq(1)
    expect(crawl_state(ctx[:crawl_id])).to eq("canceled")
  end
end
