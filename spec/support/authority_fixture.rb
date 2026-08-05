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

  # `allowed_roles` DEFAULTS TO THE RATIFIED CELL, so a fixture proves the production shape unless it
  # deliberately builds a wrong one (round-17 finding R17-SEC-1).
  def build(organization_id:, account_id:, capability:, epoch: nil, grants: nil, required_role: nil,
            allowed_roles: nil)
    IdentityAccess::Authorization::WriteAuthority.new(
      organization_id:, account_id:, capability:, required_role:,
      allowed_roles: allowed_roles || Platform::PermissionBaseline::CAPABILITIES.fetch(capability),
      epoch: epoch || current_epoch(organization_id),
      grant_ids: (grants || active_grants(organization_id, account_id)).map { |g| g["id"] },
      grant_versions: (grants || active_grants(organization_id, account_id)).map { |g| g["state_version"].to_i },
      grant_scopes: (grants || active_grants(organization_id, account_id)).map { |g| g["scope_hex"].to_s }
    )
  end

  def current_epoch(organization_id)
    DbInspector.one("SELECT authorization_epoch FROM organizations WHERE id = $1::uuid",
                    [organization_id])["authorization_epoch"].to_i
  end

  # EXACTLY THE ROWS `CommandAuthorizer#authorize` SELECTS FROM, in the same shape its decision
  # carries them: id, state version, and the hex scope digest the write compares.
  def active_grants(organization_id, account_id)
    DbInspector.all(<<~SQL, [organization_id, account_id])
      SELECT id, state_version, coalesce(encode(scope_sha256, 'hex'), '') AS scope_hex
      FROM role_assignments
      WHERE organization_id = $1::uuid AND account_id = $2::uuid AND status = 'active'
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
