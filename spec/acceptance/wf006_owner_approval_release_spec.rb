# frozen_string_literal: true

require "rails_helper"
require_relative "support/wf006_parse_chain"

# THE APPROVAL SWITCH: the owner-approval release service, and what an approved package can and
# cannot make a Check say.
#
# The collection chain, the intake boundary and the Check were all built. The step between them —
# the principal entitled to turn a `proposed` package `active` — was named by the specification
# (WORKFLOW_SPECIFICATIONS.md :168; IMPLEMENTATION_MATRIX.md :1579; contracts/S-08.json,
# "`measurement_set.activate` for the owner-approval release service") and existed nowhere in the
# code. A staged package could therefore never become usable by any path the platform owned.
#
# TWO HALVES, AND THE SECOND MATTERS MORE. Activation must work; and an APPROVED BUT EXPIRED package
# must still be refused by the Check, for the right reason. A system that consumes stale evidence
# because someone approved it once is worse than one that consumes nothing — and the wrong refusal
# would be almost as bad: `input_evidence_missing` tells a customer nothing was ever measured, when
# in fact it was measured and the measurement expired. Both are asserted below, against the real
# chain, on separate assertions.
RSpec.describe "WF-006 owner-approval release service", type: :acceptance,
               acceptance_ids: %w[AC-CAP-010 AC-WF-006], test_types: %w[TYP-DATA TYP-SEC] do
  include Wf006ParseChain
  self.use_transactional_tests = false
  after { ReceiptMinter.truncate_all }

  let(:catalog) { Workflows::Wf007::CheckCatalog }
  let(:intake) { Workflows::Wf006::MeasurementIntake }
  let(:package_module) { Workflows::Wf006::MeasurementPackage }
  let(:release) { Workflows::Wf006::OwnerApprovalRelease.new }

  def sealed_evaluation
    ctx = crawlable
    run_to_parsed(ctx, outbound_pages("/" => { body: "<html><head><title>Acme</title></head></html>" }))
    ctx
  end

  def in_org(org)
    Platform::UnitOfWork.run do |conn|
      store = IdentityAccess::Infrastructure::EvaluationInputStore.new(conn.raw_connection)
      store.enter_org_context(org:, correlation_id: SecureRandom.uuid_v7)
      yield store
    end
  end

  def definition = catalog.definition("CHK-AIP-001")

  # THE FIXTURE IS SHAPED ON THE PACKAGE THAT IS REALLY STAGED. The row in the development database
  # was collected by `videt-probe-harness` at `videt.vertical-run-export-v0.1` for
  # `ai_answer_presence`, and `observed` is a parameter precisely so the same fixture can be run both
  # inside and outside its 24-hour window. Nothing here collects anything: the observations are
  # written by the fixture, and the signatures are fixture values.
  def package_for(ctx, observed:, keys: %w[Q-1 Q-2], items: nil, set_version: "1.0.0")
    org = ctx[:g][:organization_id]
    items ||= keys.map do |key|
      { "intent_key" => key, "presence_status" => "present", "citation_status" => "cited",
        "entity_keys" => ["Acme Supplies"] }
    end
    {
      "package_schema_version" => "measurement-set-package-v1",
      "measurement_set_id" => "videt-aip-release-switch", "measurement_set_version" => set_version,
      "measurement_kind" => "ai_answer_presence",
      "organization_id" => org, "project_id" => ctx[:g][:project_id],
      "package_created_at" => observed.iso8601, "proposed_effective_at" => observed.iso8601,
      "provider_identities" => [{ "provider" => "anthropic", "model" => "claude-sonnet-5" }],
      "collector_adapter" => { "id" => "videt-probe-harness", "version" => "videt.vertical-run-export-v0.1",
                               "sha256" => Digest::SHA256.hexdigest("adapter") },
      "expected_keys" => keys,
      "key_content" => keys.to_h { |k| [k, "Who are the best builders in Melbourne? (#{k})"] },
      "locale" => "en-AU", "time_zone" => "UTC", "max_evidence_age_seconds" => 86_400,
      "binding" => {
        "catalog_version" => catalog::CATALOG_VERSION,
        "catalog_sha256" => catalog.hex(catalog.catalog_digest),
        "definition_id" => "CHK-AIP-001", "definition_version" => "1.0.0",
        "definition_sha256" => catalog.hex(catalog.definition_digest(definition))
      },
      "retention_location" => "operations/probe-harness/evidence/",
      "owner_approval_reference" => "OD-010-FIXTURE",
      "observations" => [{
        "schema_version" => "external-observation-v1",
        "organization_id" => org, "project_id" => ctx[:g][:project_id],
        "measurement_kind" => "ai_answer_presence",
        "measurement_policy_version" => "external-measurement-interim-v1",
        "collector_adapter_id" => "videt-probe-harness",
        "collector_adapter_version" => "videt.vertical-run-export-v0.1",
        "measurement_set_version" => set_version, "locale" => "en-AU", "time_zone" => "UTC",
        "observed_at_utc" => observed.iso8601,
        "captured_at_utc" => observed.iso8601,
        "fresh_until_utc" => (observed + 86_400).iso8601,
        "coverage_status" => "complete",
        "body" => { "expected_intent_keys" => keys, "items" => items }
      }]
    }
  end

  # Both owners over the SAME digest. Fixture values: this spec builds the mechanism, it does not
  # exercise anyone's judgement with it.
  def signed(package)
    hex = package_module.digest(package).unpack1("H*")
    package.merge(
      "signatures" => {
        "chief_product" => { "signer_identity" => "chief.product@videt.example", "authority" => "Chief Product",
                             "signed_at" => Time.now.utc.iso8601, "decision" => "approved",
                             "package_sha256" => hex },
        "chief_architect" => { "signer_identity" => "chief.architect@videt.example",
                               "authority" => "Chief Architect",
                               "signed_at" => Time.now.utc.iso8601, "decision" => "approved",
                               "package_sha256" => hex }
      }
    )
  end

  def import(ctx, package)
    in_org(ctx[:g][:organization_id]) do |store|
      intake.import(store:, package:, organization_id: ctx[:g][:organization_id],
                    project_id: ctx[:g][:project_id], now: Time.now.utc,
                    correlation_id: SecureRandom.uuid_v7,
                    catalog_version: catalog::CATALOG_VERSION,
                    catalog_sha256: catalog.hex(catalog.catalog_digest))
    end
  end

  def activate(ctx, package)
    release.call(package:, organization_id: ctx[:g][:organization_id], now: Time.now.utc,
                 correlation_id: SecureRandom.uuid_v7)
  end

  def submit(ctx, payload)
    in_org(ctx[:g][:organization_id]) do |store|
      intake.submit(store:, payload:, organization_id: ctx[:g][:organization_id],
                    project_id: ctx[:g][:project_id],
                    evaluation_id: evaluation_for(ctx[:crawl_id])["id"],
                    now: Time.now.utc, correlation_id: SecureRandom.uuid_v7)
    end
  end

  def set_row = DbInspector.one("SELECT * FROM measurement_sets", [])

  # THE REAL STORE, HELD OPEN AT ONE STATEMENT. Not a double: every call reaches the real object and
  # does its real work against the real database. The wrapper adds one advisory-lock acquisition
  # immediately before the guarded UPDATE, which is what lets `RaceHarness` suspend the operation
  # MID-TRANSACTION — after it has read `proposed`, before it tries to write — so a competing
  # activation can commit underneath it. It is an anonymous class rather than a named one because a
  # constant assigned inside a `describe` block lands on `Object` (FU-42).
  def held_at_activation(store, gate)
    Class.new(SimpleDelegator) do
      define_method(:gate) { gate }

      def activate_measurement_set(**kwargs)
        __getobj__.serialize_on(gate)
        __getobj__.activate_measurement_set(**kwargs)
      end
    end.new(store)
  end

  def executions
    DbInspector.all("SELECT * FROM command_executions WHERE command_type = $1 ORDER BY created_at, id",
                    ["wf006.activate_measurement_set"])
  end

  # `command_results` carries no `command_type` of its own; it names the execution that produced it,
  # which is where the type lives.
  def results_rows
    DbInspector.all(<<~SQL, ["wf006.activate_measurement_set"])
      SELECT r.* FROM command_results r
      JOIN command_executions e ON e.id = r.command_execution_id
      WHERE e.command_type = $1 ORDER BY r.created_at, r.id
    SQL
  end

  # =====================================================================================
  describe "the permission it acts under" do
    # THE SWITCH IS NOT A BUTTON. :168 reads `deny` in all six actor columns and names the release
    # service in the seventh, so no role, in any mode, may reach it. The population is the ratified
    # column list rather than a hand-picked role, so a role added to the table is covered here the
    # day it appears.
    it "denies `measurement_set.activate` to every canonical role, in every mode" do
      roles = RatifiedPermissionBaseline.canonical_role_columns
      expect(roles).not_to be_empty

      roles.each do |role|
        expect(Platform::PermissionBaseline.permits?("measurement_set.activate", [role]))
          .to be(false), "#{role} may activate a Measurement Set"
      end
      # Holding every role at once still does not confer it.
      expect(Platform::PermissionBaseline.permits?("measurement_set.activate", roles)).to be(false)
      expect(Platform::PermissionBaseline.mode_permits?("measurement_set.activate", "read_only")).to be(false)
    end

    # The seventh column, materialized: one registered row, active, scoped to this permission and
    # nothing else. A build that named the executor or the identity service here would have widened
    # activation to every path those identities already run.
    it "registers the release service as an active identity scoped to that permission alone" do
      row = DbInspector.one("SELECT * FROM service_identities WHERE id = $1::uuid",
                            [Platform::ServiceIdentity::RELEASE_SERVICE])

      expect(row).not_to be_nil
      expect(row["subject"]).to eq("f1.release_service")
      expect(row["status"]).to eq("active")
      expect(JSON.parse(row["permission_scope"])).to eq({ "measurement_set" => ["activate"] })
      # The registered row AND the constant that seeds it, because `ensure_service_identities` never
      # overwrites an existing row — so a widened scope in Ruby would sit there unapplied, agreeing
      # with nothing and denying nothing, until the next database was built from it.
      reserved = Platform::ServiceIdentity::RESERVED
                 .find { |id, *| id == Platform::ServiceIdentity::RELEASE_SERVICE }
      expect(JSON.parse(reserved.last)).to eq({ "measurement_set" => ["activate"] })
      expect(Platform::ServiceIdentity::RELEASE_SERVICE)
        .not_to eq(Platform::ServiceIdentity::SCHEDULED_ACTION_EXECUTOR)
      expect(Platform::ServiceIdentity::RELEASE_SERVICE).not_to eq(Platform::ServiceIdentity::IDENTITY_SERVICE)
    end
  end

  # =====================================================================================
  describe "activation" do
    it "moves a signed package from proposed to active and records who approved it and when" do
      ctx = sealed_evaluation
      package = package_for(ctx, observed: start_now - 60)
      import(ctx, package)
      expect(set_row["status"]).to eq("proposed")

      result = activate(ctx, signed(package))

      expect(result).to be_success
      row = set_row
      expect(row["status"]).to eq("active")
      # All four approval columns are WRITTEN, not left null. The database's
      # `activation_requires_both_signatures` CHECK refuses an active row without them, so a build
      # that skipped them could not have committed — this asserts their CONTENT is real.
      expect(row["activated_at"]).not_to be_nil
      expect(row["owner_approval_reference"]).to eq("OD-010-FIXTURE")
      expect(JSON.parse(row["product_signature"])["signer_identity"]).to eq("chief.product@videt.example")
      expect(JSON.parse(row["architect_signature"])["signer_identity"]).to eq("chief.architect@videt.example")
      expect(row["state_version"].to_i).to eq(1)
    end

    it "attributes the activation to the release service identity and to no human actor" do
      ctx = sealed_evaluation
      package = package_for(ctx, observed: start_now - 60)
      import(ctx, package)

      activate(ctx, signed(package))

      execution = executions.last
      expect(execution["service_identity_id"]).to eq(Platform::ServiceIdentity::RELEASE_SERVICE)
      expect(execution["actor_id"]).to be_nil
      expect(execution["action"]).to eq("measurement_set.activate")
      expect(execution["target_type"]).to eq("release_artifact")

      audit = DbInspector.one(<<~SQL, [Platform::ServiceIdentity::RELEASE_SERVICE])
        SELECT * FROM audit_record_registry WHERE service_identity_id = $1::uuid
      SQL
      expect(audit["actor_id"]).to be_nil
      expect(audit["to_state"]).to eq("active")
      expect(audit["outcome"]).to eq("success")
      expect(audit["workflow_id"]).to eq("WF-006")
      payload = JSON.parse(audit["payload"])
      expect(payload["owner_approval_reference"]).to eq("OD-010-FIXTURE")
      expect(payload["signers"].map { |s| s["signer_identity"] })
        .to eq(["chief.architect@videt.example", "chief.product@videt.example"])

      result_row = results_rows.last
      expect(result_row["outcome"]).to eq("success")
      expect(result_row["service_identity_id"]).to eq(Platform::ServiceIdentity::RELEASE_SERVICE)
      expect(result_row["actor_id"]).to be_nil
    end

    # Twice on the same bytes is ONE activation. The second call returns the stored result rather
    # than re-running the transition, so the set's version does not move and no second approval is
    # recorded for an approval that happened once.
    it "is idempotent: a replay returns the stored result and activates nothing a second time" do
      ctx = sealed_evaluation
      package = package_for(ctx, observed: start_now - 60)
      import(ctx, package)
      first = activate(ctx, signed(package))

      second = activate(ctx, signed(package))

      expect(second).to be_success
      expect(second.replayed).to be(true)
      expect(second.result_id).to eq(first.result_id)
      expect(set_row["state_version"].to_i).to eq(1)
      expect(results_rows.count { |r| r["outcome"] == "success" }).to eq(1)
    end

    # An already-active set is refused before the guarded UPDATE is reached, so a second approval of
    # bytes that are already live changes nothing. This is the EARLY guard; the version guard behind
    # it is a different statement and is raced below.
    it "refuses to activate a set that is already active" do
      ctx = sealed_evaluation
      org = ctx[:g][:organization_id]
      package = package_for(ctx, observed: start_now - 60)
      import(ctx, package)
      activate(ctx, signed(package))

      result = in_org(org) do |store|
        intake.activate(store:, package: signed(package), organization_id: org, now: Time.now.utc,
                        correlation_id: SecureRandom.uuid_v7)
      end

      expect(result).not_to be_ok
      expect(result.reason).to eq("measurement_set_terminal")
      expect(set_row["state_version"].to_i).to eq(1)
    end

    # THE VERSION GUARD, RACED RATHER THAN SIMULATED.
    #
    # `activate_measurement_set` is guarded on `status = 'proposed' AND state_version = $2` and
    # returns NO ROW when it loses; the command must report that as a refusal. It used to return
    # `ok(nil)` — a success whose record was nothing — which made a lost race indistinguishable from
    # a real activation to every caller, including one that would then have recorded an approval that
    # never happened.
    #
    # SEQUENTIAL CALLS CANNOT REACH THIS BRANCH, which is why the defect survived: by the time a
    # second call runs, the first has committed and the EARLY `status == 'proposed'` guard refuses
    # first. The branch needs a caller that has already READ `proposed` when someone else commits.
    # `RaceHarness` produces exactly that — the gated operation is held on an advisory lock between
    # its read and its write, and is released only once the winner has committed underneath it.
    it "refuses when it LOSES the version race, rather than reporting an empty success" do
      ctx = sealed_evaluation
      org = ctx[:g][:organization_id]
      package = package_for(ctx, observed: start_now - 60)
      import(ctx, package)
      approved = signed(package)
      gate = "measurement-set-activation-gate"

      losers, = RaceHarness.interleave(
        RaceHarness.key_for(gate),
        gated: [lambda do
          Platform::UnitOfWork.run do |conn|
            store = IdentityAccess::Infrastructure::EvaluationInputStore.new(conn.raw_connection)
            store.enter_org_context(org:, correlation_id: SecureRandom.uuid_v7)
            intake.activate(store: held_at_activation(store, gate), package: approved,
                            organization_id: org, now: Time.now.utc, correlation_id: SecureRandom.uuid_v7)
          end
        end],
        while_committing: -> { activate(ctx, approved) }
      )

      loser = losers.first
      expect(loser).to be_a(Workflows::Wf006::MeasurementIntake::Result)
      expect(loser).not_to be_ok
      expect(loser.reason).to eq("measurement_set_terminal")
      expect(loser.record).to be_nil
      # Exactly one activation happened, and the winner's is the one that stands.
      expect(set_row["state_version"].to_i).to eq(1)
      expect(results_rows.count { |r| r["outcome"] == "success" }).to eq(1)
    end

    # ONE EXAMPLE PER TERMINAL STATE, NOT A LOOP. `sealed_evaluation` bootstraps a real Organization
    # from an identity memoized PER EXAMPLE, so two chains inside one example would collide on it —
    # which is why this file's harness comment says to parameterize by example rather than by loop.
    it "refuses a package that has been superseded, and changes nothing" do
      ctx = sealed_evaluation
      package = package_for(ctx, observed: start_now - 60)
      import(ctx, package)
      DbInspector.connection.exec_params(
        "UPDATE measurement_sets SET status='superseded', superseded_at=now() WHERE id=$1::uuid",
        [set_row["id"]]
      )

      result = activate(ctx, signed(package))

      expect(result).to be_failure
      expect(result.reason_code).to eq("measurement_set_terminal")
      expect(set_row["status"]).to eq("superseded")
      expect(set_row["activated_at"]).to be_nil
    end

    it "refuses a package that has been rejected, and changes nothing" do
      ctx = sealed_evaluation
      package = package_for(ctx, observed: start_now - 60)
      import(ctx, package)
      DbInspector.connection.exec_params(
        "UPDATE measurement_sets SET status='rejected', rejected_reason='owner declined' WHERE id=$1::uuid",
        [set_row["id"]]
      )

      result = activate(ctx, signed(package))

      expect(result).to be_failure
      expect(result.reason_code).to eq("measurement_set_terminal")
      expect(set_row["status"]).to eq("rejected")
      expect(set_row["activated_at"]).to be_nil
    end

    # A REFUSAL MUST NOT BE STICKY. A package refused today for want of a second signature has to be
    # activatable tomorrow when that signature arrives — so the refusal records what happened and
    # stores no idempotency row under the unchanged bytes.
    it "records a refusal without latching it, so the properly signed package still activates" do
      ctx = sealed_evaluation
      package = package_for(ctx, observed: start_now - 60)
      import(ctx, package)
      one_signature = signed(package)
      one_signature["signatures"].delete("chief_architect")

      refused = activate(ctx, one_signature)

      expect(refused).to be_failure
      expect(refused.reason_code).to eq("measurement_set_approval_incomplete")
      expect(set_row["status"]).to eq("proposed")
      failure_audit = DbInspector.one(<<~SQL, [Platform::ServiceIdentity::RELEASE_SERVICE])
        SELECT * FROM audit_record_registry
        WHERE service_identity_id = $1::uuid AND outcome = 'failure'
      SQL
      expect(failure_audit["reason_code"]).to eq("measurement_set_approval_incomplete")

      expect(activate(ctx, signed(package))).to be_success
      expect(set_row["status"]).to eq("active")
    end
  end

  # =====================================================================================
  # THE HALF THAT MATTERS MOST.
  #
  # The package staged in the development database was created on 8 August against a
  # `max_evidence_age_seconds` of 86,400, so by the time this switch exists it is nearly two days
  # old. Approving it must not make it usable. These two examples run the SAME package through the
  # SAME chain at two ages and assert the Check says two different, correct things.
  describe "an approved package that has expired" do
    def evaluate_with(ctx, package)
      import(ctx, package)
      expect(activate(ctx, signed(package))).to be_success
      expect(submit(ctx, package["observations"].first)).to be_ok

      advance_wf007(ctx)
      drain_check_attempts(ctx)
      advance_wf007(ctx)
      check_results(evaluation_for(ctx[:crawl_id])["id"]).index_by { |r| r["check_definition_id"] }
    end

    # 48 hours before the snapshot seals, against a 24-hour rule. The activation succeeds — the
    # owner really did approve these bytes — and the Check refuses them anyway.
    it "is activated, and the Check refuses it as STALE rather than as missing" do
      ctx = sealed_evaluation
      expired = package_for(ctx, observed: start_now - (48 * 3600))

      results = evaluate_with(ctx, expired)

      aip = results["CHK-AIP-001"]
      expect(aip["error_reason_code"]).to eq("input_evidence_stale")
      # The distinction is the finding. `input_evidence_missing` would tell a customer nothing had
      # ever been measured, when in fact it was measured and the measurement expired.
      expect(aip["error_reason_code"]).not_to eq("input_evidence_missing")
      expect(set_row["status"]).to eq("active")
    end

    # The mechanism behind that refusal, asserted separately so the example above cannot pass for
    # the wrong reason: the expired observation is SELECTED and tagged `stale`, not dropped. An
    # entry that selected nothing would also report a handled error, and would be indistinguishable
    # from "no evidence was ever supplied" in the applicability record.
    it "selects the expired observation and tags it stale, rather than silently dropping it" do
      ctx = sealed_evaluation
      expired = package_for(ctx, observed: start_now - (48 * 3600))
      evaluate_with(ctx, expired)

      entry = applicability_entries(evaluation_for(ctx[:crawl_id])["id"])
              .find { |e| e["check_definition_id"] == "CHK-AIP-001" }
      selected = JSON.parse(entry["selected_evidence"])

      expect(selected.length).to eq(1)
      expect(selected.first["freshness"]).to eq("stale")
    end

    # THE FRESH PATH, THROUGH THE RELEASE SERVICE, IN THE TEST ENVIRONMENT ONLY. Same fixture, same
    # chain, an observation inside its window: a real AI-presence verdict. This is what the owner
    # gets after a fresh collection run, and it costs nothing to prove because the observation is a
    # fixture rather than something collected.
    it "produces a real verdict when the same package is inside its freshness window" do
      ctx = sealed_evaluation
      keys = %w[Q-1 Q-2 Q-3 Q-4 Q-5]
      items = keys.each_with_index.map do |key, index|
        if index < 2
          { "intent_key" => key, "presence_status" => "present", "citation_status" => "cited",
            "entity_keys" => ["Acme Supplies"] }
        else
          { "intent_key" => key, "presence_status" => "absent", "citation_status" => "not_cited",
            "entity_keys" => [] }
        end
      end
      fresh = package_for(ctx, observed: start_now - 60, keys:, items:)

      results = evaluate_with(ctx, fresh)

      aip = results["CHK-AIP-001"]
      expect(aip["error_reason_code"]).to be_nil
      observation = JSON.parse(aip["normalized_observation"])
      expect(observation["expected_count"]).to eq(5)
      expect(observation["qualified_count"]).to eq(2)
      expect(observation["qualified_rate"]).to eq("0.4000")
    end
  end
end
