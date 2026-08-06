# frozen_string_literal: true

require "rails_helper"

# THE RATIFIED PROTECTED ENUMERATION, AT THE GRANT PATH (FU-54 / R19-SEC-2).
#
# WHAT WAS OPEN. `WORKFLOW_SPECIFICATIONS.md:333` is the authority for which grants are protected —
# ":335 This enumeration is the authority" — and it names EIGHTEEN. `Platform::PermissionBaseline::PROTECTED`
# carried FIFTEEN. Two of the three omissions were under-grants in the fail-closed direction, because
# SecurityOperator is already protected through other keys and only the exactness of `:240`'s preview
# was affected.
#
# THE THIRD WAS A LIVE DEFECT, REPRODUCED THREE TIMES INDEPENDENTLY BEFORE THE REPAIR.
# `:175` makes BillingOperator the ONLY role whose `policy.entitlement.manage` cell reads `allow`,
# and BillingOperator appears in no other entry, so `protected_role?("BillingOperator")` was FALSE.
# `request_role_assignment.rb:61` therefore classed the request non-protected, `GrantAuthority.evaluate`
# was called with `direct: true`, and `grant_authority.rb:52`'s `invitation_approval_required` refusal
# never fired. Measured at HEAD before the repair: a lone OrganizationAdmin requesting a BillingOperator
# grant got `success=true`, `status=active`, `expires_at=nil`, `approval_due_at=nil`, zero approval
# records and an empty allowlist.
#
# `:333` requires approval within 24 hours by a SecurityOperator OTHER than the requester and a
# mandatory active expiry; `:140` confines an OrganizationAdmin's `role.manage` cell to "non-protected
# tenant grants". So a single OrganizationAdmin, acting alone, minted an immediately-active
# never-expiring grant carrying protected authority.
#
# NO PROOF ASSERTED THE WRONG STATE AND NONE WOULD HAVE CAUGHT IT: the transcription spec checked
# `CAPABILITIES` against `:135` in two dimensions and had NO check of `PROTECTED` against `:333`.
# That third dimension is now `spec/architecture/permission_baseline_transcription_spec.rb`'s, and
# this file is the behavioural half — the refusal itself, at the handler, with a control.
RSpec.describe "WF-013 the ratified protected enumeration governs the grant path", type: :acceptance,
               acceptance_ids: ["AC-CAP-013", "AC-WF-013"],
               test_types: %w[TYP-SEC TYP-E2E] do
  self.use_transactional_tests = false

  after { ReceiptMinter.truncate_all }

  def fixed_now = Time.utc(2026, 7, 20, 10, 0, 0)
  def org_scope = Digest::SHA256.digest("scope:organization")

  let(:admin) { TenantSeeder.seed_authorized_admin(issued_at: fixed_now - 900) }
  let(:org) { admin[:organization_id] }

  def ctx = Platform::RequestContext.for_actor(clock: Platform::Clock.fixed(fixed_now),
                                               ids: Platform::Ids.system, correlation_id: SecureRandom.uuid_v7)

  def account(subject = "target")
    TenantSeeder.create_account(organization_id: org, issuer_key: "https://id.example/oidc",
                                subject: "#{subject}-#{SecureRandom.hex(6)}")
  end

  # THE EXPIRY IS SUPPLIED, SO THE REFUSAL IS THE APPROVAL RULE AND NOT THE EXPIRY RULE.
  #
  # `:333` demands BOTH of a protected grant: approval within 24 hours by a different SecurityOperator,
  # AND a mandatory active expiry no later than 30 days. `role_expiry_required` fires first when no
  # expiry is given, which would let every example below pass on a limb that is not the one under
  # test — the over-determination this repository rejects everywhere else. Seven days is inside the
  # ratified ceiling, so the expiry limb passes and `invitation_approval_required` is the only thing
  # left that can refuse.
  def request_grant(target, role:, key: "req-#{SecureRandom.hex(3)}", expires_at: fixed_now + (7 * 86_400))
    cmd = Workflows::Wf013::Commands::RequestRoleAssignment.new(
      command_id: SecureRandom.uuid_v7, idempotency_key: key, schema_version: "1.0",
      session_id: admin[:session_id], account_id: target, canonical_role: role,
      permission_mode: "standard", persona: nil, scope_sha256: org_scope, expires_at:,
      expected_authorization_epoch: 7, reason: nil, requested_at_utc: fixed_now
    )
    Workflows::Wf013::Handlers::RequestRoleAssignment.new.call(command: cmd, request_context: ctx)
  end

  def rows_for(target)
    DbInspector.all("SELECT * FROM role_assignments WHERE organization_id = $1::uuid AND account_id = $2::uuid",
                    [org, target])
  end

  # THE ENUMERATION IS THE SUBJECT, NOT ONE MEMBER OF IT (repair the defect class, not the instance).
  #
  # A hand-picked `BillingOperator` case would bind the one omission that was found. The population
  # is DERIVED instead: every canonical role that `:333` makes protected, through the ratified table,
  # must be refused a direct grant. A role that becomes protected later is covered the day the
  # enumeration names it.
  describe "every role the ratified enumeration makes protected is refused a direct grant" do
    # A PROTECTED GRANT IS NOT REFUSED — IT GOES TO APPROVAL, AND CONFERS NOTHING UNTIL IT GETS ONE.
    # That is the property `:333` states and the property BillingOperator did not have: measured
    # before the repair, its request landed `status=active`, `approval_due_at=nil`, conferring
    # protected authority on the requester's say-so alone.
    RatifiedPermissionBaseline.protected_canonical_roles.each do |role|
      it "sends a lone OrganizationAdmin's #{role} grant to APPROVAL rather than making it active" do
        expect(Platform::PermissionBaseline.protected_role?(role)).to be(true),
                                                                      "`:333` makes #{role} protected and " \
                                                                      "`PROTECTED` does not, which is FU-54"

        target = account
        result = request_grant(target, role:)
        expect(result).to be_success, "the protected request was refused outright: #{result.failure&.reason_code}"

        rows = rows_for(target)
        expect(rows.length).to eq(1)
        row = rows.first

        expect(row["status"]).to eq("pending"),
                                 "a lone OrganizationAdmin minted a #{role} grant carrying protected " \
                                 "authority, active on its own say-so"
        # ":316 a pending Assignment confers no permission while pending", and :333's 24-hour rule.
        expect(row["effective_at"]).to be_nil
        expect(row["approval_due_at"]).not_to be_nil
        expect(Time.parse(row["approval_due_at"]) - Time.parse(row["requested_at"])).to eq(24 * 3600)
        expect(JSON.parse(row["protected_permission_allowlist"])).to eq([])
      end
    end

    # NON-VACUITY, AND IT IS THE HALF THAT MATTERS. A `protected_role?` that answered true for every
    # role would satisfy every example above forever while making the platform ungrantable. A role
    # `:333` does NOT protect must still be granted directly, and land ACTIVE.
    it "still grants a NON-protected role directly and active, so the rule is the enumeration and not a blanket" do
      role = (RatifiedPermissionBaseline.canonical_role_columns -
              RatifiedPermissionBaseline.protected_canonical_roles).first
      expect(role).not_to be_nil, "every canonical role is protected, so this control cannot exist"
      expect(Platform::PermissionBaseline.protected_role?(role)).to be(false)

      target = account
      result = request_grant(target, role:)

      expect(result).to be_success, "a non-protected #{role} grant was refused: #{result.failure&.reason_code}"
      expect(rows_for(target).map { |r| r["status"] }).to eq(["active"])
    end
  end

  # THE SPECIFIC SHAPE FU-54 REPRODUCED, PINNED SO IT CANNOT COME BACK QUIETLY.
  #
  # `policy.entitlement.manage` is the reason BillingOperator is protected at all: `:175` gives it the
  # only non-deny cell in that row, and `:333` names the permission. If the entry is ever removed, the
  # derived sweep above stops covering BillingOperator AND this example fails by name.
  it "protects BillingOperator through `policy.entitlement.manage`, which is why the sweep covers it" do
    expect(RatifiedPermissionBaseline.protected_permissions).to include("policy.entitlement.manage")
    expect(RatifiedPermissionBaseline.cell("policy.entitlement.manage", "BillingOperator")).to eq("allow")
    expect(Platform::PermissionBaseline::PROTECTED.fetch("policy.entitlement.manage"))
      .to eq(%w[BillingOperator])
    expect(Platform::PermissionBaseline.protected_permission_preview("BillingOperator"))
      .to eq(%w[policy.entitlement.manage])
  end
end
