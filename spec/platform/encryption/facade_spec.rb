# frozen_string_literal: true

require "rails_helper"
require "digest"
require "securerandom"

# F-02 Envelope Encryption — the frozen public façade (FOUNDATION-002). protect/reveal/erase
# are the entire consumer surface; the cipher and store are injected here so the wiring is
# proven against the real storage boundary with the in-memory key provider.
RSpec.describe Platform::Encryption, type: :model do
  let(:provider) { EncryptionSupport::InMemoryKeyProvider.new }
  let(:cipher) { Platform::Encryption::EnvelopeCipher.new(key_provider: provider) }
  let(:store) { Platform::Encryption::EncryptedRecordStore.new }
  let(:plaintext) { "f1-verification=facade-secret".b }

  def aad(**overrides)
    Platform::Encryption::Aad.for(**{
      application: "verification", record_type: "verification_request",
      record_id: "req-1", purpose: "challenge_token", tenant: "org-1"
    }.merge(overrides))
  end

  def protect = described_class.protect(plaintext:, aad: aad, cipher:, store:)

  describe ".protect / .reveal" do
    it "protects a value and reveals it back to the exact plaintext" do
      result = protect
      expect(result.reference).to match(/\A[0-9a-f-]{36}\z/)
      expect(result.content_digest).to eq(Digest::SHA256.digest(plaintext))
      expect(described_class.reveal(result.reference, aad: aad, cipher:, store:)).to eq(plaintext)
    end

    it "raises a typed error when the AAD does not match" do
      reference = protect.reference
      expect { described_class.reveal(reference, aad: aad(record_id: "other"), cipher:, store:) }
        .to raise_error(Platform::Encryption::Error) { |e| expect(e.reason).to eq(:authentication_failed) }
    end

    it "returns nil for an unknown reference" do
      expect(described_class.reveal(SecureRandom.uuid, aad: aad, cipher:, store:)).to be_nil
    end
  end

  describe ".erase" do
    it "erases the value so a later reveal returns nil" do
      reference = protect.reference
      expect(described_class.erase(reference, store:)).to eq(:destroyed)
      expect(described_class.reveal(reference, aad: aad, cipher:, store:)).to be_nil
    end
  end

  describe "no secret ever appears in a loggable or exception surface" do
    it "redacts an error to the reason alone" do
      error = Platform::Encryption::Error.new(:authentication_failed)
      expect(error.redacted).to eq(error: "encryption_error", reason: :authentication_failed)
    end

    it "leaks no plaintext through an authentication failure" do
      reference = protect.reference
      described_class.reveal(reference, aad: aad(record_id: "other"), cipher:, store:)
    rescue Platform::Encryption::Error => e
      expect(e.message).not_to include(plaintext)
      expect(e.redacted.to_s).not_to include(plaintext)
    end
  end
end
