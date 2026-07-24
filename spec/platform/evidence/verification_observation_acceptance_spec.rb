# frozen_string_literal: true

require "rails_helper"
require "digest"
require "securerandom"

# F-03 Evidence Production — acceptance: a verification_observation record persists with full
# provenance and a content digest, and its RESTRICTED payload holds no plaintext token or raw
# observation (FOUNDATION-003 acceptance). This is F-03 consuming F-02: the redacted payload
# is protected behind an F-02 reference, and the Evidence envelope records only that reference
# plus a content digest — never inline plaintext. It also asserts the producer/reader surface.
RSpec.describe "F-03 verification_observation acceptance", type: :model do
  # The raw secret an observation would see. It must appear NOWHERE at rest.
  let(:token) { "f1-verification=SUPER-SECRET-CHALLENGE-#{SecureRandom.hex(8)}" }
  let(:organization_id) { TenantSeeder.create_organization }
  let(:project_id) { seed_project(organization_id) }
  let(:runtime) { ActiveRecord::Base.connection.raw_connection }

  # F-02 wired with the in-memory key provider (the production key ring needs deployment
  # secrets); the real encrypted-record store persists the ciphertext.
  let(:crypto_cipher) { Platform::Encryption::EnvelopeCipher.new(key_provider: EncryptionSupport::InMemoryKeyProvider.new) }
  let(:crypto_store) { Platform::Encryption::EncryptedRecordStore.new }

  before { runtime.exec_params("SELECT f1_enter_org_context($1::uuid, $2::uuid)", [organization_id, SecureRandom.uuid]) }

  def seed_project(org)
    id = SecureRandom.uuid_v7
    DbInspector.connection.exec_params(<<~SQL, [id, org])
      INSERT INTO projects
        (id, state_version, lock_version, created_at, updated_at, correlation_id, organization_id,
         display_name, locale, time_zone, objective, state, source_set_version)
      VALUES ($1,0,0,now(),now(),gen_random_uuid(),$2,'P','en-AU','UTC','discoverability_assessment','draft',0)
    SQL
    id
  end

  # A redacted verification_observation payload: enums, counts, and a HASH of the observed
  # value — never the token itself (SCORE_EVIDENCE_MODEL.md :160).
  def redacted_payload
    Platform::CanonicalJson.encode(
      "verification_request_id" => "vr-1", "method" => "http_file",
      "observation_location" => "https://example.com/.well-known/f1-verification.txt",
      "attempt_number" => 1, "attempt_origin" => "automated", "automated_slot_offset" => 0,
      "network_outcome" => "response", "http_status" => 200, "received_byte_count" => 42,
      "observed_value_sha256" => Digest::SHA256.hexdigest(token), # the hash, not the token
      "match_decision" => "matched", "reason_code" => "matched"
    ).b
  end

  it "persists a restricted verification_observation with the payload behind an F-02 reference, and no plaintext at rest" do
    payload = redacted_payload
    aad = Platform::Encryption::Aad.for(
      application: "evidence", record_type: "verification_observation",
      record_id: "attempt-1", purpose: "observation_payload", tenant: organization_id
    )
    protected_payload = Platform::Encryption.protect(plaintext: payload, aad:, cipher: crypto_cipher, store: crypto_store)

    record = Platform::Evidence::Record.build(
      schema_version: "verification-observation-v1", organization_id:, project_id:, source_id: nil, evaluation_id: nil,
      evidence_type: "verification_observation", producer_id: "svc-verifier", attempt_id: "attempt-1",
      payload_reference: protected_payload.reference, content_sha256: protected_payload.content_digest.unpack1("H*"),
      captured_at_utc: Time.utc(2026, 7, 25), observed_at_utc: Time.utc(2026, 7, 25),
      source_system: "f1-verification", collection_method: "http_file", collector_version: "verification-observer-v1",
      validation_status: "valid", validation_reason_code: nil,
      data_classification: "restricted", payload_retention_class: "product_evidence_payload",
      correlation_id: SecureRandom.uuid
    )
    evidence_id = Platform::Evidence.produce(record)

    persisted = Platform::Evidence.get(evidence_id)
    expect(persisted.evidence_type).to eq("verification_observation")
    expect(persisted.data_classification).to eq("restricted")
    expect(persisted.payload_reference).to eq(protected_payload.reference) # a reference, not the payload
    expect(persisted.content_sha256).to eq(protected_payload.content_digest.unpack1("H*"))
    expect(Platform::Evidence.find_by_content_hash(persisted.content_sha256).map(&:evidence_id)).to include(evidence_id)

    # The Evidence envelope holds only a reference + digest — no inline payload, no token.
    row_values = runtime.exec_params("SELECT * FROM evidence WHERE id=$1", [evidence_id]).to_a.first.values.join
    expect(row_values).not_to include(token)
    expect(row_values).not_to include("SUPER-SECRET")

    # The F-02 payload record holds only ciphertext.
    expect(crypto_store.fetch(protected_payload.reference).envelope).not_to include(token)

    # Revealing the payload yields the redacted observation (a hash), never the token.
    revealed = Platform::Encryption.reveal(protected_payload.reference, aad:, cipher: crypto_cipher, store: crypto_store)
    expect(revealed).to eq(payload)
    expect(revealed).not_to include(token)
  end
end
