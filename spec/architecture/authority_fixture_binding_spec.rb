# frozen_string_literal: true

require "rails_helper"

# THE FIXTURE THAT HID R-ADV-2, BOUND TO THE PRODUCTION IT STANDS IN FOR (FU-60).
#
# WHAT THIS IS ABOUT. `AuthorityFixture` builds the write-level authority a store proof hands to a
# store directly. Until this file existed it built that authority ITSELF: it computed
# `CAPABILITIES.fetch(capability)` and `READ_ONLY_CAPABILITIES.include?(capability)` in its own
# expressions, and it selected the actor's grants with its own SELECT. Both were second copies of
# something production already owns, and `grep -rn AuthorityFixture spec/architecture/` returned
# nothing — so nothing anywhere asserted they agreed.
#
# THAT IS NOT AN UNTIDINESS. It is the mechanism that hid R-ADV-2. Every case in the write battery
# built its authority through this fixture, so all of them proved what the STATEMENT does with a
# correct value and none proved the value was DERIVED — which is how three capability-scoped
# mutations survived 1185 acceptance examples. A harness that computes the answer it is checking is
# the same defect class as a test that asserts a property it does not exercise, one level down.
#
# WHAT IS PROVED HERE AND WHAT IS ONLY DEFENDED, STATED PLAINLY BECAUSE THEY ARE NOT THE SAME
# STRENGTH:
#
#   * THE DERIVATION. The repair removes the copy rather than gating it, so `build` and
#     `WriteAuthority.for` cannot disagree — they are one call. Nothing behavioural can therefore
#     fail if the removal is undone, because the two expressions were textually identical, which is
#     what FU-60 recorded. So the removal is held STRUCTURALLY, by the first example, and the
#     agreement is held as a CONTROL by the second: it cannot fail today, and it is what fails if a
#     later hand re-inlines a copy that drifts.
#   * THE SELECTION. That one IS measurable, because the copies did NOT agree: the fixture selected
#     a WIDER set than `effective_role_assignments`, missing its effectiveness window entirely. The
#     last example drives exactly that difference and fails against the old predicate.
RSpec.describe "AuthorityFixture is bound to the production authority", type: :architecture do
  self.use_transactional_tests = false
  after { ReceiptMinter.truncate_all }

  # A METHOD, NOT A CONSTANT. A constant assigned inside an `RSpec.describe` block lands on Object,
  # where another spec file's identically-named constant silently wins by load order — the defect
  # `permission_baseline_transcription_spec.rb` records having hit for real.
  def fixture_source = File.read(Rails.root.join("spec/support/authority_fixture.rb"))

  # One materialized principal, with the bootstrap OrganizationAdmin grant every tenant carries.
  let(:tenant) { TenantSeeder.seed_authorized_admin }
  let(:org) { tenant[:organization_id] }
  let(:account) { tenant[:account_id] }

  # The actor and decision production would carry for `grants`, built here so the comparison below
  # is against a DIRECT call to the production builder rather than against a second transcription
  # of what it does.
  def production_authority(capability, grants, required_role: nil, required_scope_hex: nil)
    actor = IdentityAccess::Authorization::AuthenticatedActor.new(
      account_id: account, organization_id: org,
      authorization_epoch: DbInspector.one("SELECT authorization_epoch FROM organizations WHERE id = $1::uuid",
                                           [org])["authorization_epoch"].to_i
    )
    decision = IdentityAccess::Authorization::Decision.new(
      allowed: true, reason: "authorized", organization_epoch: actor.authorization_epoch,
      policy_snapshot_id: nil, role_assignment_versions: [], granting_assignments: grants
    )
    IdentityAccess::Authorization::WriteAuthority.for(actor:, decision:, capability:, required_role:,
                                                      required_scope_hex:)
  end

  # THE STRUCTURAL HALF. The property FU-60 names is "there is no second copy of the derivation",
  # and that is a property of the text, so it is asserted against the text — the idiom
  # `write_observer_spec.rb` already uses for a claim its examples cannot reach. This is the
  # assertion that fails the moment the duplication returns; the behavioural control below cannot,
  # because two identical expressions agree.
  it "holds no copy of the capability derivations, and builds through the production builder" do
    source = fixture_source

    expect(source).to include("WriteAuthority.for("),
                      "the fixture no longer routes through the production builder, so every " \
                      "fixture-built case is proving the fixture again"
    expect(source).not_to match(/PermissionBaseline::CAPABILITIES/),
                          "the fixture has its own copy of the `allowed_roles` derivation again — " \
                          "the expression whose duplicate hid R-ADV-2"
    expect(source).not_to match(/PermissionBaseline::READ_ONLY_CAPABILITIES/),
                          "the fixture has its own copy of the `read_only_permitted` derivation " \
                          "again — round-18 CB-1's column, unbound"
    expect(source).not_to match(/WriteAuthority\.new/),
                          "the fixture constructs the authority member by member again, which is " \
                          "how a member production later derives differently goes unnoticed here"
  end

  # THE CONTROL. It cannot fail while `build` IS the production call; it is what fails if a copy
  # comes back and drifts. It is deliberately wider than the follow-up's suggested gate, which named
  # `allowed_roles` and `read_only_permitted` alone: a member added to `WriteAuthority` and derived
  # only in production would satisfy that gate and diverge here, which is this tranche's own defect
  # class inside the repair for it.
  it "agrees with `WriteAuthority.for` on EVERY member, at EVERY materialized capability" do
    grants = AuthorityFixture.active_grants(org, account)
    expect(grants).not_to be_empty,
                          "the principal carries no grant, so every comparison below would compare " \
                          "two empty authorities and prove nothing"

    Platform::PermissionBaseline::CAPABILITIES.each_key do |capability|
      built = AuthorityFixture.build(organization_id: org, account_id: account, capability:,
                                     grants:)

      expect(built).to eq(production_authority(capability, grants)),
                       "the fixture and `WriteAuthority.for` disagree at #{capability}"
    end
  end

  # THE SCOPE RULE TOO, because `required_role` is the one input a fixture caller passes through
  # rather than derives, and a builder that dropped it would leave every fixture-built policy case
  # driving the write at a configuration production never uses (R20-2's shape).
  it "agrees with the production builder when a scope rule is carried" do
    grants = AuthorityFixture.active_grants(org, account)

    built = AuthorityFixture.build(organization_id: org, account_id: account,
                                   capability: "policy.crawl.manage", grants:,
                                   required_role: "OrganizationAdmin")

    expect(built).to eq(production_authority("policy.crawl.manage", grants,
                                             required_role: "OrganizationAdmin"))
  end

  # AND THE CONTAINMENT OPERAND, FOR THE SAME REASON (FU-2, sited by FU-49). `required_scope_hex` is
  # the second input a fixture caller passes through rather than derives, and it is the member this
  # example's own comment above predicted: "a member added to `WriteAuthority` and derived only in
  # production would satisfy that gate and diverge here". A fixture that silently dropped it would
  # build every policy case with NO containment claim, so the write's new conjunct would be vacuous
  # in every fixture-driven proof while production carried it.
  it "agrees with the production builder when a containment scope is carried" do
    grants = AuthorityFixture.active_grants(org, account)
    org_scope = IdentityAccess::Authorization::GrantAuthority::ORGANIZATION_SCOPE_HEX

    built = AuthorityFixture.build(organization_id: org, account_id: account,
                                   capability: "policy.crawl.manage", grants:,
                                   required_role: "OrganizationAdmin", required_scope_hex: org_scope)

    expect(built.required_scope_hex).to eq(org_scope),
                                        "the fixture dropped the containment operand, so every " \
                                        "fixture-built policy case would drive the write with no " \
                                        "containment claim while production carries one"
    expect(built).to eq(production_authority("policy.crawl.manage", grants,
                                             required_role: "OrganizationAdmin",
                                             required_scope_hex: org_scope))
  end

  # THE OVERRIDE MUST SURVIVE, AND MUST OVERRIDE ONE MEMBER ONLY. The fixture's stated purpose
  # includes building a deliberately WRONG authority — the battery's "the grant is LIVE but its role
  # confers nothing" case hands the write the real grant with a cell that excludes its role — so a
  # binding that removed the override would delete a negative proof. An override that reached any
  # OTHER member would put the fixture back in the business of deriving.
  it "overrides `allowed_roles` on request, and changes nothing else" do
    grants = AuthorityFixture.active_grants(org, account)
    derived = AuthorityFixture.build(organization_id: org, account_id: account,
                                     capability: "crawl.cancel", grants:)
    overridden = AuthorityFixture.build(organization_id: org, account_id: account,
                                        capability: "crawl.cancel", grants:,
                                        allowed_roles: %w[NoSuchRole])

    expect(overridden.allowed_roles).to eq(%w[NoSuchRole])
    expect(overridden.to_h.except(:allowed_roles)).to eq(derived.to_h.except(:allowed_roles)),
                                                     "overriding the cell moved a member that is " \
                                                     "not the cell"
  end

  # THE SELECTION, DRIVEN AT THE DIFFERENCE ROUND 20 MEASURED (FU-60's round-20 extension).
  #
  # The old fixture asked for `status = 'active'` and nothing else. `effective_role_assignments`
  # also requires `effective_at IS NOT NULL AND effective_at <= now` and an unelapsed `expires_at`,
  # so the fixture selected a WIDER set — measured at 1 row against production's 0 for an
  # active-but-not-yet-effective grant. This is that grant, and this example is what the old
  # predicate fails.
  it "selects the rows production selects, and not the ones only it selected" do
    effective_from = Time.utc(2026, 9, 1)
    not_yet = TenantSeeder.create_role_assignment(organization_id: org, account_id: account,
                                                  canonical_role: "MarketingOperator",
                                                  effective_at: effective_from)
    before = effective_from - 3600
    after = effective_from + 3600

    expect(AuthorityFixture.active_grants(org, account, now: before).map { |g| g["id"] })
      .not_to include(not_yet),
              "the fixture carried a grant that is not yet effective, which production's " \
              "selection excludes — the exact row round 20 measured at 1 against production's 0"
    expect(AuthorityFixture.active_grants(org, account, now: after).map { |g| g["id"] })
      .to include(not_yet),
          "the fixture excluded an effective grant, so the narrowing went too far and every " \
          "fixture-built authority is now missing grants production would carry"

    # AND IT IS PRODUCTION'S OWN SELECTION THAT DECIDES, at both instants, restricted to this
    # Organization because `DbInspector.connection` is the BYPASSRLS superuser and the FORCE RLS
    # that scopes production's query is not in force on it.
    store = IdentityAccess::Infrastructure::AuthorizationStore.new(DbInspector.connection)
    [before, after].each do |now|
      expected = store.effective_role_assignments(account_id: account, now:).map { |r| r["id"] }
      expect(AuthorityFixture.active_grants(org, account, now:).map { |g| g["id"] })
        .to match_array(expected), "the fixture's selection diverges from production's at #{now}"
    end
  end

  # NON-VACUITY OF THE COMPARISON ABOVE. `effective_role_assignments` filters on `account_id` alone
  # and leaves the Organization limb to RLS. On a BYPASSRLS connection that limb applies nothing, so
  # the fixture applies it explicitly — and if it stopped, the comparison above would still pass
  # while every fixture-built authority carried another Organization's grants.
  it "restricts to the Organization that RLS would have restricted to" do
    other = TenantSeeder.seed_authorized_admin
    shared = TenantSeeder.create_role_assignment(organization_id: other[:organization_id],
                                                 account_id: account,
                                                 canonical_role: "MarketingOperator")

    unrestricted = IdentityAccess::Infrastructure::AuthorizationStore
                   .new(DbInspector.connection)
                   .effective_role_assignments(account_id: account, now: Time.now.utc)
                   .map { |r| r["id"] }

    expect(unrestricted).to include(shared),
                            "the cross-Organization grant was not selected at all, so this example " \
                            "is not driving the restriction it claims to"
    expect(AuthorityFixture.active_grants(org, account).map { |g| g["id"] }).not_to include(shared)
  end
end
