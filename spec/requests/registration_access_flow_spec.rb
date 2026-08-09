# frozen_string_literal: true

require "rails_helper"

# The whole registration-and-access journey, driven through HTTP exactly as a browser
# would: WEB-002 grant, WEB-003 organization genesis, the Session cookie that results,
# and the two authorized reads behind it (WEB-010 organization home, WEB-011 projects).
#
# This is the proof that the layers actually meet. Every piece below existed in isolation
# before — the WF-001 handlers, the permission baseline, row level security — but nothing
# connected a request to them, so "the backend works" was true and the product was still
# unreachable.
RSpec.describe "Registration and access", type: :request do
  # The identity issuer writes receipts on its own owner connection, outside the suite's
  # transaction, and the WF-001 handlers open their own units of work.
  self.use_transactional_tests = false

  # Every cookie F1 sets is `Secure`, because `__Host-` refuses to exist without it. The
  # test client honours that and would silently drop each one over plain HTTP, so the
  # journey is driven over HTTPS exactly as a deployment serves it.
  before { integration_session.https! }

  after do
    # Close the issuer's own owner connection FIRST. `truncate_all` needs ACCESS
    # EXCLUSIVE on 26 tables, and a second idle owner connection that has just written
    # receipts is enough to deadlock against it.
    F1::LocalIdentityIssuer.reset!
    ReceiptMinter.truncate_all
  end

  let(:email) { "founder-#{SecureRandom.hex(4)}@example.com" }

  def create_organization(organization: "Acme Discoverability", project: "Acme Website")
    post "/start/bootstrap-grant", params: { email: }
    expect(response).to redirect_to("/start/bootstrap-organization")

    post "/start/bootstrap-organization",
         params: { organization_display_name: organization, project_display_name: project,
                   **GenesisProjectProfile.form_params }
  end

  describe "creating an organization" do
    it "walks grant then genesis, and lands signed in on organization home" do
      get "/start/bootstrap-grant"
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Create an organization")

      create_organization
      expect(response).to redirect_to("/app")

      # The Session bearer token is in the cookie, and it is not the Session id.
      token = cookies[ApplicationController::SESSION_COOKIE]
      expect(token).to be_present
      expect(Platform::SessionToken.plausible?(token)).to be(true)

      follow_redirect!
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Acme Discoverability")
      expect(response.body).to include(email)
    end

    it "stores only the digest of the token it handed out" do
      create_organization
      token = cookies[ApplicationController::SESSION_COOKIE]

      stored = DbInspector.all("SELECT token_sha256 FROM sessions").map { |r| r["token_sha256"] }
      expect(stored.length).to eq(1)
      # The raw token appears nowhere; the digest of it is what the row carries.
      expect(stored.first).not_to include(token)
      expect(DbInspector.all("SELECT id FROM sessions WHERE token_sha256 = $1",
                             [{ value: Platform::SessionToken.digest_of(token), format: 1 }]).length).to eq(1)
    end

    it "refuses a name outside the ratified length without creating anything" do
      post "/start/bootstrap-grant", params: { email: }
      post "/start/bootstrap-organization",
           params: { organization_display_name: "", project_display_name: "Acme Website",
                     **GenesisProjectProfile.form_params }

      expect(response).to have_http_status(:unprocessable_content)
      expect(DbInspector.all("SELECT id FROM organizations")).to be_empty
    end

    # WEB-003 (FRONTEND_ARCHITECTURE.md :51) is "render and submit Organization plus
    # first-Project body", and the body :621 requires includes the local-presence decision.
    # The registrant's own words reach the Project; the screen does not compose them, and it
    # cannot proceed without them — WORKFLOW_SPECIFICATIONS.md :657 puts the floor at 20
    # characters and SCORE_EVIDENCE_MODEL.md :587 requires a person to record it.
    it "carries the registrant's stated local-presence reason onto the genesis Project" do
      post "/start/bootstrap-grant", params: { email: }
      follow_redirect!
      # The screen asks the question; it does not answer it on the registrant's behalf.
      expect(response.body).to include("no local presence")

      reason = "We trade entirely online and have no premises any customer visits."
      post "/start/bootstrap-organization",
           params: { organization_display_name: "Acme Discoverability",
                     project_display_name: "Acme Website",
                     local_presence_applicable: "false", local_presence_reason: reason }
      expect(response).to redirect_to("/app")

      row = DbInspector.all("SELECT * FROM projects").sole
      expect(row["project_profile_schema_version"]).to eq("project-profile-v1")
      expect(row["local_presence_applicable"]).to eq("f")
      expect(row["local_presence_reason"]).to eq(reason)
      expect(row["objective"]).to eq("discoverability_assessment")
    end

    it "refuses a reason below the ratified floor without creating anything" do
      post "/start/bootstrap-grant", params: { email: }
      post "/start/bootstrap-organization",
           params: { organization_display_name: "Acme Discoverability",
                     project_display_name: "Acme Website",
                     local_presence_applicable: "false", local_presence_reason: "too short" }

      expect(response).to have_http_status(:unprocessable_content)
      expect(DbInspector.all("SELECT id FROM organizations")).to be_empty
      expect(DbInspector.all("SELECT id FROM projects")).to be_empty
    end

    # FU-72. Until now this screen hard-coded `local_presence_applicable=false` and asked
    # only for the reason, so a business that DOES trade from premises could register only
    # by declaring, in its own words, that it does not — and `CHK-LP-001` then returned
    # `not_applicable` for a business that should have been measured. The true branch of
    # WORKFLOW_SPECIFICATIONS.md :657 is now reachable from the form.
    it "commits a full Local Business Profile when the registrant asserts a local presence" do
      post "/start/bootstrap-grant", params: { email: }
      post "/start/bootstrap-organization",
           params: { organization_display_name: "Acme Discoverability",
                     project_display_name: "Acme Website",
                     local_presence_applicable: "true",
                     local_presence_address: "14 Bourke Street,  Melbourne VIC 3000",
                     local_presence_telephone: "+61390000000",
                     # Typed in the order they came to mind. :657 requires the array
                     # sorted by UTF-8 bytes, so the screen sorts it; it drops nothing.
                     local_presence_service_areas: "Richmond\nCarlton\n\nFitzroy\n" }
      expect(response).to redirect_to("/app")

      row = DbInspector.all("SELECT * FROM projects").sole
      expect(row["local_presence_applicable"]).to eq("t")
      expect(row["local_presence_reason"]).to be_nil

      profile = JSON.parse(row["local_business_profile"])
      expect(profile["schema_version"]).to eq("local-business-profile-v1")
      # Never asked for: :657 fixes it to the exact normalized Organization display name.
      expect(profile["business_name"]).to eq("Acme Discoverability")
      # Internal whitespace collapsed to one ASCII space, as :657 requires.
      expect(profile["address_text"]).to eq("14 Bourke Street, Melbourne VIC 3000")
      expect(profile["telephone_e164"]).to eq("+61390000000")
      expect(profile["service_areas"]).to eq(%w[Carlton Fitzroy Richmond])
      # The true branch carries a content digest; the false branch does not.
      expect(row["local_business_profile_content_sha256"]).to be_present
      expect(row["profile_attesting_account_id"]).to be_present
    end

    # SCORE_EVIDENCE_MODEL.md :587 lets `local_presence` be `not_applicable` only when a
    # person records the reason. An unanswered form is therefore not a `false`, and the
    # screen must not supply one on that person's behalf.
    it "refuses an unanswered applicability rather than declaring one, creating nothing" do
      post "/start/bootstrap-grant", params: { email: }
      post "/start/bootstrap-organization",
           params: { organization_display_name: "Acme Discoverability",
                     project_display_name: "Acme Website",
                     local_presence_reason: GenesisProjectProfile::DEFAULT_REASON }

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include(LocalPresenceForm::APPLICABILITY_MESSAGE)
      expect(DbInspector.all("SELECT id FROM organizations")).to be_empty
      expect(DbInspector.all("SELECT id FROM projects")).to be_empty
    end

    it "offers both answers and never preselects one" do
      post "/start/bootstrap-grant", params: { email: }
      follow_redirect!

      expect(response.body).to include("Does this project have a local presence?")
      expect(response.body).to include('value="true"')
      expect(response.body).to include('value="false"')
      expect(response.body).not_to include("checked")
    end

    it "will not reach the genesis form without a confirmed identity" do
      get "/start/bootstrap-organization"

      expect(response).to redirect_to("/start/bootstrap-grant")
    end
  end

  describe "the authenticated shell" do
    it "shows the draft project the genesis created" do
      create_organization(project: "Acme Website")
      follow_redirect!

      get "/app/projects"

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Acme Website")
      expect(response.body).to include("draft")
    end

    it "records an authorization decision for the read" do
      create_organization
      get "/app/projects"

      decisions = DbInspector.all("SELECT action, decision FROM authorization_decisions ORDER BY created_at")
      expect(decisions.map { |d| d["action"] }).to include("project.read")
      expect(decisions.select { |d| d["action"] == "project.read" }.map { |d| d["decision"] }).to all(eq("allow"))
    end

    it "creates a second project through WF-002 and lists it" do
      create_organization
      follow_redirect!

      post "/app/projects", params: {
        display_name: "Second Property", local_presence_applicable: "false",
        local_presence_reason: "This project covers an online-only storefront with no physical premises."
      }
      expect(response).to redirect_to("/app/projects")

      follow_redirect!
      expect(response.body).to include("Second Property")
    end

    # FU-72, the WF-002 half. The same question, the same two branches, and the business
    # name still never asked: this screen reads the Organization display name on its own
    # authorized connection because :657 fixes the profile's name to exactly that value.
    it "creates a second project that asserts a local presence, naming the business itself" do
      create_organization(organization: "Acme Discoverability")
      follow_redirect!

      get "/app/projects/new"
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Does this project have a local presence?")
      # Shown as the name the profile will carry, not offered as an editable control.
      expect(response.body).to include("Acme Discoverability")
      expect(response.body).not_to include("local_presence_business_name")

      post "/app/projects", params: {
        display_name: "Second Property", local_presence_applicable: "true",
        local_presence_address: "9 Smith Street, Collingwood VIC 3066",
        local_presence_telephone: "+61411000000",
        local_presence_service_areas: "Northcote\nAbbotsford"
      }
      expect(response).to redirect_to("/app/projects")

      row = DbInspector.all(
        "SELECT * FROM projects WHERE display_name = $1", ["Second Property"]
      ).sole
      expect(row["local_presence_applicable"]).to eq("t")
      profile = JSON.parse(row["local_business_profile"])
      expect(profile["business_name"]).to eq("Acme Discoverability")
      expect(profile["service_areas"]).to eq(%w[Abbotsford Northcote])
    end

    it "refuses a second project whose applicability was left unanswered" do
      create_organization
      follow_redirect!

      post "/app/projects", params: {
        display_name: "Second Property",
        local_presence_reason: GenesisProjectProfile::DEFAULT_REASON
      }

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include(LocalPresenceForm::APPLICABILITY_MESSAGE)
      expect(DbInspector.all("SELECT id FROM projects WHERE display_name = $1",
                             ["Second Property"])).to be_empty
    end
  end

  describe "registering a source" do
    def first_project_id
      DbInspector.all("SELECT id FROM projects ORDER BY created_at").first["id"]
    end

    it "registers a source against the genesis project and lists it as proposed" do
      create_organization
      follow_redirect!
      project_id = first_project_id

      get "/app/projects/#{project_id}/sources"
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("No sources registered")

      post "/app/projects/#{project_id}/sources", params: { submitted_root_uri: "https://example.com" }
      expect(response).to redirect_to("/app/projects/#{project_id}/sources")

      follow_redirect!
      expect(response.body).to include("example.com")
      # Registration only PROPOSES: it must not present the Source as verified or active.
      expect(response.body).to include("proposed")
      # The one action a proposed Source has is WEB-015 verification, not activation.
      expect(response.body).to include("Verify ownership")
      expect(response.body).not_to include("Activate")
    end

    it "refuses a non-HTTPS address with the workflow's own reason, creating nothing" do
      create_organization
      project_id = first_project_id

      post "/app/projects/#{project_id}/sources", params: { submitted_root_uri: "http://example.com" }

      expect(response).to have_http_status(:unprocessable_content)
      expect(DbInspector.all("SELECT id FROM sources")).to be_empty
    end

    it "does not disclose another organization's project through the sources route" do
      create_organization(organization: "First Tenant", project: "First Site")
      first_token = cookies[ApplicationController::SESSION_COOKIE]
      first_project = first_project_id

      other_email = "other-#{SecureRandom.hex(4)}@example.com"
      post "/start/bootstrap-grant", params: { email: other_email }
      post "/start/bootstrap-organization",
           params: { organization_display_name: "Second Tenant", project_display_name: "Second Site",
                     **GenesisProjectProfile.form_params }
      second_project = DbInspector.all("SELECT id FROM projects ORDER BY created_at").last["id"]
      expect(second_project).not_to eq(first_project)

      # The first tenant asking for the second tenant's Project gets "not found", which
      # does not distinguish absent from forbidden.
      cookies[ApplicationController::SESSION_COOKIE] = first_token
      get "/app/projects/#{second_project}/sources"

      expect(response).to have_http_status(:not_found)
      expect(response.body).not_to include("Second Site")
    end
  end

  describe "the crawls screen" do
    def first_project_id
      DbInspector.all("SELECT id FROM projects ORDER BY created_at").first["id"]
    end

    it "states both unmet prerequisites instead of offering a trigger that would refuse" do
      create_organization
      follow_redirect!
      project_id = first_project_id

      get "/app/projects/#{project_id}/crawls"

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("This project cannot be crawled yet")
      # The genesis Project is a draft with no sources, so BOTH conditions are named.
      expect(response.body).to include("It must be active")
      expect(response.body).to include("No active source")
      expect(response.body).not_to include("Queue crawl")
      expect(response.body).to include("No crawls have run")
    end

    it "refuses a directly posted trigger with the workflow's own reason" do
      create_organization
      project_id = first_project_id

      # A hidden control is not a denial: the route is posted to directly and WF-005 is
      # what actually refuses it.
      post "/app/projects/#{project_id}/crawls"

      expect(response).to redirect_to("/app/projects/#{project_id}/crawls")
      follow_redirect!
      expect(response.body).to match(/no active source|Activate the project/i)
      expect(DbInspector.all("SELECT id FROM crawls")).to be_empty
    end
  end

  describe "refusal" do
    it "sends an unauthenticated visitor to sign in rather than rendering the shell" do
      get "/app"

      expect(response).to redirect_to("/start/sign-in")
    end

    it "refuses a well-formed token that matches no Session" do
      cookies[ApplicationController::SESSION_COOKIE] = Platform::SessionToken.mint.raw

      get "/app"

      expect(response).to redirect_to("/start/sign-in")
    end

    it "does not let one organization's cookie read another's projects" do
      create_organization(organization: "First Tenant", project: "First Site")
      first_token = cookies[ApplicationController::SESSION_COOKIE]

      # A second, entirely separate tenant.
      other_email = "other-#{SecureRandom.hex(4)}@example.com"
      post "/start/bootstrap-grant", params: { email: other_email }
      post "/start/bootstrap-organization",
           params: { organization_display_name: "Second Tenant", project_display_name: "Second Site",
                     **GenesisProjectProfile.form_params }

      cookies[ApplicationController::SESSION_COOKIE] = first_token
      get "/app/projects"

      expect(response.body).to include("First Site")
      expect(response.body).not_to include("Second Site")
    end
  end

  describe "signing in again" do
    it "issues a new Session for an existing account" do
      create_organization
      follow_redirect!
      organization_id = DbInspector.all("SELECT id FROM organizations").first["id"]
      cookies.delete(ApplicationController::SESSION_COOKIE)

      post "/start/sign-in", params: { email:, organization_id: }

      expect(response).to redirect_to("/app")
      expect(cookies[ApplicationController::SESSION_COOKIE]).to be_present

      follow_redirect!
      expect(response.body).to include("Acme Discoverability")
    end
  end
end
