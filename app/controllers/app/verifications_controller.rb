# frozen_string_literal: true

module App
  # `/app/projects/:project_id/sources/:source_id/verification` — the WF-003 ownership
  # verification surface: QRY-021 PendingVerificationChallenge plus the
  # `IssueVerificationChallenge` and `ReserveVerificationAttempt` commands and the
  # `CompleteVerificationAttempt` observation they exist to reach.
  #
  # FRONTEND_ARCHITECTURE.md's screen table names no row for this. Its nearest neighbour
  # is WEB-015 `/app/projects/:project_id/sources/:id` (QRY-005 SourceDetail), which is
  # the Source's own detail screen and a different query; the verification contract lives
  # in API_CONTRACTS.md :266-268 and :585 instead. So this route sits inside the WEB-015
  # Source family without claiming to be it, and its authority is QRY-021's own:
  # `source.verify`, not a Source read permission.
  #
  # This is the screen that turns a `proposed` Source into a `verified` one, which is
  # the only door to activation and therefore to crawling. Before it existed the whole
  # chain — register, verify, activate, crawl — stopped at the first step with the
  # backend fully built and unreachable.
  #
  # THREE THINGS DESERVE EXPLANATION.
  #
  # 1. The idempotency key is DERIVED, not random. `IssueVerificationChallenge` is
  #    idempotent per (Source, key), and an exact replay by the original actor is the
  #    ratified way to redeliver the plaintext challenge (S-05.json idempotency;
  #    ADR-024 DEF-1 — retrieval is QRY-021, redelivery is the replay). A random key
  #    would make the token unrecoverable the moment the page was reloaded, so the key
  #    is a function of the Source and the chosen method. Pressing "Issue" twice
  #    replays rather than opening a second Request, and reloading the screen
  #    redelivers the same value.
  #
  # 2. `show` runs a command. QRY-021's own route returns `challenge_token` for a
  #    pending Request, and the read model deliberately cannot: the token is not a
  #    column, only an F-02 ciphertext reference is, and revealing it is an audited
  #    disclosure. So the screen reads its metadata from the read store and obtains the
  #    value through the authorized redelivery replay, which appends the restricted
  #    access log the contract requires and changes no domain state.
  #
  # 3. `observe` completes what it reserves. The API contract answers the on-demand
  #    route 202, and the reservation and the observation are separate commands, but
  #    the accepted baseline has no on-demand ScheduledAction kind — the closed
  #    catalogue has `verification_observation_slot` for the automated schedule only.
  #    "On-demand observation executes under its reserved attempt" (S-05.json
  #    background_job), so the reserved attempt is completed in the same request.
  #    `CompleteVerificationAttempt` does its own phasing internally: it reveals inside
  #    a transaction, calls the provider with NO transaction held, and commits the
  #    outcome in a second one. Nothing here holds a transaction across the network.
  class VerificationsController < ApplicationController
    # The observation is service-executed work: authority was established when the
    # Request was created and again when this actor's on-demand attempt was accepted,
    # so the completion carries a service identity and no actor (MTX-051). The
    # ScheduledAction executor is the platform's verification-observing identity —
    # the same one the automated slots run the identical command under.
    OBSERVER_IDENTITY = Platform::ServiceIdentity::SCHEDULED_ACTION_EXECUTOR

    METHODS = %w[dns_txt http_file].freeze
    DEFAULT_METHOD = "dns_txt"

    def show
      outcome = authorize!("source.verify", resource: { type: "source", id: params[:source_id] }) do |actor, conn|
        read_screen(actor, conn)
      end
      return if outcome.nil?
      # A Project or Source outside the proved Organization context reads as absent,
      # which does not distinguish "no such Source" from "not yours".
      return render("shared/not_found", status: :not_found) if outcome.value.nil?

      assign_screen(outcome.value)
      # Only a pending Request has challenge material, and only then is a redelivery
      # meaningful. A terminal Request's material has been cryptographically destroyed.
      redeliver_challenge if @request && @request["request_status"] == "pending"
    end

    def create
      @verification_method = params[:verification_method].presence || DEFAULT_METHOD
      gate = authorize!("source.verify", resource: { type: "source", id: params[:source_id] })
      return if gate.nil?
      unless METHODS.include?(@verification_method)
        return redirect_to(verification_path, status: :see_other, alert: "Choose DNS or an HTTPS file.")
      end

      result = submit_issue(gate.actor.organization_id, @verification_method)
      if result&.success?
        redirect_to verification_path, status: :see_other,
                    notice: "Ownership challenge issued. Publish the value below, then check it."
      else
        redirect_to verification_path, status: :see_other, alert: message_for(result, "issued")
      end
    end

    # Reserve one on-demand attempt and run it. The two commands are separate on
    # purpose: the reservation is the authorized, counted, rate-limited act, and the
    # observation is what the reserved slot then does.
    def observe
      gate = authorize!("source.verify", resource: { type: "source", id: params[:source_id] })
      return if gate.nil?

      reserved = submit_reserve(gate.actor.organization_id)
      unless reserved&.success?
        return redirect_to(verification_path, status: :see_other, alert: message_for(reserved, "checked"))
      end

      observed = submit_complete(gate.actor.organization_id, reserved.payload)
      redirect_to verification_path, status: :see_other, **observation_flash(observed)
    end

    # DEVELOPMENT ONLY. Writes the value the developer would otherwise publish in DNS
    # or at the well-known URL into the local fixture the development observer reads.
    # It does not verify anything: the next check runs the real predicate over what
    # this wrote, so a broken value still fails. `Platform::DevelopmentVerificationOutbound`
    # refuses outside an opted-in development process, and this action refuses with it.
    def place_record
      unless Platform::DevelopmentVerificationOutbound.enabled?
        return render("shared/not_found", status: :not_found)
      end

      outcome = authorize!("source.verify", resource: { type: "source", id: params[:source_id] }) do |actor, conn|
        read_screen(actor, conn)
      end
      return if outcome.nil?
      return render("shared/not_found", status: :not_found) if outcome.value.nil?

      assign_screen(outcome.value)
      redeliver_challenge if @request && @request["request_status"] == "pending"
      return redirect_to(verification_path, status: :see_other, alert: "There is no pending challenge to publish.") if @required_value.nil?

      path = Platform::DevelopmentVerificationOutbound.place(
        canonical_host: @source["canonical_host"], value: @required_value
      )
      redirect_to verification_path, status: :see_other,
                  notice: "Development record written to #{path.relative_path_from(Rails.root)}. Now check it."
    end

    private

    def verification_path = app_project_source_verification_path(params[:project_id], params[:source_id])

    # ---- reads ---------------------------------------------------------------

    def read_screen(actor, conn)
      store = IdentityAccess::Infrastructure::TenantReadStore.new(conn.raw_connection)
      project = store.project(organization_id: actor.organization_id, project_id: params[:project_id])
      source = store.source(organization_id: actor.organization_id, project_id: params[:project_id],
                            source_id: params[:source_id])
      return nil if project.nil? || source.nil?

      request = store.verification_request(organization_id: actor.organization_id, source_id: params[:source_id])
      attempts = if request
                   store.verification_attempts(organization_id: actor.organization_id,
                                               verification_request_id: request["id"])
      else
                   []
      end
      { organization_id: actor.organization_id, project:, source:, request:, attempts: }
    end

    def assign_screen(value)
      @organization_id = value[:organization_id]
      @project = value[:project]
      @source = value[:source]
      @request = value[:request]
      @attempts = value[:attempts]
      @methods = METHODS
      @dev_records = Platform::DevelopmentVerificationOutbound.enabled?
    end

    # The authorized redelivery: an exact replay of the issuing command, which returns
    # the same plaintext token and appends a restricted access log. A failure here is
    # not fatal to the screen — the metadata still renders and the view says the value
    # cannot be shown, which is the honest reading of `challenge_redelivery_unavailable`.
    def redeliver_challenge
      result = submit_issue(@organization_id, @request["method"], expected_state_version: @source["state_version"].to_i)
      return unless result&.success? && result.payload[:challenge_token]

      @challenge_token = result.payload[:challenge_token]
      # ASCII by construction (the token is unpadded base64url), re-tagged so the view
      # renders it as text rather than as the raw bytes the predicate compares.
      @required_value = Workflows::Wf003::VerificationObservation.expected_value(@challenge_token)
                                                                .dup.force_encoding("UTF-8")
      @observation_location = observation_location(@request["method"], @request["canonical_host"])
    end

    def observation_location(method, host)
      case method
      when "dns_txt" then Workflows::Wf003::VerificationObservation.dns_location(host)
      when "http_file" then Workflows::Wf003::VerificationObservation.http_url(host)
      end
    end

    # ---- commands ------------------------------------------------------------

    def submit_issue(organization_id, verification_method, expected_state_version: nil)
      session_id = Platform::SessionLocator.resolve(session_token)
      return nil if session_id.nil?

      # From the row this screen read: if the Source moved in between, the command
      # refuses as stale rather than issuing against a Source that has changed.
      expected_state_version ||= read_source_version&.fetch("state_version")&.to_i
      return nil if expected_state_version.nil?

      command = Workflows::Wf003::Commands::IssueVerificationChallenge.new(
        command_id: SecureRandom.uuid_v7, idempotency_key: issue_key(params[:source_id], verification_method),
        schema_version: "1.0", session_id:, organization_id:, project_id: params[:project_id],
        source_id: params[:source_id], method: verification_method,
        expected_state_version:, requested_at_utc: Time.now.utc
      )
      Workflows::Wf003::Handlers::IssueVerificationChallenge.new.call(command:, request_context: actor_context)
    end

    def submit_reserve(organization_id)
      session_id = Platform::SessionLocator.resolve(session_token)
      return nil if session_id.nil?

      request = read_request_version(organization_id)
      return nil if request.nil?

      command = Workflows::Wf003::Commands::ReserveVerificationAttempt.new(
        command_id: SecureRandom.uuid_v7, idempotency_key: SecureRandom.uuid_v7, schema_version: "1.0",
        session_id:, organization_id:, project_id: params[:project_id],
        verification_request_id: request["id"], expected_state_version: request["state_version"].to_i,
        requested_at_utc: Time.now.utc
      )
      Workflows::Wf003::Handlers::ReserveVerificationAttempt.new.call(command:, request_context: actor_context)
    end

    def submit_complete(organization_id, reserved)
      command = Workflows::Wf003::Commands::CompleteVerificationAttempt.new(
        command_id: SecureRandom.uuid_v7, schema_version: "1.0", organization_id:,
        verification_request_id: reserved[:verification_request_id],
        verification_attempt_id: reserved[:verification_attempt_id], requested_at_utc: Time.now.utc
      )
      Workflows::Wf003::Handlers::CompleteVerificationAttempt.new.call(
        command:, request_context: service_context,
        outbound: Platform::DevelopmentVerificationOutbound.surface
      )
    end

    # Stable per (Source, method), so a reload redelivers rather than reissuing and a
    # double submit cannot open two Requests. Namespaced by the command so the value
    # can never collide with another workflow's idempotency space.
    def issue_key(source_id, verification_method)
      Platform::DerivedUuid.v8(Platform::CanonicalJson.digest({
        "command_type" => Workflows::Wf003::Commands::IssueVerificationChallenge::TYPE,
        "source_id" => source_id, "method" => verification_method
      }))
    end

    def read_source_version
      authorize!("source.verify", resource: { type: "source", id: params[:source_id] }) do |actor, conn|
        conn.raw_connection.exec_params(<<~SQL, [actor.organization_id, params[:project_id], params[:source_id]]).to_a.first
          SELECT state_version FROM sources
          WHERE organization_id = $1::uuid AND project_id = $2::uuid AND id = $3::uuid
        SQL
      end&.value
    end

    def read_request_version(organization_id)
      authorize!("source.verify", resource: { type: "source", id: params[:source_id] }) do |_actor, conn|
        conn.raw_connection.exec_params(<<~SQL, [organization_id, params[:source_id]]).to_a.first
          SELECT id, state_version FROM verification_requests
          WHERE organization_id = $1::uuid AND source_id = $2::uuid AND request_status = 'pending'
          ORDER BY issued_at_utc DESC, id DESC LIMIT 1
        SQL
      end&.value
    end

    def actor_context = Platform::RequestContext.for_actor(correlation_id: correlation_id)

    def service_context
      Platform::RequestContext.for_service(service_identity_id: OBSERVER_IDENTITY, correlation_id: correlation_id)
    end

    # ---- outcome text --------------------------------------------------------

    # The observation's own reason code, never one invented here. A matched observation
    # before expiry has already verified the Source inside the completion transaction.
    def observation_flash(result)
      return { alert: message_for(result, "checked") } unless result&.success?

      payload = result.payload
      if payload[:source_state] == "verified"
        { notice: "Ownership verified. This source can now be activated." }
      else
        { alert: "Not verified yet: #{Verifications::OBSERVATIONS.fetch(payload[:reason_code], payload[:reason_code])}" }
      end
    end

    def message_for(result, verb)
      return "Sign in again to continue." if result.nil?

      Verifications::REASONS.fetch(result.reason_code, nil) ||
        "That verification could not be #{verb} (#{result.reason_code})."
    end
  end

  # Deterministic human-authored text for the reason codes this screen can surface.
  # Each key is a reason the WF-003 commands or the observation engine actually
  # produce; nothing here invents an outcome the workflow cannot return.
  module Verifications
    REASONS = {
      "unsupported_method" => "Choose DNS or an HTTPS file.",
      "verification_in_progress" => "A verification is already open for this source. Check it, or wait for it to expire.",
      "source_not_proposed" => "This source is no longer awaiting verification.",
      "stale_state_version" => "This source changed while the page was open. Reload and try again.",
      "verification_request_not_pending" => "This verification has already finished.",
      "on_demand_limit_reached" => "You have used all ten manual checks for this challenge.",
      "on_demand_observation_in_progress" => "A check is already running. Reload in a moment.",
      "on_demand_rate_limited" => "Manual checks are limited to one every five minutes.",
      "challenge_expired" => "This challenge has expired. Issue a new one.",
      "challenge_redelivery_unavailable" => "The challenge value can no longer be shown for this request.",
      "idempotency_conflict" => "That request conflicts with one already recorded. Reload and try again.",
      "source_verify_unauthorized" => "You do not have permission to verify sources.",
      "tenant_mismatch" => "That source is not available."
    }.freeze

    # The 14 ratified observation reason codes, as a sentence a user can act on.
    OBSERVATIONS = {
      "dns_nxdomain" => "no TXT record was found at that name yet. DNS changes can take a few minutes to publish.",
      "dns_value_mismatch" => "a TXT record exists but none of its values match. Check for a typo or an old record.",
      "dns_timeout" => "the DNS lookup timed out. Try again shortly.",
      "dns_temporary_failure" => "the resolver could not answer. Try again shortly.",
      "http_status_mismatch" => "the file did not return 200 OK.",
      "http_content_mismatch" => "the file was served but its contents do not match.",
      "http_body_too_large" => "the file is larger than 4 KB. It must contain only the value.",
      "http_redirect_rejected" => "the URL redirected. It must be served directly, without a redirect.",
      "http_timeout" => "the request timed out. Try again shortly.",
      "http_rate_limited" => "the host rate-limited the request. Try again shortly.",
      "http_server_error" => "the host returned a server error. Try again shortly.",
      "tls_validation_failed" => "the HTTPS certificate could not be validated.",
      "connection_failure" => "the host could not be reached."
    }.freeze
  end
end
