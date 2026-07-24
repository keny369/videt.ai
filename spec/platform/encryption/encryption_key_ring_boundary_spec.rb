# frozen_string_literal: true

require "rails_helper"
require "digest"
require "securerandom"

# F-02 Envelope Encryption — the key-ring metadata boundary, end to end against the real
# database (FOUNDATION-002; owner refinement 2026-07-25). Proves the runtime resolves the
# ring through the SECURITY DEFINER functions only, that it cannot touch the owner-only
# table or the owner-only register mutation, and that the DB holds no key material.
RSpec.describe "F-02 key-ring metadata boundary", type: :model do
  let(:provider_id) { "platform-keyring-test-#{SecureRandom.hex(4)}" }
  let(:key) { Platform::Encryption::Aes256Gcm.random_key }
  let(:fingerprint) { Digest::SHA256.digest(key) }
  let(:owner) { ReceiptMinter.owner_connection }

  let(:metadata) { Platform::Encryption::DatabaseMetadataStore.new }
  let(:key_source) { Platform::Encryption::DeploymentKeySource.new(keys: { provider_id => { "v1" => key } }) }
  let(:provider) { Platform::Encryption::PlatformKeyProvider.new(id: provider_id, metadata:, key_source:) }
  let(:aad) { "canonical-aad".b }

  before do
    owner.exec_params(
      "SELECT f1_encryption_register_active_version($1, $2, $3, $4)",
      [provider_id, "v1", { value: fingerprint, format: 1 }, "test-ref"]
    )
  end

  after do
    owner.exec_params("DELETE FROM f1_encryption_key_versions WHERE provider = $1", [provider_id])
  end

  it "resolves the active version through the SECURITY DEFINER boundary" do
    expect(provider.active_version).to eq("v1")
    expect(provider.status("v1")).to eq(:usable)
    expect(provider.status("nope")).to eq(:unknown)
  end

  it "wraps and unwraps a DEK end to end through the real boundary" do
    dek = Platform::Encryption::Aes256Gcm.random_key
    wrapped = provider.wrap(dek:, aad:)
    expect(wrapped.version).to eq("v1")
    expect(provider.unwrap(wrapped: wrapped.bytes, version: wrapped.version, aad:)).to eq(dek)
  end

  it "stores no key material in the metadata — only a non-secret fingerprint" do
    row = owner.exec_params(
      "SELECT encode(key_fingerprint, 'hex') AS fp_hex FROM f1_encryption_key_versions WHERE provider = $1 AND version = 'v1'",
      [provider_id]
    ).to_a.first
    expect(row["fp_hex"]).to eq(fingerprint.unpack1("H*"))
    expect(row["fp_hex"]).not_to eq(key.unpack1("H*")) # a hash of the key, never the key
  end

  describe "the runtime cannot reach around the boundary" do
    def runtime = ActiveRecord::Base.connection

    it "is denied a direct SELECT on the owner-only metadata table" do
      expect { runtime.execute("SELECT * FROM f1_encryption_key_versions") }
        .to raise_error(ActiveRecord::StatementInvalid, /permission denied/)
    end

    it "is denied the owner-only register mutation" do
      expect { runtime.execute("SELECT f1_encryption_register_active_version('x','y',decode('00','hex'),null)") }
        .to raise_error(ActiveRecord::StatementInvalid, /permission denied/)
    end

    it "is granted the read functions it needs" do
      expect(runtime.select_value("SELECT f1_encryption_active_version(#{runtime.quote(provider_id)})")).to eq("v1")
    end
  end
end
