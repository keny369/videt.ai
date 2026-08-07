# frozen_string_literal: true

module App
  # WEB-014 `/app/projects/:project_id/sources` and its registration form
  # (FRONTEND_ARCHITECTURE.md :65): QRY-004 SourceCollection plus the WF-004
  # RegisterSource and ActivateSource commands.
  #
  # Registration only PROPOSES a Source. It never verifies, activates or crawls, and this
  # screen does not pretend otherwise: a newly registered Source shows as `proposed`, and
  # the activation control appears only once a Source has been verified. Rendering an
  # "activate" button on a proposed Source would offer an action WF-004 refuses. A
  # proposed Source instead links to the WF-003 verification surface, which is the only
  # route from `proposed` to `verified`.
  #
  # Reads go through Platform::AuthenticatedRequest, which owns their transaction. Writes
  # do not: a WF-004 handler opens the sole unit of work itself and authenticates the
  # Session inside it, so the controller only locates the candidate Session id.
  class SourcesController < ApplicationController
    def index
      outcome = authorize!("source.read", resource: { type: "project", id: params[:project_id] }) do |actor, conn|
        store = IdentityAccess::Infrastructure::TenantReadStore.new(conn.raw_connection)
        project = store.project(organization_id: actor.organization_id, project_id: params[:project_id])
        next nil if project.nil?

        { project:, sources: store.sources(organization_id: actor.organization_id,
                                           project_id: params[:project_id]) }
      end
      return if outcome.nil?
      # A Project outside the proved Organization context reads as absent, which is the
      # correct disclosure: it does not distinguish "no such Project" from "not yours".
      return render("shared/not_found", status: :not_found) if outcome.value.nil?

      @project = outcome.value[:project]
      @sources = outcome.value[:sources]
      @can_register = permitted?(outcome, "source.register")
      @can_manage = permitted?(outcome, "source.lifecycle.manage")
      # `source.verify` is a separate grant from reading the collection: a Marketing
      # Operator may register and activate Sources but may not verify one.
      @can_verify = permitted?(outcome, "source.verify")
    end

    def new
      outcome = authorize!("source.register", resource: { type: "project", id: params[:project_id] })
      return if outcome.nil?

      @project_id = params[:project_id]
      @submitted_root_uri = ""
    end

    def create
      @project_id = params[:project_id]
      @submitted_root_uri = params[:submitted_root_uri].to_s.strip

      gate = authorize!("source.register", resource: { type: "project", id: @project_id })
      return if gate.nil?

      result = submit_register(gate.actor.organization_id)
      if result&.success?
        redirect_to app_project_sources_path(@project_id), status: :see_other,
                    notice: "Source registered. It is proposed until ownership is verified."
      else
        @error = registration_error(result)
        render :new, status: :unprocessable_content
      end
    end

    def activate
      gate = authorize!("source.lifecycle.manage", resource: { type: "source", id: params[:id] })
      return if gate.nil?

      result = submit_activate(gate.actor.organization_id, params[:project_id], params[:id])
      if result&.success?
        redirect_to app_project_sources_path(params[:project_id]), status: :see_other,
                    notice: "Source activated."
      else
        redirect_to app_project_sources_path(params[:project_id]), status: :see_other,
                    alert: "That source could not be activated (#{result&.reason_code || "unauthenticated"})."
      end
    end

    private

    def submit_register(organization_id)
      session_id = Platform::SessionLocator.resolve(session_token)
      return nil if session_id.nil?

      project = read_project(@project_id)
      return nil if project.nil?

      command = Workflows::Wf004::Commands::RegisterSource.new(
        command_id: SecureRandom.uuid_v7, idempotency_key: SecureRandom.uuid_v7, schema_version: "1.0",
        session_id:, organization_id:, project_id: @project_id,
        registration_schema_version: Workflows::Wf004::SourceRegistration::REGISTRATION_SCHEMA_VERSION,
        submitted_root_uri: @submitted_root_uri,
        # From the row this screen rendered: if the Project moved in between, the command
        # refuses as stale rather than registering against a Project that has changed.
        expected_state_version: project["state_version"].to_i,
        requested_at_utc: Time.now.utc
      )
      Workflows::Wf004::Handlers::RegisterSource.new.call(command:, request_context: actor_context)
    end

    def submit_activate(organization_id, project_id, source_id)
      session_id = Platform::SessionLocator.resolve(session_token)
      return nil if session_id.nil?

      source = read_source(project_id, source_id)
      return nil if source.nil?

      command = Workflows::Wf004::Commands::ActivateSource.new(
        command_id: SecureRandom.uuid_v7, idempotency_key: SecureRandom.uuid_v7, schema_version: "1.0",
        session_id:, organization_id:, project_id:, source_id:,
        expected_state_version: source["state_version"].to_i, requested_at_utc: Time.now.utc
      )
      Workflows::Wf004::Handlers::ActivateSource.new.call(command:, request_context: actor_context)
    end

    def read_project(project_id)
      authorize!("project.read", resource: { type: "project", id: project_id }) do |actor, conn|
        conn.raw_connection.exec_params(
          "SELECT state_version FROM projects WHERE organization_id = $1::uuid AND id = $2::uuid",
          [actor.organization_id, project_id]
        ).to_a.first
      end&.value
    end

    def read_source(project_id, source_id)
      authorize!("source.read", resource: { type: "source", id: source_id }) do |actor, conn|
        conn.raw_connection.exec_params(<<~SQL, [actor.organization_id, project_id, source_id]).to_a.first
          SELECT state_version FROM sources
          WHERE organization_id = $1::uuid AND project_id = $2::uuid AND id = $3::uuid
        SQL
      end&.value
    end

    # The workflow's own reason code, never one invented here. APPLICATION_LAYER.md :98
    # forbids a controller rescuing its way to a reason of its own.
    def registration_error(result)
      return "Sign in again to continue." if result.nil?

      Sources::REASONS.fetch(result.reason_code, nil) ||
        "That source could not be registered (#{result.reason_code})."
    end

    def actor_context = Platform::RequestContext.for_actor(correlation_id: correlation_id)

    def permitted?(outcome, capability)
      outcome.decision.granting.any? do |assignment|
        Platform::PermissionBaseline.permits?(capability, [assignment["canonical_role"]]) &&
          Platform::PermissionBaseline.mode_permits?(capability, assignment["permission_mode"])
      end
    end
  end

  # Deterministic human-authored text for the reason codes registration can produce.
  module Sources
    REASONS = {
      "source_uri_malformed" => "Enter a complete address, for example https://example.com.",
      "source_uri_scheme_unsupported" => "Only HTTPS addresses can be registered.",
      "source_host_invalid" => "That address does not have a valid host name.",
      "source_already_registered" => "That address is already registered to this project.",
      "stale_state_version" => "This project changed while the form was open. Try again.",
      "project_not_active" => "Activate the project before registering sources."
    }.freeze
  end
end
