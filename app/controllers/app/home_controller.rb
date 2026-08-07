# frozen_string_literal: true

module App
  # WEB-010 `/app` (FRONTEND_ARCHITECTURE.md :61): the Session-bound logical destination
  # shell, materializing QRY-001 OrganizationHome.
  #
  # ":61 logical destination shell only; no unnamed Organization/Project/notice
  # disclosure." This screen renders the Organization the Session proved and the acting
  # Account, and nothing else. The Project list is NOT here even though it would be
  # convenient: `project.read` is a separate grant and ":123 is never implied by holding
  # a companion mutation permission", so Projects live behind their own screen and their
  # own authorization.
  class HomeController < ApplicationController
    def show
      outcome = authorize!("organization.read") do |actor, conn|
        store = IdentityAccess::Infrastructure::TenantReadStore.new(conn.raw_connection)
        { organization: store.organization_home(actor.organization_id),
          account: store.account(actor.account_id) }
      end
      return if outcome.nil?

      @organization = outcome.value[:organization]
      @account = outcome.value[:account]
      # Navigation visibility is convenience, never authority (:127). A hidden link does
      # not prove denial and a visible one does not grant anything: the Projects screen
      # authorizes `project.read` for itself on every request.
      @can_read_projects = permitted?(outcome, "project.read")
    end

    private

    # Whether to render a navigation link. Computed from the same decision facts the
    # target request will use, but it substitutes for nothing: the target reauthorizes.
    def permitted?(outcome, capability)
      outcome.decision.granting.any? do |assignment|
        Platform::PermissionBaseline.permits?(capability, [assignment["canonical_role"]]) &&
          Platform::PermissionBaseline.mode_permits?(capability, assignment["permission_mode"])
      end
    end
  end
end
