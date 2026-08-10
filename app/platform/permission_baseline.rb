# frozen_string_literal: true

module Platform
  # The ratified Permission Baseline (`permission-baseline-v1`,
  # WORKFLOW_SPECIFICATIONS.md § Permission Baseline table :135-141, referenced by
  # the mandatory `access-policy-v1` at :320). It is a fixed data table mapping a
  # canonical capability to the canonical roles the baseline ALLOWS; every other
  # role denies. Only ratified rows this build actually consumes are present —
  # adding a further ratified capability is a data addition here and requires no
  # change to the evaluator's semantics. It is not a policy engine: Access Policy
  # deny-subtraction and protected-permission approval live in the caller and the
  # (deferred) full effective-permission engine.
  module PermissionBaseline
    module_function

    VERSION = "permission-baseline-v1"

    # capability => the canonical roles the baseline allows (WORKFLOW_SPECIFICATIONS.md:140).
    # `invitation.create` and `invitation.revoke` share one baseline row —
    # "allow within the actor's grant authority" for OrganizationAdmin, deny for
    # every other role — and neither is a protected permission (:333 omits both),
    # so no protected-allowlist or dual-control gate applies to them.
    # `invitation.approve` reads "protected explicit grant" for SecurityOperator,
    # so the baseline allow is necessary but not sufficient: see PROTECTED below.
    CAPABILITIES = {
      "invitation.create" => %w[OrganizationAdmin].freeze,
      "invitation.revoke" => %w[OrganizationAdmin].freeze,
      "invitation.approve" => %w[SecurityOperator].freeze,
      # ":138 `organization.suspend`, `organization.reactivate` | allow for own
      # Organization | … | support-session only | …". The SecurityOperator arm is
      # support-session-only and Support Sessions are a later slice, so only the
      # OrganizationAdmin arm is reachable here; neither is a protected permission
      # (:333 omits both), so no protected-allowlist gate applies.
      "organization.suspend" => %w[OrganizationAdmin].freeze,
      "organization.reactivate" => %w[OrganizationAdmin].freeze,
      # ":140 `role.manage` | allow for non-protected tenant grants | deny | deny |
      # allow |". It IS a protected permission (:333), so the baseline allow is
      # necessary but not sufficient: step 4's allowlist gate applies, and the
      # OrganizationAdmin cell's "non-protected tenant grants" limb is enforced by
      # IdentityAccess::Authorization::GrantAuthority.
      "role.manage" => %w[OrganizationAdmin SecurityOperator].freeze,
      # ":140 `project.create` | allow | allow | deny | deny |" (WF-002 actors are
      # Organization Administrator and Marketing Operator). It is NOT a protected
      # permission (:333 omits it), so the baseline allow is sufficient and no
      # protected-allowlist gate applies. `project.activate` (materialized below) is the ONLY
      # other Project permission Volume I defines, and holding `project.create` never implies it
      # (S-03.json MTX-027 actor / WF-002 Security Notes).
      "project.create" => %w[OrganizationAdmin MarketingOperator].freeze,
      # CAP-003 / WF-002 Project activation (S-03; contracts/S-03.json MTX-027; owner D3,
      # DECISIONS ADR-072). `project.activate` (WORKFLOW_SPECIFICATIONS.md § Permission Baseline
      # :143 "allow | allow | deny | deny | deny | deny | deny"): an OrganizationAdmin or
      # MarketingOperator may activate a draft Project (draft->active, gated on >=1 active
      # same-Project Source). Every other role denies. NOT a protected permission; holding
      # project.create never implies it.
      "project.activate" => %w[OrganizationAdmin MarketingOperator].freeze,
      # ":140 `source.register` | allow | allow | deny | allow |" — the CAP-004
      # actors are Organization Administrator, Marketing Operator and Technical
      # Implementer. It is NOT a protected permission (:333 omits it). The later
      # Source scope and activation/disable/removal permissions (S-06) remain
      # deliberately absent until their slices consume them.
      "source.register" => %w[OrganizationAdmin MarketingOperator TechnicalImplementer].freeze,
      # CAP-005 / WF-003 Ownership Verification. `source.verify` is the canonical
      # verification permission (contracts/S-05.json permission_checks): Verification
      # Request creation is allowed to an Organization Administrator or a Technical
      # Implementer, and every other role denies. It is NOT a protected permission
      # (:333 omits it), so the baseline allow is sufficient and no protected-
      # allowlist gate applies. The same permission later governs pending-challenge
      # retrieval and cancellation (QRY-021 / CancelVerificationRequest), which are
      # not built in this limb.
      "source.verify"   => %w[OrganizationAdmin TechnicalImplementer].freeze,
      # CAP-006 / WF-004 Source Discovery and Scope. `source.scope.propose` governs
      # proposing a Source Scope Change (WORKFLOW_SPECIFICATIONS.md § Permission Baseline
      # :144 "`source.register`, `source.scope.propose` | allow | allow | allow | deny |
      # deny | deny"): allowed to an OrganizationAdmin, MarketingOperator or Technical
      # Implementer, every other role denies. It is NOT a protected permission (:333 omits
      # it), so the baseline allow is sufficient and no protected-allowlist gate applies.
      # It is materialized here for S-06-003 exactly as `source.verify` was for S-05-001;
      # `policy.source_scope.manage` (activation, S-06-004) and `source.lifecycle.manage`
      # (lifecycle, S-06-006) are materialized below as their slices consume them.
      "source.scope.propose" => %w[OrganizationAdmin MarketingOperator TechnicalImplementer].freeze,
      # CAP-006 / WF-004 Source Scope policy activation. `policy.source_scope.manage`
      # governs activating a Source Scope Policy version — the atomic contraction fast-path
      # on ProposeSourceScopeChange and approval in DecideSourceScopeChange
      # (WORKFLOW_SPECIFICATIONS.md § Permission Baseline :172 "`policy.source_scope.manage`
      # | allow | allow for Project scope | deny | deny | deny | deny | deny"): allowed to an
      # OrganizationAdmin (Organization scope) or a MarketingOperator (Project scope), every
      # other role denies. It is NOT a protected permission (:333 omits it). Materialized here
      # for S-06-004. The Project-vs-Organization scope limb of the MarketingOperator cell —
      # GrantScope containment of the Assignment's scope against the target Source's Project —
      # is NOT yet enforced: assignment-scope containment is wired only to `role.manage`
      # (IdentityAccess::Domain::GrantAuthority#contains_scope?) and remains deferred
      # platform-wide for the resource capabilities (as for `source.register` and
      # `project.create`); the WF-004 handlers gate only Organization membership + the
      # dual-control rule. Recorded as a cross-cutting follow-up (DECISIONS ADR-063). Only an
      # OrganizationAdmin may approve or reject an EXPANSION (dual control lives in the handler).
      "policy.source_scope.manage" => %w[OrganizationAdmin MarketingOperator].freeze,
      # CAP-006 / WF-004 Source lifecycle transitions (PRULE-006): ActivateSource,
      # DisableSource, ReactivateSource, RemoveSource (WORKFLOW_SPECIFICATIONS.md § Permission
      # Baseline :145 "`source.lifecycle.manage` | allow | allow | deny | deny | deny | deny"):
      # allowed to an OrganizationAdmin or a MarketingOperator only; a TechnicalImplementer
      # cannot mutate lifecycle regardless of other permissions (S-06.json MTX-057). NOT a
      # protected permission (:333 omits it). Materialized here for S-06-006. The scope-limb
      # deferral recorded for policy.source_scope.manage (ADR-063 FU-2) applies identically.
      "source.lifecycle.manage" => %w[OrganizationAdmin MarketingOperator].freeze,
      # CAP-007 / WF-005 Crawl policy narrowing (S-07-001). `policy.crawl.manage`
      # (WORKFLOW_SPECIFICATIONS.md § Permission Baseline :173 "allow to narrow Organization
      # bounds | allow to narrow Project bounds | deny | deny | deny | deny"): an
      # OrganizationAdmin may narrow the ORGANIZATION-scope crawl policy; a MarketingOperator
      # may narrow a PROJECT-scope crawl policy; every other role denies. The Org-vs-Project
      # SCOPE limb is enforced in the ActivateCrawlPolicy handler (an OrganizationAdmin at
      # organization scope, a MarketingOperator at project scope). It implies NO crawl-execution
      # permission (crawl.trigger etc. are separate). NOT a protected permission (:333 omits it).
      # The scope-containment deferral (ADR-063 FU-2) applies identically. Materialized here for
      # S-07-001; the release service activates the global safety ceiling only (deferred; the
      # frozen crawl-policy-v1 constant is the interim ceiling, ADR-068).
      "policy.crawl.manage" => %w[OrganizationAdmin MarketingOperator].freeze,
      # CAP-007 / WF-005 Crawl trigger (S-07-002). `crawl.trigger` (WORKFLOW_SPECIFICATIONS.md
      # § Permission Baseline :147 "allow | allow | deny | deny | deny | deny | scheduler only"):
      # an OrganizationAdmin or MarketingOperator may queue a manual Crawl; the Project
      # scheduler service identity queues configured schedules through its own service path (not
      # a baseline role). Every other role denies. NOT a protected permission (:333 omits it).
      # Materialized here for S-07-002.
      "crawl.trigger" => %w[OrganizationAdmin MarketingOperator].freeze,
      # CAP-007 / WF-005 Crawl cancellation (S-07-009). :147 puts `crawl.cancel` in the SAME ROW as
      # `crawl.trigger` — "allow | allow | deny | deny | deny | deny | scheduler only" — so it is
      # transcribed with the same two roles and no others. It is a SEPARATE permission even though the
      # cells are identical: :738 says "cancellation requires `crawl.cancel`", and collapsing two
      # ratified permissions into one because today's cells agree is how a later divergence in the
      # table becomes silently unimplementable. NOT a protected permission (:333 omits it).
      "crawl.cancel" => %w[OrganizationAdmin MarketingOperator].freeze,
      # THE CUSTOMER-FACING READS, materialized for the first time (OD-020; :202 "Each
      # read is tenant-scoped, is denied outside an explicit grant, confers no write
      # authority, and is never implied by holding a companion mutation permission").
      # Until now not one read was transcribed, so every read answered `deny` and no read
      # screen could render at all.
      #
      # ":154 `organization.read` | allow for own Organization | allow for own
      # Organization | allow for own Organization | support-session only | allow for own
      # Organization | allow for own Organization | workflow-specific only". The
      # SecurityOperator arm is support-session-only, deferred exactly as the two
      # Organization lifecycle rows are. BillingOperator IS allowed here, and only here
      # among the reads.
      "organization.read" => %w[OrganizationAdmin MarketingOperator TechnicalImplementer BillingOperator].freeze,
      # ":155 `project.read`, `source.read`, `crawl.read`, `evaluation.read` | allow |
      # allow | allow | authorized incident/adjudication scope only | deny | allow |
      # workflow-specific only". One ratified row, four capabilities: BillingOperator
      # denies, and the SecurityOperator cell is conditional on an incident/adjudication
      # scope this build has no mechanism for, so it is deferred rather than transcribed.
      # `evaluation.read` is deliberately NOT materialized — no Evaluation read screen
      # exists, and an allow nothing consumes is an unexercised one.
      "project.read" => %w[OrganizationAdmin MarketingOperator TechnicalImplementer].freeze,
      "source.read" => %w[OrganizationAdmin MarketingOperator TechnicalImplementer].freeze,
      "crawl.read" => %w[OrganizationAdmin MarketingOperator TechnicalImplementer].freeze,
      # ":168 `measurement_set.activate` | deny | deny | deny | deny | deny | deny |
      # owner-approval release service only". THE EMPTY ALLOW-LIST IS THE WHOLE CELL, and it is
      # transcribed rather than left unmapped for the reason the READ_ONLY_MODE note below already
      # states in words: "an empty allow-set that is CONSULTED is a control; an unconsulted one is
      # what R3-10 found."
      #
      # Until now this row was absent, so `permits?` raised `InvariantViolation` on it. That is
      # fail-closed and it is not the same thing as a transcribed denial: an unmapped capability
      # reads as "nobody has written this row down yet", and the next person to materialize it has
      # no ratified cell in front of them. Now the row is here, its six actor columns all deny, and
      # the three transcription dimensions check it against :168 like every other row.
      #
      # The seventh column is not a role and is not expressible here. It names
      # `Platform::ServiceIdentity::RELEASE_SERVICE`, which `Workflows::Wf006::OwnerApprovalRelease`
      # executes under — so no value of `roles` makes `permits?` true, for any actor, in any mode.
      "measurement_set.activate" => [].freeze
    }.freeze

    # The ratified protected-grant enumeration (:331-333 "Grants containing … are
    # protected. … This enumeration is the authority for which grants are
    # protected"), restricted to the permissions that appear in the Permission
    # Baseline table, each mapped to the canonical roles whose baseline cell is
    # anything other than `deny`.
    #
    # This is a transcription of ratified cells, not a policy. It answers exactly
    # one question the Invitation record requires (:240 "exact protected-permission
    # preview"): which protected permissions does a grant of this canonical role
    # contain? A permission is in a role's preview when the enumeration names it
    # AND the baseline cell for that role is not `deny`.
    #
    # IT WAS THREE SHORT, AND ONE OF THE THREE WAS A LIVE DEFECT (FU-54 / R19-SEC-2).
    # `:333` names EIGHTEEN and this map carried FIFTEEN. The transcription check
    # compared `CAPABILITIES` against `:135` in two dimensions and had NO third
    # dimension for `PROTECTED` against `:333`, so nothing could see the gap —
    # deleting a ratified entry left the whole suite green.
    #
    #   `security.investigation.approve` (:185, SecurityOperator "protected explicit
    #   grant") and the SecurityOperator `organization.close` arm (:139, "protected
    #   approval only") were UNDER-GRANTS IN THE FAIL-CLOSED DIRECTION: SecurityOperator
    #   is already protected through other keys, so `protected_role?` was unaffected and
    #   only the exactness of :240's preview was wrong.
    #
    #   `policy.entitlement.manage` WAS NOT. `:175` makes BillingOperator the ONLY role
    #   whose cell for it reads `allow`, and BillingOperator appears in no other entry,
    #   so `protected_role?("BillingOperator")` was FALSE. `RequestRoleAssignment` therefore
    #   classed such a request non-protected and took the DIRECT grant path, and a lone
    #   OrganizationAdmin minted an immediately-active, never-expiring grant carrying
    #   protected authority — against :333's "approval within 24 hours by a SecurityOperator
    #   other than the requester", :316's mandatory expiry, and :140's confinement of an
    #   OrganizationAdmin's `role.manage` cell to "non-protected tenant grants".
    #
    # `organization.close` CARRIES ONLY ITS SecurityOperator ARM, because :333 says so in
    # words: "A SecurityOperator `organization.close` grant authorizes only closure approval
    # or rejection; the OrganizationAdmin baseline cell permitting a closure request for the
    # actor's own Organization is not a protected grant and is unchanged." Every other entry
    # takes its whole non-deny row. That single exception is recorded as data in
    # `spec/support/ratified_permission_baseline.rb` rather than as a judgement here, so the
    # transcription check derives this map from the document and adding a second exception is
    # a visible act.
    PROTECTED = {
      "account.delete" => %w[OrganizationAdmin SecurityOperator].freeze,
      "account.revoke" => %w[OrganizationAdmin SecurityOperator].freeze,
      "account.suspend" => %w[OrganizationAdmin SecurityOperator].freeze,
      "credential.revoke" => %w[SecurityOperator].freeze,
      "credential.rotate" => %w[SecurityOperator].freeze,
      "evidence.restricted.read" => %w[OrganizationAdmin SecurityOperator].freeze,
      "evidence.validation.manage" => %w[SecurityOperator].freeze,
      "invitation.approve" => %w[SecurityOperator].freeze,
      "issue.adjudicate" => %w[SecurityOperator].freeze,
      "legal_hold.manage" => %w[SecurityOperator].freeze,
      "organization.close" => %w[SecurityOperator].freeze,
      "policy.access.manage" => %w[OrganizationAdmin SecurityOperator].freeze,
      "policy.entitlement.manage" => %w[BillingOperator].freeze,
      "policy.export.manage" => %w[OrganizationAdmin SecurityOperator].freeze,
      "role.manage" => %w[OrganizationAdmin SecurityOperator].freeze,
      "security.investigate" => %w[SecurityOperator].freeze,
      "security.investigation.approve" => %w[SecurityOperator].freeze,
      "support.session.approve" => %w[SecurityOperator].freeze
    }.freeze

    # The exact protected-permission preview for a grant of `canonical_role`:
    # sorted, and empty for a role that contains none. An Invitation offering a
    # role with a non-empty preview is a protected invitation (:242).
    def protected_permission_preview(canonical_role)
      PROTECTED.select { |_, roles| roles.include?(canonical_role) }.keys.sort.freeze
    end

    def protected_role?(canonical_role) = protected_permission_preview(canonical_role).any?

    # Does this Role Assignment's approved allowlist carry `capability`? Required
    # in addition to the baseline allow when the baseline cell reads "protected
    # explicit grant" (:314 "sorted explicit protected-permission allowlist").
    def protected_grant?(capability, allowlist)
      PROTECTED.key?(capability) && Array(allowlist).include?(capability)
    end

    def known?(capability) = CAPABILITIES.key?(capability)

    # Does the baseline allow `capability` to an actor holding any of `roles`?
    def permits?(capability, roles)
      allowed = CAPABILITIES.fetch(capability) do
        raise Platform::InvariantViolation, "unmapped Permission Baseline capability #{capability.inspect}"
      end
      roles.any? { |role| allowed.include?(role) }
    end

    # THE SIXTH COLUMN OF THE SAME ROW, WHICH `CAPABILITIES` CANNOT EXPRESS (R3-10).
    #
    # :135's table has SEVEN cells per row, one per column heading, and the sixth is
    # **Read-Only Executive Buyer**. `CAPABILITIES` above is keyed by `canonical_role`
    # alone, and a Read-Only Executive Buyer is NOT a canonical role: :314 defines it as
    # the tuple `canonical_role = MarketingOperator`, `permission_mode = read_only`,
    # `persona = executive_buyer` (`Platform::BaselineContent::ALLOWED_ROLE_MODE_PERSONA`,
    # `Workflows::Wf013::InvitationOffer#valid_tuple?`). So transcribing only the ALLOW
    # cells of a row silently mapped that actor onto MarketingOperator's cell and granted
    # it everything a MarketingOperator may do — including `crawl.cancel`, whose own cell
    # for this column reads `deny`, and whose effect is IRREVERSIBLE because
    # `f1_crawls_guard` refuses every edge out of a terminal state.
    #
    # THE TABLE DECIDES THIS, NOT A JUDGEMENT. Every capability `CAPABILITIES`
    # materializes is a WRITE capability whose Read-Only Executive Buyer cell reads
    # exactly `deny` — all SIXTEEN of them, verified against the ratified table. (An
    # earlier note said "fourteen" and cited `:137-:151`; both were wrong. The count
    # missed `source.verify` and `policy.source_scope.manage`, and three of the sixteen
    # sit at :170, :172 and :173, outside the cited span. The CONCLUSION was unaffected —
    # every one of the sixteen denies — and `permission_baseline_transcription_spec`
    # derives its subject from `CAPABILITIES.keys`, so the check was already covering all
    # sixteen while the prose undercounted them.) The cells that column
    # ALLOWS (`organization.read`, `project.read`, `source.read`, `crawl.read`,
    # `evaluation.read`, `notification.inbox.read`, the `issue`/`score`/`history`/
    # `recommendation` reads, `session.terminate` for the actor's own Session, and
    # `export.list`/`export.create`/`export.retrieve` as summary-only) are READ
    # capabilities, and this build materializes none of them. So the ratified answer for
    # every capability that exists here today is `deny`, and this set is EMPTY BY
    # TRANSCRIPTION rather than by omission.
    #
    # It is a set rather than a boolean precisely so the next materialized capability is
    # a data addition: a read capability the column allows is added here, and the
    # evaluator's semantics do not change. An empty allow-set that is CONSULTED is a
    # control; an unconsulted one is what R3-10 found.
    #
    # SCOPE, STATED SO IT IS NOT READ WIDER. This closes the `permission_mode` limb of
    # FU-1 for every capability the baseline materializes. It does NOT touch FU-2, the
    # assignment-scope (GrantScope) containment limb, which remains open and is a
    # different dimension of the same row.
    READ_ONLY_MODE = "read_only"
    # The sixth column, now that this build materializes read capabilities. :154 and :155
    # both read `allow for own Organization`/`allow` for the Read-Only Executive Buyer,
    # so a `read_only` assignment confers exactly these and nothing else — which is what
    # makes the mode meaningful rather than decorative: the same MarketingOperator row
    # that allows `project.create` in `standard` confers none of it in `read_only`.
    READ_ONLY_CAPABILITIES = %w[organization.read project.read source.read crawl.read].freeze

    # Does an assignment held in `permission_mode` confer `capability`? Any mode other
    # than `read_only` is unconstrained by this dimension and answers to the role cell
    # alone, which is what `standard` means in :314.
    def mode_permits?(capability, permission_mode)
      return true unless permission_mode.to_s == READ_ONLY_MODE

      READ_ONLY_CAPABILITIES.include?(capability)
    end

    # THE WHOLE BASELINE ROW FOR ONE ASSIGNMENT: the role cell AND the mode cell (FU-62).
    #
    # WHY THIS EXISTS AS ONE METHOD. `permits?` reads the role cell and `mode_permits?` reads the
    # sixth column, and answering the real question needs BOTH. Five call sites wrote the conjunction
    # out by hand and agreed; the sixth — `Wf013::Handlers::ReactivateOrganization` — applied the role
    # limb ALONE, on a role list flattened out of the assignments so the mode could not be recovered
    # even if someone had wanted it. That is R3-10's exact shape surviving outside the class R3-10
    # repaired: an authorization control implemented once properly and once partially, with only the
    # caller set keeping the partial one safe.
    #
    # AND THE CALLER SET WAS NOT KEEPING IT SAFE. The record said the gap was unreachable because
    # `OrganizationAdmin` + `read_only` is not a ratified tuple. MEASURED 2026-08-10: the tuple is
    # barred by `Wf013::InvitationOffer#valid_tuple?` and BY NOTHING IN THE DATABASE —
    # `role_assignments_permission_mode_check` constrains the mode's domain and never its pairing
    # with a role — so the row inserts, and a `read_only` OrganizationAdmin holding a valid
    # reactivation receipt REACTIVATED A SUSPENDED ORGANIZATION. `organization.reactivate` is not in
    # `READ_ONLY_CAPABILITIES`, so the mode cell denies it outright.
    #
    # THE CENSUS ABOVE READ "at the three creation paths" AND WAS WRONG, WHICH IS THE SAME DEFECT ONE
    # LEVEL UP (corrected 2026-08-11 while taking FU-76). `valid_tuple?` has TWO production callers,
    # `wf013/handlers/create_invitation.rb:48` and `wf013/handlers/request_role_assignment.rb:38`.
    # The paths that create a grant WITHOUT calling it are the ones that mattered: WF-001's genesis
    # writes its OrganizationAdmin directly, and `Wf001::Handlers::AcceptInvitation` copies
    # `canonical_role`, `permission_mode` and `persona` STRAIGHT OUT OF THE INVITATION ROW and
    # re-validates none of them. A miscounted caller set is exactly what "only the caller set keeping
    # it safe" cannot survive.
    #
    # THE DATABASE LIMB IS NOW CLOSED (FU-76, migration 20260810120000).
    # `role_assignments_ratified_role_mode_persona` and `invitations_ratified_role_mode_persona`
    # admit exactly `BaselineContent::ALLOWED_ROLE_MODE_PERSONA`, on both tables because the two are
    # chained through acceptance. This paragraph's "BY NOTHING IN THE DATABASE" is the state that
    # was measured, and it is kept as the record of what was reachable, not as current fact.
    #
    # A conjunction spelled out at six call sites is six chances to spell five of it. This is one.
    def assignment_permits?(capability, assignment)
      permits?(capability, [assignment["canonical_role"]]) &&
        mode_permits?(capability, assignment["permission_mode"])
    end
  end
end
