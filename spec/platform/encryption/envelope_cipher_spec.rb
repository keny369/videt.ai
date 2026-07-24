# frozen_string_literal: true

require "rails_helper"

# F-02 Envelope Encryption — the EnvelopeCipher (FOUNDATION-002 §Abstraction). The heart of
# the acceptance bar: round-trip, distinct ciphertext, every mutation fails, AAD relocation
# fails, and a second provider works unchanged.
RSpec.describe Platform::Encryption::EnvelopeCipher, type: :model do
  let(:provider) { EncryptionSupport::InMemoryKeyProvider.new }
  let(:cipher) { described_class.new(key_provider: provider) }
  let(:plaintext) { "f1-verification=super-secret-challenge-token".b }
  let(:err) { Platform::Encryption::Error }

  def aad(**overrides)
    Platform::Encryption::Aad.for(**{
      application: "verification", record_type: "verification_request",
      record_id: "req-1", purpose: "challenge_token", tenant: "org-1"
    }.merge(overrides))
  end

  # Flip the last byte, which for every field (including the packed wrapped DEK, whose
  # first byte is the format-version prefix) lands in cryptographic material.
  def flip(bytes)
    out = bytes.dup
    last = out.bytesize - 1
    out.setbyte(last, out.getbyte(last) ^ 0x01)
    out
  end

  def reason(sym, &block) = raise_error(err) { |e| expect(e.reason).to eq(sym) }

  describe "round trip" do
    it "encrypts and decrypts back to the exact plaintext" do
      envelope = cipher.encrypt(plaintext:, aad: aad)
      expect(cipher.decrypt(envelope:, aad: aad)).to eq(plaintext)
    end

    it "carries the full versioned metadata" do
      envelope = cipher.encrypt(plaintext:, aad: aad)
      expect(envelope.format_version).to eq(1)
      expect(envelope.algorithm).to eq("AES-256-GCM")
      expect(envelope.key_provider).to eq(provider.id)
      expect(envelope.wrapping_key_version).to eq(provider.active_version)
      expect(envelope.aad_schema_version).to eq("record-aad-v1")
    end

    it "never exposes the plaintext in the envelope" do
      envelope = cipher.encrypt(plaintext:, aad: aad)
      expect(envelope.serialize).not_to include(plaintext)
      expect(envelope.ciphertext).not_to eq(plaintext)
    end
  end

  it "produces distinct ciphertext (fresh DEK + nonce) for identical plaintext" do
    a = cipher.encrypt(plaintext:, aad: aad)
    b = cipher.encrypt(plaintext:, aad: aad)
    expect(a.ciphertext).not_to eq(b.ciphertext)
    expect(a.nonce).not_to eq(b.nonce)
    expect(a.wrapped_dek).not_to eq(b.wrapped_dek)
    expect(cipher.decrypt(envelope: a, aad: aad)).to eq(plaintext)
    expect(cipher.decrypt(envelope: b, aad: aad)).to eq(plaintext)
  end

  describe "any mutation fails authentication" do
    let(:envelope) { cipher.encrypt(plaintext:, aad: aad) }

    it "fails on a mutated ciphertext" do
      expect { cipher.decrypt(envelope: envelope.with(ciphertext: flip(envelope.ciphertext)), aad: aad) }
        .to reason(:authentication_failed)
    end

    it "fails on a mutated nonce" do
      expect { cipher.decrypt(envelope: envelope.with(nonce: flip(envelope.nonce)), aad: aad) }
        .to reason(:authentication_failed)
    end

    it "fails on a mutated authentication tag" do
      expect { cipher.decrypt(envelope: envelope.with(authentication_tag: flip(envelope.authentication_tag)), aad: aad) }
        .to reason(:authentication_failed)
    end

    it "fails on a mutated wrapped DEK" do
      expect { cipher.decrypt(envelope: envelope.with(wrapped_dek: flip(envelope.wrapped_dek)), aad: aad) }
        .to reason(:authentication_failed)
    end
  end

  describe "AAD relocation fails authentication" do
    let(:envelope) { cipher.encrypt(plaintext:, aad: aad) }

    {
      "record" => { record_id: "req-2" },
      "record type" => { record_type: "other_record" },
      "attribute/purpose" => { purpose: "other_purpose" },
      "tenant" => { tenant: "org-2" }
    }.each do |label, change|
      it "rejects a ciphertext relocated to another #{label}" do
        expect { cipher.decrypt(envelope:, aad: aad(**change)) }.to reason(:authentication_failed)
      end
    end
  end

  describe "structural mismatches are typed before the crypto runs" do
    let(:envelope) { cipher.encrypt(plaintext:, aad: aad) }

    it "rejects an AAD schema mismatch as aad_mismatch" do
      expect { cipher.decrypt(envelope:, aad: aad(schema_version: "record-aad-v2")) }.to reason(:aad_mismatch)
    end

    it "rejects an unsupported format" do
      expect { cipher.decrypt(envelope: envelope.with(format_version: 2), aad: aad) }.to reason(:unsupported_format)
    end

    it "rejects an unsupported algorithm" do
      expect { cipher.decrypt(envelope: envelope.with(algorithm: "AES-128-CBC"), aad: aad) }.to reason(:unsupported_algorithm)
    end

    it "rejects an envelope from another key provider" do
      expect { cipher.decrypt(envelope: envelope.with(key_provider: "some-other-provider"), aad: aad) }
        .to reason(:unsupported_key_provider)
    end
  end

  describe "provider substitutability (the second-provider acceptance)" do
    it "works unchanged against the production KeyProvider with an injected key" do
      key = Platform::Encryption::Aes256Gcm.random_key
      metadata = EncryptionSupport::FakeMetadataStore.new
      metadata.register("v1", key)
      platform = Platform::Encryption::PlatformKeyProvider.new(
        id: "platform-keyring", metadata:,
        key_source: Platform::Encryption::DeploymentKeySource.new(keys: { "platform-keyring" => { "v1" => key } })
      )
      other_cipher = described_class.new(key_provider: platform)

      envelope = other_cipher.encrypt(plaintext:, aad: aad)
      expect(other_cipher.decrypt(envelope:, aad: aad)).to eq(plaintext)
      expect(envelope.key_provider).to eq("platform-keyring")
    end
  end
end
