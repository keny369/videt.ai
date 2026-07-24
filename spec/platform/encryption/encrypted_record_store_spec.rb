# frozen_string_literal: true

require "rails_helper"
require "digest"

# F-02 Envelope Encryption — the encrypted-record storage boundary against the real
# database (FOUNDATION-002). Proves store/fetch/destroy through the SECURITY DEFINER
# functions, that the runtime cannot touch the owner-only table, and that no plaintext is
# persisted. Runs on the runtime (f1_web) connection inside the fixture transaction.
RSpec.describe Platform::Encryption::EncryptedRecordStore, type: :model do
  let(:provider) { EncryptionSupport::InMemoryKeyProvider.new }
  let(:cipher) { Platform::Encryption::EnvelopeCipher.new(key_provider: provider) }
  let(:store) { described_class.new }
  let(:plaintext) { "f1-verification=highly-secret-challenge".b }
  let(:digest) { Digest::SHA256.digest(plaintext) }

  def aad
    Platform::Encryption::Aad.for(
      application: "verification", record_type: "verification_request",
      record_id: "req-1", purpose: "challenge_token", tenant: "org-1"
    )
  end

  def store_secret
    envelope = cipher.encrypt(plaintext:, aad:)
    store.put(envelope:, aad:, content_digest: digest)
  end

  describe "store and fetch" do
    it "returns an unguessable reference and round-trips the envelope back to plaintext" do
      reference = store_secret
      expect(reference).to match(/\A[0-9a-f-]{36}\z/)

      fetched = store.fetch(reference)
      expect(fetched.state).to eq("active")
      expect(fetched.content_digest).to eq(digest)
      envelope = Platform::Encryption::Envelope.deserialize(fetched.envelope)
      expect(cipher.decrypt(envelope:, aad:)).to eq(plaintext)
    end

    it "returns nil for an unknown reference" do
      expect(store.fetch(SecureRandom.uuid)).to be_nil
    end

    it "persists no plaintext — only the ciphertext envelope" do
      fetched = store.fetch(store_secret)
      expect(fetched.envelope).not_to include(plaintext)
      expect(fetched.envelope).not_to include("challenge")
    end
  end

  describe "record-level destruction (cryptographic erasure of one value)" do
    it "removes the envelope, keeps the digest, and makes decryption impossible" do
      reference = store_secret
      expect(store.destroy(reference)).to eq(:destroyed)

      fetched = store.fetch(reference)
      expect(fetched).to be_destroyed
      expect(fetched.envelope).to be_nil          # the only path to the DEK is gone
      expect(fetched.content_digest).to eq(digest) # the non-secret anchor survives
    end

    it "is idempotent" do
      reference = store_secret
      expect(store.destroy(reference)).to eq(:destroyed)
      expect(store.destroy(reference)).to eq(:already_destroyed)
    end

    it "reports :unknown for a missing reference" do
      expect(store.destroy(SecureRandom.uuid)).to eq(:unknown)
    end
  end

  describe "the runtime cannot reach around the boundary" do
    it "is denied a direct SELECT on the owner-only table" do
      expect { ActiveRecord::Base.connection.execute("SELECT * FROM f1_encrypted_records") }
        .to raise_error(ActiveRecord::StatementInvalid, /permission denied/)
    end
  end
end
