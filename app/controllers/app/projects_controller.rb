# frozen_string_literal: true

module App
  # WEB-011 `/app/projects` and WEB-012 `/app/projects/new`
  # (FRONTEND_ARCHITECTURE.md :62-63): QRY-002 ProjectCollection plus the WF-002
  # CreateProject and ActivateProject commands.
  #
  # ":62 blocked pending exact Project read authority; create control separately requires
  # `project.create`." Reading the collection and creating a Project are separate grants
  # checked separately: an actor may hold either without the other, and the create form
  # is refused up front rather than after it has been filled in.
  #
  # Reads run through Platform::AuthenticatedRequest, which owns their transaction.
  # Writes do NOT: a WF-002 handler opens the sole unit of work itself (:69) and
  # authenticates the Session inside it, so the controller only locates the candidate
  # Session id and hands the handler a command.
  class ProjectsController < ApplicationController
    def index
      outcome = authorize!("project.read") do |actor, conn|
        IdentityAccess::Infrastructure::TenantReadStore.new(conn.raw_connection)
                                                       .projects(organization_id: actor.organization_id)
      end
      return if outcome.nil?

      @projects = outcome.value
      @organization_id = outcome.actor.organization_id
      @can_create = permitted?(outcome, "project.create")
      @can_activate = permitted?(outcome, "project.activate")
    end

    def new
      outcome = authorize!("project.create")
      return if outcome.nil?

      @organization_id = outcome.actor.organization_id
      @display_name = ""
      @local_presence_reason = ""
    end

    def create
      @display_name = params[:display_name].to_s.strip
      @local_presence_reason = params[:local_presence_reason].to_s.strip

      # The create form is itself permission-gated, so this authorizes before building a
      # command. The handler authorizes again under its own locks; this is not a
      # substitute for that, it is what stops an unauthorized actor reaching the form.
      gate = authorize!("project.create")
      return if gate.nil?

      @organization_id = gate.actor.organization_id
      result = submit_create(gate.actor.organization_id)
      return render(:new, status: :unprocessable_content) if result.nil?

      if result.success?
        redirect_to app_projects_path, status: :see_other,
                    notice: "Project created as a draft. Activate it once it has an active source."
      else
        @error = "That project could not be created (#{result.reason_code})."
        render :new, status: :unprocessable_content
      end
    end

    def activate
      gate = authorize!("project.activate", resource: { type: "project", id: params[:id] })
      return if gate.nil?

      result = submit_activate(gate.actor.organization_id, params[:id])
      if result&.success?
        redirect_to app_projects_path, status: :see_other, notice: "Project activated."
      else
        redirect_to app_projects_path, status: :see_other,
                    alert: "That project could not be activated (#{result&.reason_code || "unauthenticated"})."
      end
    end

    private

    def submit_create(organization_id)
      session_id = Platform::SessionLocator.resolve(session_token)
      return nil if session_id.nil?

      command = Workflows::Wf002::Commands::CreateProject.new(
        command_id: SecureRandom.uuid_v7, idempotency_key: SecureRandom.uuid_v7, schema_version: "1.0",
        session_id:, organization_id:, profile: project_profile, requested_at_utc: Time.now.utc
      )
      Workflows::Wf002::Handlers::CreateProject.new.call(command:, request_context: actor_context)
    end

    def submit_activate(organization_id, project_id)
      session_id = Platform::SessionLocator.resolve(session_token)
      return nil if session_id.nil?

      current = read_project(project_id)
      return nil if current.nil?

      command = Workflows::Wf002::Commands::ActivateProject.new(
        command_id: SecureRandom.uuid_v7, idempotency_key: SecureRandom.uuid_v7, schema_version: "1.0",
        session_id:, organization_id:, project_id:,
        # Both expected versions come from the row this screen actually rendered. A
        # mismatch is a stale-state refusal, which is the correct answer when the Project
        # moved between the page being drawn and the button being pressed.
        expected_state_version: current["state_version"].to_i,
        expected_source_membership_version: current["source_set_version"].to_i,
        requested_at_utc: Time.now.utc
      )
      Workflows::Wf002::Handlers::ActivateProject.new.call(command:, request_context: actor_context)
    end

    def read_project(project_id)
      outcome = authorize!("project.read") do |actor, conn|
        conn.raw_connection.exec_params(
          "SELECT state_version, source_set_version FROM projects WHERE organization_id = $1::uuid AND id = $2::uuid",
          [actor.organization_id, project_id]
        ).to_a.first
      end
      outcome&.value
    end

    # The complete `project-profile-v1` body WF-002 requires. The locale, time zone and
    # objective are fixed by the ratified profile rather than offered as choices, so the
    # form asks only for what the schema leaves open.
    def project_profile
      creation = Workflows::Wf002::ProjectCreation
      {
        "project_profile_schema_version" => creation::PROFILE_SCHEMA_VERSION,
        "display_name" => @display_name,
        "default_locale" => creation::DEFAULT_LOCALE,
        "reporting_time_zone" => creation::REPORTING_TIME_ZONE,
        # This slice creates Projects without a local-presence claim: the branch that
        # asserts one requires a complete local-business-profile body, which has no form
        # yet. Declaring false with a stated reason is the honest half to build first.
        "local_presence_applicable" => false,
        "local_presence_reason" => @local_presence_reason,
        "local_business_profile" => nil,
        "objective" => creation::OBJECTIVE
      }
    end

    def actor_context = Platform::RequestContext.for_actor(correlation_id: correlation_id)

    # Navigation and control visibility only. ":127 Navigation visibility MUST be computed
    # from the same current authorization facade used by the target request, but it never
    # substitutes for target authorization."
    def permitted?(outcome, capability)
      outcome.decision.granting.any? do |assignment|
        Platform::PermissionBaseline.permits?(capability, [assignment["canonical_role"]]) &&
          Platform::PermissionBaseline.mode_permits?(capability, assignment["permission_mode"])
      end
    end
  end
end
