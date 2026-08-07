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
  # only after WF-003 ownership verification and then WF-004 activation.
  class CrawlsController < ApplicationController
    def index
      outcome = authorize!("crawl.read", resource: { type: "project", id: params[:project_id] }) do |actor, conn|
        store = IdentityAccess::Infrastructure::TenantReadStore.new(conn.raw_connection)
        project = store.project(organization_id: actor.organization_id, project_id: params[:project_id])
        next nil if project.nil?

        { project:,
          crawls: store.crawls(organization_id: actor.organization_id, project_id: params[:project_id]),
          sources: store.sources(organization_id: actor.organization_id, project_id: params[:project_id]),
          evaluation_in_flight: store.initial_evaluation_in_flight?(organization_id: actor.organization_id,
                                                                    project_id: params[:project_id]) }
      end
      return if outcome.nil?
      return render("shared/not_found", status: :not_found) if outcome.value.nil?

      @project = outcome.value[:project]
      @crawls = outcome.value[:crawls]
      # Computed from the same rows WF-005 will evaluate, so the screen explains the same
      # refusal the command would give rather than a guess at it.
      @active_sources = outcome.value[:sources].count { |s| s["state"] == "active" }
      @project_active = @project["state"] == "active"
      # The OD-018 guard. It is stated here for the same reason as the other two, and it
      # deserves its own sentence: a first Crawl opens an `initial` Evaluation, and the
      # workflow that would resolve that Evaluation is a later slice, so today the first
      # Crawl of a Project is currently its only one. Saying so is the honest screen; a
      # button that always refuses is not.
      @evaluation_in_flight = outcome.value[:evaluation_in_flight]
      @can_trigger = permitted?(outcome, "crawl.trigger")
    end

    # WEB-017 QRY-023 CrawlDetail: "Crawl, Source/URL outcome and stage summary
    # projection", under the same `crawl.read` authority as the collection.
    #
    # The collection can only say a run failed. This says WHY, in the run's own
    # vocabulary: the Sources it was pinned to, every fetch it made with its outcome and
    # reason code, the per-URL terminal decisions and their effect on coverage, and the
    # Documents it produced. A run that produced nothing is the case worth explaining, so
    # each empty section says what its emptiness means rather than rendering blank.
    def show
      outcome = authorize!("crawl.read", resource: { type: "crawl", id: params[:id] }) do |actor, conn|
        read_detail(actor, conn)
      end
      return if outcome.nil?
      return render("shared/not_found", status: :not_found) if outcome.value.nil?

      @project = outcome.value[:project]
      @crawl = outcome.value[:crawl]
      @evaluation = outcome.value[:evaluation]
      @sources = outcome.value[:sources]
      @fetch_attempts = outcome.value[:fetch_attempts]
      @terminal_outcomes = outcome.value[:terminal_outcomes]
      @documents = outcome.value[:documents]
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

    def read_detail(actor, conn)
      store = IdentityAccess::Infrastructure::TenantReadStore.new(conn.raw_connection)
      org = actor.organization_id
      project = store.project(organization_id: org, project_id: params[:project_id])
      crawl = store.crawl(organization_id: org, project_id: params[:project_id], crawl_id: params[:id])
      return nil if project.nil? || crawl.nil?

      { project:, crawl:,
        evaluation: store.crawl_evaluation(organization_id: org, crawl_id: params[:id]),
        sources: store.crawl_sources(organization_id: org, crawl_id: params[:id]),
        fetch_attempts: store.fetch_attempts(organization_id: org, crawl_id: params[:id]),
        terminal_outcomes: store.crawl_terminal_outcomes(organization_id: org, crawl_id: params[:id]),
        documents: store.crawl_documents(organization_id: org, crawl_id: params[:id]) }
    end

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
    # The Evaluation reason codes this build can produce, as a sentence. There is exactly
    # one today, and it is not a fault in the crawled site: the WF-006 input gate derives
    # `blocked` because no parser policy can be resolved and no Parsed Artifact can
    # succeed, so the honest sentence names the missing capability rather than implying
    # the source failed.
    EVALUATION_REASONS = {
      "evaluation_inputs_unavailable" =>
        "The crawl's documents could not be turned into evaluation inputs, because content " \
        "analysis is not part of this build yet. Nothing is wrong with the source."
    }.freeze

    REASONS = {
      "crawl_project_not_active" => "Activate the project before crawling it.",
      "crawl_no_active_source" => "This project has no active source. Verify and activate a source first.",
      # WF-005 admits one root crawl per project until its evaluation resolves. A person
      # pressing the button twice deserves that sentence, not the reason code.
      "initial_evaluation_already_running" => "This project already has a crawl in flight. Wait for it to finish.",
      "crawl_trigger_unauthorized" => "You do not have permission to start crawls.",
      "crawl_entitlement_unavailable" => "Your plan's crawl allowance could not be reserved.",
      "entitlement_denied" => "Your plan's crawl allowance is exhausted."
    }.freeze
  end
end
