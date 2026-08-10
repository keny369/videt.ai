# frozen_string_literal: true

require "rails_helper"
require_relative "support/wf005_crawl_chain"

# A PROTECTED WRITE'S ORGANIZATION COMES FROM THE AUTHENTICATED SESSION, NEVER FROM CALLER INPUT (FU-50).
#
# WHAT WAS OPEN, AND HOW NARROW IT REALLY WAS. The capability CTE is written three times.
# `CrawlStartStore#cancel` bound `authority.organization_id` into `ra.organization_id`;
# `CrawlStore#insert_crawl` and `CrawlPolicyStore#activate_version` bound `row[:organization_id]`.
# Round 19 recorded that as a live divergence. Re-traced at every call site it is not one:
# `QueueCrawl#commit` and `ActivateCrawlPolicy` both set `org = actor.organization_id` and build
# their authority with `WriteAuthority.for(actor:)`, whose `organization_id` IS `actor.organization_id`,
# so the two operands are the same value at both writes today.
#
# WHAT WAS ACTUALLY UNPROVED IS THAT NOTHING ENFORCED THE AGREEMENT. A caller passing a row
# organization other than the authenticated one would have sent the capability CTE looking for grants
# in the CALLER-SUPPLIED organization, and round 20 measured that `ra.organization_id` was bound by
# NOTHING across the entire suite — the only reaction to unbinding it was a byte-digest staleness
# check that fires identically for a comment-only edit.
#
# WHY THE REFUSAL AND NOT ONLY THE REBINDING. The owner's decision is that all three writes bind
# `authority.organization_id`, because that value is derived from the authenticated Session. Binding
# alone only decides WHICH value wins: after it, the authority limbs answer about the authenticated
# Organization while the row still carries another one, and the INSERT is then refused by
# `crawls_context` / `crawl_policies_context` — an RLS error from the database rather than a broken
# contract at the store. So the store refuses the divergence itself, before the statement, naming
# both values.
#
# WHAT THIS FILE PROVES AND WHAT IT DOES NOT. It proves the REFUSAL, by execution, against a real
# second Organization bootstrapped through the real WF-001 chain. It does NOT prove which parameter
# the statement binds — that cannot be shown behaviourally once divergence is refused, and it is
# proved instead by `spec/architecture/capability_cte_equivalence_spec.rb`, which reads the operand
# out of each store's own parameter list.
RSpec.describe "WF-005 protected writes derive their organization from the authenticated authority",
               type: :acceptance, acceptance_ids: ["AC-WF-005", "AC-CAP-007"],
               test_types: %w[TYP-SEC TYP-DATA] do
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

  # A REAL SECOND ORGANIZATION, not a fabricated uuid. `identity` is memoized per example so that one
  # bootstrap keeps one identity throughout; clearing it is how this chain produces a second, distinct
  # founder — and therefore a second Organization the database actually holds. A nonexistent uuid
  # would leave "it refused an unknown organization" as a live alternative explanation.
  def another_organization
    @identity = nil
    bootstrap[:organization_id]
  end

  def queueable_org
    g = bootstrap
    sid = register_source(g, "https://fu50.acme.example")
    verify(g, sid)
    activate_source(g, sid)
    raise "activation failed" unless activate_project(g).success?

    g
  end

  def queue(env, organization_id, authority)
    in_org(env[:org]) do |pg|
      IdentityAccess::Infrastructure::CrawlStore.new(pg).insert_crawl(
        id: SecureRandom.uuid_v7, now: act_now, correlation_id: SecureRandom.uuid_v7,
        organization_id:, authority:, project_id: env[:project], kind: "root",
        requested_crawl_policy_id: nil, requested_crawl_policy_version: nil,
        requested_entitlement_policy_id: SecureRandom.uuid_v7,
        requested_entitlement_policy_version: "entitlement-interim-v1",
        trigger_kind: "manual", triggered_by_account_id: nil, idempotency_key_digest: "\x00" * 32
      )
    end
  end

  def activate_policy(env, organization_id, authority)
    in_org(env[:org]) do |pg|
      IdentityAccess::Infrastructure::CrawlPolicyStore.new(pg).activate_version(
        id: SecureRandom.uuid_v7, now: act_now, correlation_id: SecureRandom.uuid_v7,
        organization_id:, authority:, project_id: nil, scope: "organization",
        policy_version: "crawl-policy-organization-v1", supersedes_id: nil,
        expected_state_version: nil, activated_by_account_id: authority.account_id,
        normalized_bounds: Workflows::Wf005::CrawlPolicy::GLOBAL_CEILING, content_sha256: "\x00" * 32
      )
    end
  end

  def crawls_in(org)
    DbInspector.all("SELECT id FROM crawls WHERE organization_id = $1::uuid", [org])
  end

  def policies_in(org)
    DbInspector.all("SELECT id FROM crawl_policies WHERE organization_id = $1::uuid", [org])
  end

  it "refuses a queue insert whose row organization is not the authenticated one, and writes nothing" do
    g = queueable_org
    env = { org: g[:organization_id], project: g[:project_id] }
    other = another_organization
    authority = AuthorityFixture.for_session(g[:session_id], capability: "crawl.trigger")

    expect { queue(env, other, authority) }
      .to raise_error(Platform::InvariantViolation, /CrawlStore#insert_crawl.*never from caller input/m)

    # NEITHER organization gains a Crawl. A refusal that wrote into the AUTHENTICATED organization
    # instead would be a silent substitution of the caller's target, which is not a refusal.
    expect(crawls_in(other)).to be_empty
    expect(crawls_in(env[:org])).to be_empty
  end

  it "refuses a policy activation whose row organization is not the authenticated one, and writes nothing" do
    g = bootstrap
    env = { org: g[:organization_id], project: g[:project_id] }
    other = another_organization
    authority = AuthorityFixture.for_session(g[:session_id], capability: "policy.crawl.manage",
                                             required_role: "OrganizationAdmin")

    expect { activate_policy(env, other, authority) }
      .to raise_error(Platform::InvariantViolation,
                      /CrawlPolicyStore#activate_version.*never from caller input/m)

    expect(policies_in(other)).to be_empty
    expect(policies_in(env[:org])).to be_empty
  end

  it "names both organizations in the refusal, so the defect is diagnosable from the message alone" do
    g = bootstrap
    env = { org: g[:organization_id], project: g[:project_id] }
    other = another_organization
    authority = AuthorityFixture.for_session(g[:session_id], capability: "policy.crawl.manage",
                                             required_role: "OrganizationAdmin")

    expect { activate_policy(env, other, authority) }
      .to raise_error(Platform::InvariantViolation, /#{Regexp.escape(other)}.*#{Regexp.escape(env[:org])}/m)
  end

  # NON-VACUITY. Every example above asserts a refusal, so a store that refused EVERYTHING would pass
  # all three. These two are the same calls with the organizations agreeing, and they must commit.
  it "still queues a Crawl when the row organization IS the authenticated one" do
    g = queueable_org
    env = { org: g[:organization_id], project: g[:project_id] }
    authority = AuthorityFixture.for_session(g[:session_id], capability: "crawl.trigger")

    outcome = queue(env, env[:org], authority)

    expect(outcome[:authorized]).to be(true)
    expect(outcome[:inserted]).to eq(1)
    expect(crawls_in(env[:org]).length).to eq(1)
  end

  it "still activates a crawl policy when the row organization IS the authenticated one" do
    g = bootstrap
    env = { org: g[:organization_id], project: g[:project_id] }
    authority = AuthorityFixture.for_session(g[:session_id], capability: "policy.crawl.manage",
                                             required_role: "OrganizationAdmin")

    outcome = activate_policy(env, env[:org], authority)

    expect(outcome[:authorized]).to be(true)
    expect(outcome[:inserted]).to eq(1)
    expect(policies_in(env[:org]).length).to eq(1)
  end
end
