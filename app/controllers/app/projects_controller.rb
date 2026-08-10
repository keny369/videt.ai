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
    include LocalPresenceForm

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
      outcome = authorize!("project.create") { |actor, conn| organization_display_name(actor, conn) }
      return if outcome.nil?

      @organization_id = outcome.actor.organization_id
      @organization_display_name = outcome.value
      @display_name = ""
      assign_local_presence_form
    end

    def create
      @display_name = params[:display_name].to_s.strip
      assign_local_presence_form

      # The create form is itself permission-gated, so this authorizes before building a
      # command. The handler authorizes again under its own locks; this is not a
      # substitute for that, it is what stops an unauthorized actor reaching the form.
      #
      # The Organization display name is read in the same authorized transaction because
      # :657 fixes the Local Business Profile's business name to exactly that value. The
      # screen must not accept a name for it, and the handler cross-checks what is sent.
      gate = authorize!("project.create") { |actor, conn| organization_display_name(actor, conn) }
      return if gate.nil?

      @organization_id = gate.actor.organization_id
      @organization_display_name = gate.value
      @field_errors = local_presence_field_errors
      return render(:new, status: :unprocessable_content) if @field_errors.any?

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

    # QRY-001 already names the Organization display name as a disclosed field of the
    # authenticated shell, so this discloses nothing new; it reads it on the same
    # authorized connection rather than trusting a value round-tripped through the form.
    def organization_display_name(actor, conn)
      IdentityAccess::Infrastructure::TenantReadStore.new(conn.raw_connection)
                                                     .organization_home(actor.organization_id)
                                                     &.fetch("display_name")
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
        "objective" => creation::OBJECTIVE
      }.merge(local_presence_profile_fields(@organization_display_name))
    end

    def actor_context = Platform::RequestContext.for_actor(correlation_id: correlation_id)

    # Navigation and control visibility only. ":127 Navigation visibility MUST be computed
    # from the same current authorization facade used by the target request, but it never
    # substitutes for target authorization."
    def permitted?(outcome, capability)
      outcome.decision.granting.any? do |assignment|
        Platform::PermissionBaseline.assignment_permits?(capability, assignment)
      end
    end
  end
end
