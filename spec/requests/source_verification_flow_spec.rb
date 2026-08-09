# frozen_string_literal: true

require "rails_helper"

# WF-003 ownership verification, driven through HTTP exactly as a browser drives it.
#
# This is the link that was missing. Every WF-003 command existed and was proved in
# isolation, and none of them was reachable: a registered Source stayed `proposed`
# forever, so no Source could be activated, so no Project could be crawled, so the
# product stopped one step after registration. What is proved here is the CHAIN —
# register, issue, publish, check, verify, activate, crawl — through the same routes a
# person uses.
RSpec.describe "Source ownership verification", type: :request do
  # The identity issuer and the WF handlers open their own units of work.
  self.use_transactional_tests = false

  before { integration_session.https! }

  after do
    F1::LocalIdentityIssuer.reset!
    ReceiptMinter.truncate_all
  end

  let(:email) { "founder-#{SecureRandom.hex(4)}@example.com" }
  let(:host) { "shop.example.test" }

  # ---- a local stand-in for the guarded egress -------------------------------
  #
  # Duck-typed exactly as the F-01 façade answers, never an internal transport class.
  # The published value is whatever a test decides the "owner" put in DNS, so the
  # ratified predicate — not the harness — decides whether verification succeeds.
  def publish(value)
    answer = Object.new
    answer.define_singleton_method(:refused?) { value.nil? }
    answer.define_singleton_method(:reason) { :absent }
    answer.define_singleton_method(:records) { value.nil? ? [] : [[value]] }
    surface = Object.new
    surface.define_singleton_method(:fetch_dns_txt) { |*_a, **_k| answer }
    allow(Platform::DevelopmentVerificationOutbound).to receive(:surface).and_return(surface)
  end

  # ---- journey helpers -------------------------------------------------------

  def create_organization(organization: "Acme Discoverability", project: "Acme Website")
    post "/start/bootstrap-grant", params: { email: }
    post "/start/bootstrap-organization",
         params: { organization_display_name: organization, project_display_name: project,
                   **GenesisProjectProfile.form_params }
  end

  def project_id = DbInspector.all("SELECT id FROM projects ORDER BY created_at").first["id"]
  def source_id = DbInspector.all("SELECT id FROM sources ORDER BY registered_at").first["id"]
  def source_state = DbInspector.all("SELECT state FROM sources").first["state"]
  def request_row = DbInspector.all("SELECT * FROM verification_requests").first

  def verification_path(pid = project_id, sid = source_id)
    "/app/projects/#{pid}/sources/#{sid}/verification"
  end

  # Organization genesis and one registered (therefore `proposed`) Source: the exact
  # state a person is in when they first need this screen. The Project is still a draft
  # — WF-002 refuses to activate a Project with no ACTIVE Source, so activation comes
  # after verification, not before it.
  def registered_source
    create_organization
    post "/app/projects/#{project_id}/sources", params: { submitted_root_uri: "https://#{host}" }
    expect(source_state).to eq("proposed")
  end

  # The pending `initial` Evaluation a started Crawl opens, written directly because the
  # workflow that opens it runs in a background process. Only the four columns WF-005's
  # own predicate reads are meaningful here.
  def open_initial_evaluation
    crawl = DbInspector.all("SELECT id, organization_id, project_id FROM crawls").first
    DbInspector.all(<<~SQL, [crawl["organization_id"], crawl["project_id"], crawl["id"]])
      INSERT INTO evaluations (id, created_at, updated_at, correlation_id, organization_id,
                               project_id, crawl_id, kind, state)
      VALUES (gen_random_uuid(), now(), now(), gen_random_uuid(), $1::uuid, $2::uuid, $3::uuid,
              'initial', 'pending')
    SQL
  end

  # The WF-006 input gate as the worker runs it: the same command, built from the same
  # action shape, under the same service identity. Only the transport is skipped.
  def run_evaluation_input_gate(crawl_id, organization_id)
    command = Workflows::Wf006::Commands::SealEvaluationInputs.new(
      command_id: SecureRandom.uuid_v7, schema_version: "1.0", organization_id:,
      target_type: "crawl", crawl_id:, due_at: Time.now.utc,
      action_id: SecureRandom.uuid_v7, action_identity_sha256: SecureRandom.hex(32),
      requested_at_utc: Time.now.utc
    )
    context = Platform::RequestContext.for_service(
      service_identity_id: Platform::ServiceIdentity.scheduled_action_executor,
      correlation_id: SecureRandom.uuid_v7
    )
    Workflows::Wf006::Handlers::SealEvaluationInputs.new.call(command:, request_context: context)
  end

  def issue_challenge(method = "dns_txt")
    post verification_path, params: { verification_method: method }
  end

  # The value the screen tells the owner to publish, read back out of the rendered page
  # rather than out of the database — the database does not have it, which is the point.
  def required_value
    get verification_path
    response.body[/f1-verification=[A-Za-z0-9_-]{43}/]
  end

  describe "the screen before a challenge exists" do
    it "offers to issue one, and names the host being proved" do
      registered_source

      get verification_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Issue an ownership challenge")
      expect(response.body).to include(host)
      # No Request exists, so the screen shows no check history to speak about.
      expect(response.body).not_to include("Checks")
    end

    it "is reachable from the sources screen, which no longer offers a dead end" do
      registered_source

      get "/app/projects/#{project_id}/sources"

      expect(response.body).to include("Verify ownership")
      expect(response.body).to include(verification_path)
    end

    it "says there is nothing to verify once the Source is past `proposed`" do
      registered_source
      issue_challenge
      publish(required_value)
      post "#{verification_path}/observe"
      expect(source_state).to eq("verified")

      get verification_path

      expect(response.body).to include("Nothing to verify")
    end
  end

  describe "issuing a challenge" do
    it "creates exactly one pending Request and shows what to publish" do
      registered_source

      issue_challenge
      expect(response).to redirect_to(verification_path)
      follow_redirect!

      expect(request_row["request_status"]).to eq("pending")
      expect(request_row["method"]).to eq("dns_txt")
      expect(response.body).to include("_f1-verify.#{host}")
      expect(response.body).to match(/f1-verification=[A-Za-z0-9_-]{43}/)
    end

    it "shows the same value again on reload, because the token is not stored anywhere" do
      registered_source
      issue_challenge

      first = required_value
      second = required_value

      expect(first).to be_present
      expect(second).to eq(first)
      # Redelivery is an audited disclosure, not a second copy of the secret.
      expect(DbInspector.all("SELECT id FROM verification_requests").length).to eq(1)
      access = DbInspector.all(
        "SELECT reason_code FROM audit_record_registry WHERE reason_code = 'challenge_redelivered'"
      )
      expect(access.length).to be >= 2
    end

    it "never persists the token in any column of the Request" do
      registered_source
      issue_challenge
      token = required_value.split("=").last

      row = request_row
      expect(token).to be_present
      expect(row.values.map(&:to_s)).to all(satisfy { |v| !v.include?(token) })
    end

    it "issues once when the control is pressed twice" do
      registered_source
      issue_challenge
      issue_challenge

      expect(DbInspector.all("SELECT id FROM verification_requests").length).to eq(1)
    end

    it "refuses a method outside the two ratified ones without creating a Request" do
      registered_source

      issue_challenge("carrier_pigeon")

      expect(response).to redirect_to(verification_path)
      expect(DbInspector.all("SELECT id FROM verification_requests")).to be_empty
    end

    it "schedules the ten automated observation slots and the expiry alongside it" do
      registered_source
      issue_challenge

      kinds = DbInspector.all("SELECT action_kind, count(*) AS n FROM scheduled_actions GROUP BY action_kind")
                         .to_h { |r| [r["action_kind"], r["n"].to_i] }
      expect(kinds["verification_observation_slot"]).to eq(10)
      expect(kinds["verification_request_expire"]).to eq(1)
    end
  end

  describe "checking the challenge" do
    it "verifies the Source when the published value matches" do
      registered_source
      issue_challenge
      publish(required_value)

      post "#{verification_path}/observe"

      expect(response).to redirect_to(verification_path)
      follow_redirect!
      expect(response.body).to include("Ownership verified")
      expect(source_state).to eq("verified")
      expect(request_row["request_status"]).to eq("verified")
    end

    it "records the observation as restricted Evidence and emits the two events" do
      registered_source
      issue_challenge
      publish(required_value)

      post "#{verification_path}/observe"

      evidence = DbInspector.all("SELECT evidence_type, data_classification FROM evidence")
      expect(evidence.map { |e| e["evidence_type"] }).to include("verification_observation")
      expect(evidence.map { |e| e["data_classification"] }).to all(eq("restricted"))

      events = DbInspector.all("SELECT event_type FROM event_registry").map { |e| e["event_type"] }
      expect(events).to include("SourceVerificationRequested", "SourceVerificationObserved", "SourceVerified")
    end

    it "materializes the interim source scope policy in the same commit" do
      registered_source
      issue_challenge
      publish(required_value)

      post "#{verification_path}/observe"

      policy = DbInspector.all("SELECT policy_version, canonical_host FROM source_scope_policies").first
      expect(policy["policy_version"]).to eq("source-scope-interim-v1")
      expect(policy["canonical_host"]).to eq(host)
    end

    it "leaves the Source proposed and explains why when the value is wrong" do
      registered_source
      issue_challenge
      publish("f1-verification=not-the-right-value")

      post "#{verification_path}/observe"
      follow_redirect!

      expect(source_state).to eq("proposed")
      expect(request_row["request_status"]).to eq("pending")
      expect(response.body).to include("none of its values match")
      # The failed check is recorded, not silently discarded.
      expect(response.body).to include("dns_value_mismatch")
    end

    it "leaves the Source proposed when nothing has been published at all" do
      registered_source
      issue_challenge
      publish(nil)

      post "#{verification_path}/observe"
      follow_redirect!

      expect(source_state).to eq("proposed")
      expect(response.body).to include("no TXT record was found")
    end

    it "rate-limits a second manual check rather than running it" do
      registered_source
      issue_challenge
      publish("f1-verification=not-the-right-value")
      post "#{verification_path}/observe"

      post "#{verification_path}/observe"
      follow_redirect!

      expect(response.body).to include("one every five minutes")
      expect(DbInspector.all("SELECT id FROM verification_attempts").length).to eq(1)
    end

    it "refuses to check when no challenge is open" do
      registered_source

      post "#{verification_path}/observe"
      follow_redirect!

      expect(response.body).to include("Sign in again to continue.").or include("could not be checked")
      expect(DbInspector.all("SELECT id FROM verification_attempts")).to be_empty
    end
  end

  describe "the rest of the chain the verification unlocks" do
    it "walks verified source -> active source -> queued crawl" do
      registered_source
      issue_challenge
      publish(required_value)
      post "#{verification_path}/observe"

      # The sources screen now offers activation, which it refused to offer before.
      get "/app/projects/#{project_id}/sources"
      expect(response.body).to include("Activate")

      post "/app/projects/#{project_id}/sources/#{source_id}/activate"
      expect(source_state).to eq("active")

      # WF-002 refuses to activate a Project with no active Source, so this step only
      # becomes possible now — the verification is what unlocked it.
      post "/app/projects/#{project_id}/activate"
      expect(DbInspector.all("SELECT state FROM projects").first["state"]).to eq("active")

      get "/app/projects/#{project_id}/crawls"
      expect(response.body).to include("Queue crawl")
      expect(response.body).not_to include("This project cannot be crawled yet")

      post "/app/projects/#{project_id}/crawls"
      follow_redirect!
      expect(response.body).to include("Crawl queued")
      expect(DbInspector.all("SELECT state FROM crawls").first["state"]).to eq("queued")
    end

    it "states the OD-018 guard instead of offering a second trigger that would refuse" do
      registered_source
      issue_challenge
      publish(required_value)
      post "#{verification_path}/observe"
      post "/app/projects/#{project_id}/sources/#{source_id}/activate"
      post "/app/projects/#{project_id}/activate"
      post "/app/projects/#{project_id}/crawls"
      # The `initial` Evaluation is opened by StartCrawl, in the background worker, which
      # this suite deliberately does not run. Its ROW is the whole precondition, so the
      # row is what the screen is put in front of.
      open_initial_evaluation

      get "/app/projects/#{project_id}/crawls"

      # The first crawl opened an `initial` Evaluation, which is exactly what WF-005
      # refuses a second crawl on.
      expect(response.body).to include("This project cannot be crawled again")
      expect(response.body).to include("opened an evaluation that has not resolved")
      expect(response.body).not_to include("Queue crawl")

      # And the route still refuses directly, with the workflow's own reason: a hidden
      # control is not a denial.
      post "/app/projects/#{project_id}/crawls"
      follow_redirect!
      expect(response.body).to include("already has a crawl in flight")
      expect(DbInspector.all("SELECT id FROM crawls").length).to eq(1)
    end

    it "shows what the run is doing, and says plainly that it has produced nothing yet" do
      registered_source
      issue_challenge
      publish(required_value)
      post "#{verification_path}/observe"
      post "/app/projects/#{project_id}/sources/#{source_id}/activate"
      post "/app/projects/#{project_id}/activate"
      post "/app/projects/#{project_id}/crawls"

      crawl_id = DbInspector.all("SELECT id FROM crawls").first["id"]
      get "/app/projects/#{project_id}/crawls/#{crawl_id}"

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("queued")
      # The Source the run was pinned to, at the scope policy verification materialized.
      expect(response.body).to include("https://#{host}/")
      expect(response.body).to include("source-scope-interim-v1")
      # A run that has not finished says so rather than reporting an empty result as a result.
      expect(response.body).to include("This run has not finished")
      expect(response.body).to include("This run produced no documents")
      expect(response.body).to include("No URL has reached a terminal outcome")
    end

    # THE LATCH. Before the WF-006 input gate existed, this block was impossible: the
    # first crawl opened an `initial` Evaluation, nothing resolved it, and the project
    # refused every crawl after it for ever.
    describe "crawling the same project more than once" do
      def prepared_project
        registered_source
        issue_challenge
        publish(required_value)
        post "#{verification_path}/observe"
        post "/app/projects/#{project_id}/sources/#{source_id}/activate"
        post "/app/projects/#{project_id}/activate"
      end

      def crawl_ids = DbInspector.all("SELECT id FROM crawls ORDER BY created_at").map { |c| c["id"] }
      def organization_id = DbInspector.all("SELECT id FROM organizations").first["id"]

      def evaluation_for(crawl_id)
        DbInspector.all("SELECT * FROM evaluations WHERE crawl_id = $1::uuid", [crawl_id]).first
      end

      it "resolves the evaluation and then accepts a second crawl" do
        prepared_project
        post "/app/projects/#{project_id}/crawls"
        first = crawl_ids.first
        open_initial_evaluation

        # The gate runs, and the Evaluation stops being in flight.
        result = run_evaluation_input_gate(first, organization_id)
        expect(result).to be_success

        evaluation = evaluation_for(first)
        expect(evaluation["state"]).to eq("failed")
        expect(evaluation["reason"]).to eq("evaluation_inputs_unavailable")
        # `pending -> running -> failed` in one statement: `running` is a recorded
        # waypoint, so both instants are stamped and the version advanced once.
        expect(evaluation["started_at"]).to be_present
        expect(evaluation["failed_at"]).to be_present

        # The screen offers the trigger again, and the trigger works.
        get "/app/projects/#{project_id}/crawls"
        expect(response.body).to include("Queue crawl")
        expect(response.body).not_to include("cannot be crawled")

        post "/app/projects/#{project_id}/crawls"
        follow_redirect!
        expect(response.body).to include("Crawl queued")
        expect(crawl_ids.length).to eq(2)
      end

      it "shows each run's evaluation in the list, so the queue holder is visible" do
        prepared_project
        post "/app/projects/#{project_id}/crawls"
        open_initial_evaluation

        get "/app/projects/#{project_id}/crawls"
        expect(response.body).to include("Evaluation")
        expect(response.body).to include("state--pending")

        run_evaluation_input_gate(crawl_ids.first, organization_id)

        get "/app/projects/#{project_id}/crawls"
        expect(response.body).to include("state--failed")
      end

      it "emits the three events the blocked input gate is specified to emit" do
        prepared_project
        post "/app/projects/#{project_id}/crawls"
        open_initial_evaluation
        run_evaluation_input_gate(crawl_ids.first, organization_id)

        events = DbInspector.all(<<~SQL).to_h { |e| [e["event_type"], e] }
          SELECT event_type, aggregate_type, event_profile FROM event_registry
          WHERE event_type LIKE 'Evaluation%'
        SQL

        expect(events.keys).to contain_exactly("EvaluationStarted", "EvaluationInputsBlocked", "EvaluationFailed")
        expect(events["EvaluationStarted"]["aggregate_type"]).to eq("evaluation")
        expect(events["EvaluationFailed"]["aggregate_type"]).to eq("evaluation")
        # The blocked result is created on the snapshot aggregate, per its registry row.
        expect(events["EvaluationInputsBlocked"]["aggregate_type"]).to eq("evaluation_input_snapshot")
        expect(events["EvaluationInputsBlocked"]["event_profile"]).to eq("created")
      end

      it "performs no Check or provider side effect — it only records the input gate" do
        prepared_project
        post "/app/projects/#{project_id}/crawls"
        open_initial_evaluation
        before = DbInspector.all("SELECT id FROM evidence").length

        run_evaluation_input_gate(crawl_ids.first, organization_id)

        # No Evidence is produced by a blocked gate: it observed nothing.
        expect(DbInspector.all("SELECT id FROM evidence").length).to eq(before)
      end

      it "replays a duplicate delivery without transitioning anything twice" do
        prepared_project
        post "/app/projects/#{project_id}/crawls"
        open_initial_evaluation
        crawl = crawl_ids.first
        identity = SecureRandom.hex(32)

        deliver = lambda do
          command = Workflows::Wf006::Commands::SealEvaluationInputs.new(
            command_id: SecureRandom.uuid_v7, schema_version: "1.0", organization_id:,
            target_type: "crawl", crawl_id: crawl, due_at: Time.now.utc,
            action_id: SecureRandom.uuid_v7, action_identity_sha256: identity,
            requested_at_utc: Time.now.utc
          )
          Workflows::Wf006::Handlers::SealEvaluationInputs.new.call(
            command:, request_context: Platform::RequestContext.for_service(
              service_identity_id: Platform::ServiceIdentity.scheduled_action_executor,
              correlation_id: SecureRandom.uuid_v7
            )
          )
        end

        first = deliver.call
        second = deliver.call

        expect(first).to be_success
        expect(second).to be_success
        expect(second.replayed).to be(true)
        # Two guarded edges, so the aggregate advanced exactly twice — not four times.
        expect(evaluation_for(crawl)["state_version"].to_i).to eq(2)
        expect(DbInspector.all("SELECT id FROM event_registry WHERE event_type = 'EvaluationFailed'").length).to eq(1)
      end

      it "records the checkpoint and no transition when there is nothing to resolve" do
        prepared_project
        post "/app/projects/#{project_id}/crawls"
        # No Evaluation was ever opened for this Crawl (it never started).
        result = run_evaluation_input_gate(crawl_ids.first, organization_id)

        expect(result).to be_success
        expect(result.payload[:outcome]).to eq("void")
        expect(DbInspector.all("SELECT id FROM event_registry WHERE event_type LIKE 'Evaluation%'")).to be_empty
      end

      it "refuses a crawl belonging to another organization without touching it" do
        prepared_project
        post "/app/projects/#{project_id}/crawls"
        open_initial_evaluation
        crawl = crawl_ids.first

        result = run_evaluation_input_gate(crawl, SecureRandom.uuid_v7)

        expect(result).not_to be_success
        expect(result.reason_code).to eq("scheduled_action_target_mismatch")
        expect(evaluation_for(crawl)["state"]).to eq("pending")
      end

      # This run never fetched anything, so its inputs really were unavailable — and the
      # screen says WHOSE problem that is. The sentence used to blame an unbuilt analysis
      # step; now that WF-007 exists, the honest sentence is that the crawl produced nothing
      # to analyse, and it points at the per-URL outcomes rather than at the source.
      it "shows the resolved evaluation on the crawl, in terms that do not blame the source" do
        prepared_project
        post "/app/projects/#{project_id}/crawls"
        open_initial_evaluation
        crawl = crawl_ids.first
        run_evaluation_input_gate(crawl, organization_id)

        get "/app/projects/#{project_id}/crawls/#{crawl}"

        expect(response.body).to include("Evaluation")
        expect(response.body).to include("evaluation_inputs_unavailable")
        expect(response.body).to include("produced nothing that could be analysed")
        expect(response.body).to include("say what the run actually reached")
                            .or include("say what the run actually reached.")
      end
    end

    it "does not disclose another organization's crawl detail" do
      registered_source
      issue_challenge
      publish(required_value)
      post "#{verification_path}/observe"
      post "/app/projects/#{project_id}/sources/#{source_id}/activate"
      post "/app/projects/#{project_id}/activate"
      post "/app/projects/#{project_id}/crawls"
      first_project = project_id
      first_crawl = DbInspector.all("SELECT id FROM crawls").first["id"]

      post "/start/bootstrap-grant", params: { email: "other-#{SecureRandom.hex(4)}@example.com" }
      post "/start/bootstrap-organization",
           params: { organization_display_name: "Second Tenant", project_display_name: "Second Site",
                     **GenesisProjectProfile.form_params }

      get "/app/projects/#{first_project}/crawls/#{first_crawl}"

      expect(response).to have_http_status(:not_found)
      expect(response.body).not_to include(host)
    end
  end

  describe "refusal" do
    it "sends an unauthenticated visitor to sign in" do
      registered_source
      pid = project_id
      sid = source_id
      cookies.delete(ApplicationController::SESSION_COOKIE)

      get verification_path(pid, sid)

      expect(response).to redirect_to("/start/sign-in")
    end

    it "does not disclose another organization's source" do
      registered_source
      first_token = cookies[ApplicationController::SESSION_COOKIE]
      first_project = project_id
      first_source = source_id

      post "/start/bootstrap-grant", params: { email: "other-#{SecureRandom.hex(4)}@example.com" }
      post "/start/bootstrap-organization",
           params: { organization_display_name: "Second Tenant", project_display_name: "Second Site",
                     **GenesisProjectProfile.form_params }

      get verification_path(first_project, first_source)
      expect(response).to have_http_status(:not_found)

      # And it cannot issue a challenge against it either.
      post verification_path(first_project, first_source), params: { verification_method: "dns_txt" }
      expect(DbInspector.all("SELECT id FROM verification_requests")).to be_empty

      cookies[ApplicationController::SESSION_COOKIE] = first_token
    end

    it "has no local publish action outside an opted-in development process" do
      registered_source
      issue_challenge

      post "#{verification_path}/place_record"

      expect(response).to have_http_status(:not_found)
    end
  end
end
