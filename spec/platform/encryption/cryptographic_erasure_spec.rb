# frozen_string_literal: true

require "rails_helper"
require "digest"
require "securerandom"

# F-02 Envelope Encryption — cryptographic erasure (FOUNDATION-002 §Cryptographic erasure).
# Two exact, distinct destruction boundaries: record-level (one value) and key-version
# (every value dependent on the version). Erasure is real irrecoverability, not a soft
# delete; non-secret audit metadata survives; and bulk erasure is unreachable from the runtime.
RSpec.describe "F-02 cryptographic erasure", type: :model do
  let(:plaintext) { "f1-verification=erase-me-forever".b }

  def aad
    Platform::Encryption::Aad.for(
      application: "verification", record_type: "verification_request",
      record_id: "req-1", purpose: "challenge_token", tenant: "org-1"
    )
  end

  describe "record-level erasure (destroy one value)" do
    let(:provider) { EncryptionSupport::InMemoryKeyProvider.new }
    let(:cipher) { Platform::Encryption::EnvelopeCipher.new(key_provider: provider) }
    let(:store) { Platform::Encryption::EncryptedRecordStore.new }
    let(:digest) { Digest::SHA256.digest(plaintext) }

    it "removes the only path to the plaintext while keeping the digest and audit" do
      reference = store.put(envelope: cipher.encrypt(plaintext:, aad:), aad:, content_digest: digest)
      expect(store.destroy(reference)).to eq(:destroyed)

      fetched = store.fetch(reference)
      # not a soft delete: the row survives for audit, but the envelope (and thus the DEK)
      # is gone, so the plaintext is unrecoverable even though the key provider is intact.
      expect(fetched.state).to eq("destroyed")
      expect(fetched.envelope).to be_nil
      expect(fetched.content_digest).to eq(digest)
    end

    it "is irreversible: a destroyed record never yields an envelope again" do
      reference = store.put(envelope: cipher.encrypt(plaintext:, aad:), aad:, content_digest: digest)
      store.destroy(reference)
      expect(store.destroy(reference)).to eq(:already_destroyed)
      expect(store.fetch(reference).envelope).to be_nil
    end
  end

  describe "key-version erasure (destroy every value under a version)" do
    let(:owner) { ReceiptMinter.owner_connection }
    let(:provider_id) { "platform-keyring-test-#{SecureRandom.hex(4)}" }
    let(:key) { Platform::Encryption::Aes256Gcm.random_key }
    let(:key_provider) do
      Platform::Encryption::PlatformKeyProvider.new(
        id: provider_id,
        key_source: Platform::Encryption::DeploymentKeySource.new(keys: { provider_id => { "v1" => key } })
      )
    end
    let(:cipher) { Platform::Encryption::EnvelopeCipher.new(key_provider:) }

    before do
      owner.exec_params(
        "SELECT f1_encryption_register_active_version($1, $2, $3, $4)",
        [provider_id, "v1", { value: Digest::SHA256.digest(key), format: 1 }, "ref"]
      )
    end

    after { owner.exec_params("DELETE FROM f1_encryption_key_versions WHERE provider = $1", [provider_id]) }

    def destroy_version(version) = owner.exec_params("SELECT f1_encryption_destroy_version($1, $2) AS o", [provider_id, version]).to_a.first["o"]

    it "makes every envelope under the version irrecoverable" do
      envelope = cipher.encrypt(plaintext:, aad:) # a value protected under v1
      expect(cipher.decrypt(envelope:, aad:)).to eq(plaintext) # recoverable before destruction

      expect(destroy_version("v1")).to eq("destroyed")

      expect(key_provider.status("v1")).to eq(:destroyed)
      expect { cipher.decrypt(envelope:, aad:) }
        .to raise_error(Platform::Encryption::Error) { |e| expect(e.reason).to eq(:key_destroyed) }
    end

    it "is irreversible: a destroyed version can never be reactivated" do
      destroy_version("v1")
      expect do
        owner.exec_params(
          "SELECT f1_encryption_register_active_version($1, $2, $3, $4)",
          [provider_id, "v1", { value: Digest::SHA256.digest(key), format: 1 }, "ref"]
        )
      end.to raise_error(PG::RaiseException, /destroyed key version cannot be reactivated/)
    end

    it "is idempotent and reports unknown for a missing version" do
      expect(destroy_version("v1")).to eq("destroyed")
      expect(destroy_version("v1")).to eq("already_destroyed")
      expect(destroy_version("nope")).to eq("unknown")
    end
  end

  describe "bulk erasure is unreachable from the runtime" do
    def runtime = ActiveRecord::Base.connection

    it "denies the runtime the owner-only key-version destroy mutation" do
      expect { runtime.execute("SELECT f1_encryption_destroy_version('x','y')") }
        .to raise_error(ActiveRecord::StatementInvalid, /permission denied/)
    end

    it "denies the runtime the owner-only retire mutation" do
      expect { runtime.execute("SELECT f1_encryption_retire_version('x','y')") }
        .to raise_error(ActiveRecord::StatementInvalid, /permission denied/)
    end
  end
end
