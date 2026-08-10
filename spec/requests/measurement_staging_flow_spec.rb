# frozen_string_literal: true

require "rails_helper"

# Staging an owner-approval Measurement Set package, driven through HTTP exactly as a browser
# drives it (OD-010 § Required Owner Approval Package; WORKFLOW_SPECIFICATIONS.md :480-482).
#
# THE PROPERTY THIS SCREEN EXISTS TO HAVE IS A NEGATIVE ONE. The permission baseline denies
# `measurement_set.activate` to every human role and reserves it for the owner-approval release
# service, so the screen must be able to stage a package and must NOT be able to turn one on. That
# is asserted here from the route table as well as from the page: an action that does not exist
# cannot be reached by guessing a URL, and an assertion about the rendered buttons alone would not
# prove that.
RSpec.describe "Measurement set staging", type: :request do
  self.use_transactional_tests = false

  before { integration_session.https! }
  after do
    F1::LocalIdentityIssuer.reset!
    ReceiptMinter.truncate_all
  end

  let(:email) { "founder-#{SecureRandom.hex(4)}@example.com" }
  let(:catalog) { Workflows::Wf007::CheckCatalog }

  def create_organization
    post "/start/bootstrap-grant", params: { email: }
    post "/start/bootstrap-organization",
         params: { organization_display_name: "Acme Discoverability", project_display_name: "Acme Website",
                   **GenesisProjectProfile.form_params }
  end

  def project = DbInspector.all("SELECT * FROM projects ORDER BY created_at").first
  def measurements_path = "/app/projects/#{project['id']}/measurements"
  def sets = DbInspector.all("SELECT * FROM measurement_sets", [])

  # THE INSTANT IS READ ONCE PER EXAMPLE, NOT ONCE PER CALL.
  #
  # WHAT WAS WRONG, MEASURED IN A WHOLE-SUITE RUN ON 2026-08-11. `package` took `Time.now.utc.floor`
  # FRESH on every call, and "accepts a valid package…" calls it TWICE: once to build the body it
  # POSTs, and once more to compute the digest it expects on the page. Five members are derived from
  # that instant — `package_created_at`, `proposed_effective_at`, `observed_at_utc`,
  # `captured_at_utc`, `fresh_until_utc` — so whenever the two calls straddle a SECOND BOUNDARY the
  # two packages differ and their digests differ. The example then failed with two perfectly valid
  # digests that were simply not of the same document.
  #
  # IT IS LOAD-SENSITIVE, WHICH IS WHY IT LOOKED LIKE SOMETHING ELSE. Run alone the two calls are
  # microseconds apart and it never fires; inside a 3055-example run it fired once, and a reader who
  # re-runs the file sees green and concludes the suite was at fault. That is FU-79's class — an
  # assertion resting on a real wall clock — by a different mechanism: not arithmetic over a budget,
  # but two independent clock reads REQUIRED TO AGREE.
  #
  # The repair is not a fixed clock. These packages carry a 24-hour freshness rule that a frozen 2026
  # instant would silently violate, so the instant stays real and is simply read ONCE, which is all
  # the property needs. Memoising here rather than in the one example fixes the CLASS: a future
  # caller that builds the same package twice can no longer get two different documents.
  def observed_at = @observed_at ||= Time.now.utc.floor

  def package(overrides = {})
    observed = observed_at
    definition = catalog.definition("CHK-AIP-001")
    {
      "package_schema_version" => "measurement-set-package-v1",
      "measurement_set_id" => "acme-aip", "measurement_set_version" => "1.0.0",
      "measurement_kind" => "ai_answer_presence",
      "organization_id" => project["organization_id"], "project_id" => project["id"],
      "package_created_at" => observed.iso8601, "proposed_effective_at" => observed.iso8601,
      "provider_identities" => [{ "provider" => "openai", "model" => "gpt-5.5" }],
      "collector_adapter" => { "id" => "videt-probe-harness", "version" => "v0.1",
                               "sha256" => Digest::SHA256.hexdigest("adapter") },
      "expected_keys" => %w[Q-1 Q-2],
      "key_content" => { "Q-1" => "Who are the best builders in Melbourne?",
                         "Q-2" => "Who should build my custom home in Melbourne?" },
      "locale" => "en-AU", "time_zone" => "UTC", "max_evidence_age_seconds" => 86_400,
      "binding" => { "catalog_version" => catalog::CATALOG_VERSION,
                     "catalog_sha256" => catalog.hex(catalog.catalog_digest),
                     "definition_id" => "CHK-AIP-001", "definition_version" => "1.0.0",
                     "definition_sha256" => catalog.hex(catalog.definition_digest(definition)) },
      "retention_location" => "operations/probe-harness/evidence/",
      "owner_approval_reference" => "OD-010",
      "observations" => [{
        "schema_version" => "external-observation-v1",
        "organization_id" => project["organization_id"], "project_id" => project["id"],
        "measurement_kind" => "ai_answer_presence",
        "measurement_policy_version" => "external-measurement-interim-v1",
        "collector_adapter_id" => "videt-probe-harness", "collector_adapter_version" => "v0.1",
        "measurement_set_version" => "1.0.0", "locale" => "en-AU", "time_zone" => "UTC",
        "observed_at_utc" => observed.iso8601, "captured_at_utc" => observed.iso8601,
        "fresh_until_utc" => (observed + 86_400).iso8601, "coverage_status" => "complete",
        "body" => { "expected_intent_keys" => %w[Q-1 Q-2], "items" => [
          { "intent_key" => "Q-1", "presence_status" => "present", "citation_status" => "cited",
            "entity_keys" => ["Acme"] },
          { "intent_key" => "Q-2", "presence_status" => "absent", "citation_status" => "not_cited",
            "entity_keys" => [] }
        ] }
      }]
    }.merge(overrides)
  end

  describe "the empty screen" do
    it "says plainly that nothing external is measured" do
      create_organization

      get measurements_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("No package has been staged")
      expect(response.body).to include("not measured")
    end
  end

  describe "staging a package" do
    it "accepts a valid package, stages it as proposed and shows the digest to sign" do
      create_organization

      post measurements_path, params: { package: JSON.generate(package) }

      expect(response).to have_http_status(:see_other)
      expect(sets.length).to eq(1)
      expect(sets.first["status"]).to eq("proposed")

      follow_redirect!
      expect(response.body).to include("proposed")
      # The exact digest both owners must sign, on the page.
      digest = Workflows::Wf006::MeasurementPackage.digest(package).unpack1("H*")
      expect(response.body).to include(digest)
      expect(response.body).to include("Measures nothing")
    end

    # The refusal names WHICH of the register's required parts is missing. "Invalid package"
    # would send an operator back to the register to guess.
    it "refuses an incomplete package and names the missing field" do
      create_organization

      post measurements_path, params: { package: JSON.generate(package.except("binding")) }
      follow_redirect!

      expect(sets).to be_empty
      expect(response.body).to include("authorizes nothing")
      expect(response.body).to include("package_field_missing")
    end

    it "refuses text that is not JSON without raising" do
      create_organization

      post measurements_path, params: { package: "not a package" }
      follow_redirect!

      expect(sets).to be_empty
      expect(response.body).to include("not valid JSON")
    end

    # Cross-tenant content fails closed at the boundary, before anything persists.
    it "refuses a package naming another organization" do
      create_organization

      post measurements_path, params: { package: JSON.generate(package("organization_id" => SecureRandom.uuid_v7)) }
      follow_redirect!

      expect(sets).to be_empty
      expect(response.body).to include("tenant_mismatch")
    end

    it "is idempotent: staging the same package twice leaves one proposal" do
      create_organization
      body = JSON.generate(package)

      post measurements_path, params: { package: body }
      post measurements_path, params: { package: body }

      expect(sets.length).to eq(1)
    end
  end

  describe "the activation edge this screen must not cross" do
    # ACTIVATION IS NOT ROUTABLE. Not "not linked" and not "hidden" — absent from the route
    # table, so no URL reaches it.
    it "exposes no activate route at all" do
      paths = Rails.application.routes.routes.map { |r| r.path.spec.to_s }
      expect(paths.grep(/measurement/).sort)
        .to eq(["/app/projects/:project_id/measurements(.:format)"] * 2)
      expect(paths.any? { |p| p.include?("activate") && p.include?("measurement") }).to be(false)
    end

    it "leaves the staged package measuring nothing" do
      create_organization
      post measurements_path, params: { package: JSON.generate(package) }

      expect(sets.first["status"]).to eq("proposed")
      expect(sets.first["activated_at"]).to be_nil
      expect(sets.first["product_signature"]).to be_nil
      expect(sets.first["architect_signature"]).to be_nil
      # And no observation has become Evidence, because submission needs an ACTIVE set.
      expect(DbInspector.all("SELECT id FROM evidence WHERE evidence_type='external_measurement'", []))
        .to be_empty
    end
  end
end
