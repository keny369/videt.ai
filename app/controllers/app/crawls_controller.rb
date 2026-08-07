# frozen_string_literal: true

module App
  # WEB-016 `/app/projects/:project_id/crawls` (FRONTEND_ARCHITECTURE.md :67): QRY-022
  # CrawlCollection, plus the WF-005 QueueCrawl trigger.
  #
  # ":67 `crawl.trigger` is never inferred as read authority" — reading the collection and
  # triggering a crawl are separate grants, checked separately.
  #
  # WF-005 refuses a crawl unless the Project is active AND it has at least one active
  # Source (`crawl_project_not_active`, `crawl_no_active_source`). This screen states that
  # prerequisite rather than offering a button that always fails: a Source reaches `active`
  # only after WF-003 ownership verification, which has no screen yet.
  class CrawlsController < ApplicationController
    def index
      outcome = authorize!("crawl.read", resource: { type: "project", id: params[:project_id] }) do |actor, conn|
        store = IdentityAccess::Infrastructure::TenantReadStore.new(conn.raw_connection)
        project = store.project(organization_id: actor.organization_id, project_id: params[:project_id])
        next nil if project.nil?

        { project:,
          crawls: store.crawls(organization_id: actor.organization_id, project_id: params[:project_id]),
          sources: store.sources(organization_id: actor.organization_id, project_id: params[:project_id]) }
      end
      return if outcome.nil?
      return render("shared/not_found", status: :not_found) if outcome.value.nil?

      @project = outcome.value[:project]
      @crawls = outcome.value[:crawls]
      # Computed from the same rows WF-005 will evaluate, so the screen explains the same
      # refusal the command would give rather than a guess at it.
      @active_sources = outcome.value[:sources].count { |s| s["state"] == "active" }
      @project_active = @project["state"] == "active"
      @can_trigger = permitted?(outcome, "crawl.trigger")
    end

    def create
      gate = authorize!("crawl.trigger", resource: { type: "project", id: params[:project_id] })
      return if gate.nil?

      result = submit_queue(gate.actor.organization_id, params[:project_id])
      if result&.success?
        redirect_to app_project_crawls_path(params[:project_id]), status: :see_other,
                    notice: "Crawl queued."
      else
        redirect_to app_project_crawls_path(params[:project_id]), status: :see_other,
                    alert: trigger_error(result)
      end
    end

    private

    def submit_queue(organization_id, project_id)
      session_id = Platform::SessionLocator.resolve(session_token)
      return nil if session_id.nil?

      command = Workflows::Wf005::Commands::QueueCrawl.new(
        command_id: SecureRandom.uuid_v7, idempotency_key: SecureRandom.uuid_v7, schema_version: "1.0",
        session_id:, organization_id:, project_id:, requested_at_utc: Time.now.utc
      )
      Workflows::Wf005::Handlers::QueueCrawl.new.call(command:, request_context: actor_context)
    end

    def trigger_error(result)
      return "Sign in again to continue." if result.nil?

      Crawls::REASONS.fetch(result.reason_code, nil) ||
        "That crawl could not be queued (#{result.reason_code})."
    end

    def actor_context = Platform::RequestContext.for_actor(correlation_id: correlation_id)

    def permitted?(outcome, capability)
      outcome.decision.granting.any? do |assignment|
        Platform::PermissionBaseline.permits?(capability, [assignment["canonical_role"]]) &&
          Platform::PermissionBaseline.mode_permits?(capability, assignment["permission_mode"])
      end
    end
  end

  module Crawls
    REASONS = {
      "crawl_project_not_active" => "Activate the project before crawling it.",
      "crawl_no_active_source" => "This project has no active source. Verify and activate a source first.",
      "entitlement_denied" => "Your plan's crawl allowance is exhausted."
    }.freeze
  end
end
