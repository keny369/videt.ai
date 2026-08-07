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
                   project_objective: "Improve discoverability" }
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
           params: { organization_display_name: "", project_display_name: "Acme Website" }

      expect(response).to have_http_status(:unprocessable_content)
      expect(DbInspector.all("SELECT id FROM organizations")).to be_empty
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
        display_name: "Second Property",
        local_presence_reason: "This project covers an online-only storefront with no physical premises."
      }
      expect(response).to redirect_to("/app/projects")

      follow_redirect!
      expect(response.body).to include("Second Property")
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
      expect(response.body).to include("Awaiting ownership verification")
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
           params: { organization_display_name: "Second Tenant", project_display_name: "Second Site" }
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
           params: { organization_display_name: "Second Tenant", project_display_name: "Second Site" }

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
