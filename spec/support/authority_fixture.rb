# frozen_string_literal: true

# THE WRITE-LEVEL AUTHORITY A PROOF HANDS TO A STORE DIRECTLY (FU-48).
#
# The store proofs exist because the invariant belongs to the WRITE, so it must hold for any
# production caller rather than only for the one handler a spec drives. Since D7 the write carries
# two axes, and a proof driving the store must be able to build each of them truthfully — and to
# build a deliberately WRONG one, which is what the negative proofs are.
#
# EVERY VALUE IS READ FROM THE DATABASE, never invented: the epoch from `organizations`, the grants
# from `role_assignments`. A fixture that fabricated a grant would prove that a fabricated grant is
# accepted, which is the opposite of the property.
module AuthorityFixture
  module_function

  def for_session(session_id, capability:, epoch: nil, grants: nil, required_role: nil,
                  allowed_roles: nil)
    row = DbInspector.one("SELECT account_id, organization_id FROM sessions WHERE id = $1::uuid", [session_id])
    raise "no session #{session_id}" if row.nil?

    build(organization_id: row["organization_id"], account_id: row["account_id"], capability:, epoch:,
          grants:, required_role:, allowed_roles:)
  end

  # THE DERIVATIONS ARE PRODUCTION'S. THERE IS NO SECOND COPY OF THEM HERE (FU-60).
  #
  # WHAT WAS WRONG, AND WHY IT MATTERED MORE THAN A DUPLICATION USUALLY DOES. This method used to
  # compute `CAPABILITIES.fetch(capability)` and `READ_ONLY_CAPABILITIES.include?(capability)`
  # itself, independently of `WriteAuthority.for`. That is THE MECHANISM THAT HID R-ADV-2: every
  # battery case built its authority through this fixture, so all of them proved what the STATEMENT
  # does with a correct value and none proved the value was DERIVED — which is how three
  # capability-scoped mutations survived 1185 acceptance examples. The expressions were textually
  # identical, so there was no live divergence; the exposure was that `WriteAuthority.for` could gain
  # a third input or change a derivation and every fixture-built case would keep proving the old
  # shape, silently.
  #
  # A GATE OVER TWO COPIES WOULD HAVE BEEN THE WEAKER REPAIR. The follow-up offered one — an
  # architecture example asserting the two agree at every materialized capability. Calling the
  # production builder removes the second copy instead, so there is nothing left to drift; the gate
  # in `spec/architecture/authority_fixture_binding_spec.rb` then proves the CALL is still what
  # happens, rather than proving two expressions still match.
  #
  # `allowed_roles` REMAINS AN OVERRIDE, and must. A fixture that could only build the right
  # authority could not build a deliberately WRONG one, which is what the negative proofs are — see
  # the battery's "the grant is LIVE but its role confers nothing" case, which hands the write the
  # real grant with a cell that excludes its role. The override is applied AFTER the production
  # build, so an overriding caller still gets every other member from the production derivation.
  def build(organization_id:, account_id:, capability:, epoch: nil, grants: nil, required_role: nil,
            allowed_roles: nil)
    actor = IdentityAccess::Authorization::AuthenticatedActor.new(
      account_id:, organization_id:, authorization_epoch: epoch || current_epoch(organization_id)
    )
    # The shape `CommandAuthorizer#authorize` returns on allow, carrying exactly the grants this
    # authority is to be built from — which is the input `WriteAuthority.for` reads.
    decision = IdentityAccess::Authorization::Decision.new(
      allowed: true, reason: "authorized", organization_epoch: actor.authorization_epoch,
      policy_snapshot_id: nil, role_assignment_versions: [],
      granting_assignments: grants || active_grants(organization_id, account_id)
    )
    authority = IdentityAccess::Authorization::WriteAuthority.for(actor:, decision:, capability:,
                                                                  required_role:)
    allowed_roles ? authority.with(allowed_roles:) : authority
  end

  def current_epoch(organization_id)
    DbInspector.one("SELECT authorization_epoch FROM organizations WHERE id = $1::uuid",
                    [organization_id])["authorization_epoch"].to_i
  end

  # EXACTLY THE ROWS `CommandAuthorizer#authorize` SELECTS FROM, BY RUNNING ITS SELECTION (FU-60).
  #
  # WHAT WAS WRONG. This was a second SELECT that only LOOKED like production's, and round 20
  # measured the difference: it selected a WIDER set — 1 row against production's 0 for an
  # active-but-not-yet-effective grant — because it asked for `status = 'active'` alone while
  # `effective_role_assignments` also requires `effective_at IS NOT NULL AND effective_at <= now`
  # and an unelapsed `expires_at`. A fixture that SELECTS differently from production is the same
  # hazard class as one that DERIVES differently, so it is repaired the same way: there is now one
  # copy of the selection and it is production's.
  #
  # THE ORGANIZATION RESTRICTION IS APPLIED HERE BECAUSE THE HARNESS CONNECTION BYPASSES RLS.
  # `effective_role_assignments` filters on `account_id` alone; in production the Organization limb
  # is FORCE RLS on `role_assignments`, entered by `authenticate`. `DbInspector.connection` is the
  # BYPASSRLS superuser (its own header says so), so RLS applies nothing to it and the restriction
  # would simply be missing. It is applied explicitly rather than left to a policy that is not in
  # force on this connection.
  #
  # TWO THINGS THIS BINDING DOES NOT CARRY OVER, STATED RATHER THAN HIDDEN:
  #
  #   * `now` — production takes it from the COMMAND's clock. A fixture has no command, so the
  #     default is the process clock, and a caller proving a time-dependent property must pass the
  #     clock its own decision used. Every seeded grant in this suite is effective well before real
  #     time, so the default selects the same rows the previous hand-written SELECT did.
  #   * `confers?` — production filters the selection by it inside `authorize`, using a predicate
  #     private to `CommandAuthorizer`. It is deliberately not applied: this fixture's stated purpose
  #     includes building the authority a deleted or wrong `confers?` produces upstream, which is
  #     exactly a carried grant that confers nothing.
  def active_grants(organization_id, account_id, now: Time.now.utc)
    rows = IdentityAccess::Infrastructure::AuthorizationStore
           .new(DbInspector.connection)
           .effective_role_assignments(account_id:, now:)
    in_organization(organization_id, rows.map { |r| r["id"] })
      .filter_map { |id| rows.find { |r| r["id"] == id } }
      .map { |r| r.merge("scope_hex" => r["scope_hex"].to_s) }
  end

  # THE ORDER IS THE FIXTURE'S OWN, AND THAT IS DELIBERATE. `effective_role_assignments` carries no
  # `ORDER BY`, and it does not need one: production builds a write's authority and its attestation
  # from ONE `Decision` object, so the two arrays `same_principal?` compares with `==` come from a
  # single selection and cannot disagree about order. A fixture CAN be called twice for the same
  # principal, so an undefined order would make `same_principal?` fail at random. Sorting is what
  # makes that deterministic; it is not a claim that production sorts.
  def in_organization(organization_id, ids)
    return [] if ids.empty?

    DbInspector.all(<<~SQL, [organization_id, "{#{ids.join(',')}}"]).map { |r| r["id"] }
      SELECT id FROM role_assignments
      WHERE organization_id = $1::uuid AND id = ANY($2::uuid[])
      ORDER BY id
    SQL
  end

  # The account the seeder gave a Session in this Organization. Proofs that only hold the
  # Organization use this rather than threading an account id through every helper.
  def sole_account(organization_id)
    DbInspector.all("SELECT DISTINCT account_id FROM role_assignments WHERE organization_id = $1::uuid",
                    [organization_id]).map { |r| r["account_id"] }.first
  end
end
