# frozen_string_literal: true

require "rails_helper"
require "digest"
require "securerandom"

# F-02 Envelope Encryption — rotation & retirement (FOUNDATION-002 §Rotation semantics).
# rewrap re-wraps the DEK under the active version without rewriting the payload; it is
# idempotent and concurrency-safe. retire stops a version encrypting while it still decrypts.
RSpec.describe "F-02 rotation & retirement", type: :model do
  let(:provider) { EncryptionSupport::InMemoryKeyProvider.new }
  let(:cipher) { Platform::Encryption::EnvelopeCipher.new(key_provider: provider) }
  let(:plaintext) { "f1-verification=rotate-me".b }

  def aad
    Platform::Encryption::Aad.for(
      application: "verification", record_type: "verification_request",
      record_id: "req-1", purpose: "challenge_token", tenant: "org-1"
    )
  end

  def deserialize(bytes) = Platform::Encryption::Envelope.deserialize(bytes)

  describe "EnvelopeCipher#rewrap" do
    it "re-wraps the DEK under the active version, preserving the payload, and still decrypts" do
      envelope = cipher.encrypt(plaintext:, aad:)
      provider.rotate!("v2")

      rewrapped = cipher.rewrap(envelope:, aad:)
      expect(rewrapped.wrapping_key_version).to eq("v2")
      expect(rewrapped.wrapped_dek).not_to eq(envelope.wrapped_dek)
      # the payload ciphertext is NOT rewritten
      expect(rewrapped.ciphertext).to eq(envelope.ciphertext)
      expect(rewrapped.nonce).to eq(envelope.nonce)
      expect(rewrapped.authentication_tag).to eq(envelope.authentication_tag)
      expect(cipher.decrypt(envelope: rewrapped, aad:)).to eq(plaintext)
    end

    it "is idempotent when already at the active version" do
      envelope = cipher.encrypt(plaintext:, aad:)
      expect(cipher.rewrap(envelope:, aad:)).to eq(envelope)
    end
  end

  describe "EncryptedRecordStore#rewrap (real DB)" do
    let(:store) { Platform::Encryption::EncryptedRecordStore.new }
    let(:digest) { Digest::SHA256.digest(plaintext) }

    def store_secret
      store.put(envelope: cipher.encrypt(plaintext:, aad:), aad:, content_digest: digest)
    end

    it "rewraps a stored record to the active version, preserves the payload, and still decrypts" do
      reference = store_secret
      original = deserialize(store.fetch(reference).envelope)
      provider.rotate!("v2")

      expect(store.rewrap(reference, cipher:)).to eq(:rewrapped)
      fetched = store.fetch(reference)
      expect(fetched.wrapping_key_version).to eq("v2")
      updated = deserialize(fetched.envelope)
      expect(updated.ciphertext).to eq(original.ciphertext) # payload preserved
      expect(cipher.decrypt(envelope: updated, aad:)).to eq(plaintext)
    end

    it "is a no-op when the record is already at the active version" do
      expect(store.rewrap(store_secret, cipher:)).to eq(:unchanged)
    end

    it "is concurrency-safe: a stale rewrap against the old version does not double-apply" do
      reference = store_secret
      provider.rotate!("v2")
      expect(store.rewrap(reference, cipher:)).to eq(:rewrapped)

      # simulate a concurrent rewrap that still believes the record is at v1
      connection = ActiveRecord::Base.connection.raw_connection
      new_envelope = cipher.rewrap(envelope: deserialize(store.fetch(reference).envelope), aad:)
      outcome = connection.exec_params(
        "SELECT f1_encrypted_record_rewrap($1, $2, $3, $4) AS o",
        [reference, "v1", "v2", { value: new_envelope.serialize, format: 1 }]
      ).to_a.first["o"]
      expect(outcome).to eq("stale")
    end

    it "reports :destroyed and :unknown appropriately" do
      reference = store_secret
      store.destroy(reference)
      expect(store.rewrap(reference, cipher:)).to eq(:destroyed)
      expect(store.rewrap(SecureRandom.uuid, cipher:)).to eq(:unknown)
    end
  end

  describe "retire (owner-only key-version mutation, real DB)" do
    let(:owner) { ReceiptMinter.owner_connection }
    let(:provider_id) { "platform-keyring-test-#{SecureRandom.hex(4)}" }
    let(:key) { Platform::Encryption::Aes256Gcm.random_key }
    let(:key_provider) do
      Platform::Encryption::PlatformKeyProvider.new(
        id: provider_id,
        key_source: Platform::Encryption::DeploymentKeySource.new(keys: { provider_id => { "v1" => key } })
      )
    end

    before do
      owner.exec_params(
        "SELECT f1_encryption_register_active_version($1, $2, $3, $4)",
        [provider_id, "v1", { value: Digest::SHA256.digest(key), format: 1 }, "ref"]
      )
    end

    after { owner.exec_params("DELETE FROM f1_encryption_key_versions WHERE provider = $1", [provider_id]) }

    def retire(version) = owner.exec_params("SELECT f1_encryption_retire_version($1, $2) AS o", [provider_id, version]).to_a.first["o"]

    it "retires an active version idempotently and reports unknown for a missing one" do
      expect(retire("v1")).to eq("retired")
      expect(retire("v1")).to eq("already_retired")
      expect(retire("nope")).to eq("unknown")
    end

    it "stops a retired version encrypting while it still decrypts" do
      wrapped = key_provider.wrap(dek: key, aad: "a".b) # while active
      retire("v1")

      expect(key_provider.status("v1")).to eq(:retired)
      expect { key_provider.active_version }
        .to raise_error(Platform::Encryption::Error) { |e| expect(e.reason).to eq(:key_unavailable) }
      expect(key_provider.unwrap(wrapped: wrapped.bytes, version: "v1", aad: "a".b)).to eq(key)
    end
  end
end
