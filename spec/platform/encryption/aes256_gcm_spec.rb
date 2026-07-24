# frozen_string_literal: true

require "rails_helper"

# F-02 Envelope Encryption — the AES-256-GCM primitive (FOUNDATION-002 §Envelope format).
# The single authenticated-encryption op: any mutation of ciphertext, nonce, tag, key or
# AAD is caught on open as one typed authentication_failed, never a silent plaintext.
RSpec.describe Platform::Encryption::Aes256Gcm, type: :model do
  let(:key) { described_class.random_key }
  let(:aad) { "canonical-aad-bytes".b }
  let(:plaintext) { "the challenge token: f1-verification=abc123".b }
  let(:err) { Platform::Encryption::Error }

  def reason(&block) = raise_error(err) { |e| expect(e.reason).to eq(block.call) }

  describe "keys and nonces" do
    it "generates a 256-bit key" do
      expect(described_class.random_key.bytesize).to eq(32)
    end
  end

  describe "round trip" do
    it "seals and opens back to the exact plaintext" do
      sealed = described_class.seal(key:, plaintext:, aad:)
      expect(sealed.nonce.bytesize).to eq(12)
      expect(sealed.tag.bytesize).to eq(16)
      opened = described_class.open(key:, nonce: sealed.nonce, ciphertext: sealed.ciphertext, tag: sealed.tag, aad:)
      expect(opened).to eq(plaintext)
    end

    it "produces distinct ciphertext for identical plaintext (fresh nonce per seal)" do
      a = described_class.seal(key:, plaintext:, aad:)
      b = described_class.seal(key:, plaintext:, aad:)
      expect(a.nonce).not_to eq(b.nonce)
      expect(a.ciphertext).not_to eq(b.ciphertext)
    end
  end

  describe "tamper detection is one typed outcome" do
    let(:sealed) { described_class.seal(key:, plaintext:, aad:) }

    def open_with(nonce: sealed.nonce, ciphertext: sealed.ciphertext, tag: sealed.tag, aad: self.aad, key: self.key)
      described_class.open(key:, nonce:, ciphertext:, tag:, aad:)
    end

    def flip(bytes)
      out = bytes.dup
      out.setbyte(0, out.getbyte(0) ^ 0x01)
      out
    end

    it "fails on a mutated ciphertext" do
      expect { open_with(ciphertext: flip(sealed.ciphertext)) }.to reason { :authentication_failed }
    end

    it "fails on a mutated nonce" do
      expect { open_with(nonce: flip(sealed.nonce)) }.to reason { :authentication_failed }
    end

    it "fails on a mutated tag" do
      expect { open_with(tag: flip(sealed.tag)) }.to reason { :authentication_failed }
    end

    it "fails on a different AAD" do
      expect { open_with(aad: "other-aad".b) }.to reason { :authentication_failed }
    end

    it "fails on the wrong key" do
      expect { open_with(key: described_class.random_key) }.to reason { :authentication_failed }
    end

    it "fails a wrong-length nonce/tag without reaching the cipher" do
      expect { open_with(nonce: "short".b) }.to reason { :authentication_failed }
      expect { open_with(tag: "short".b) }.to reason { :authentication_failed }
    end
  end

  describe "key validation" do
    it "rejects a wrong-length key as provider_failure" do
      expect { described_class.seal(key: "too-short".b, plaintext:, aad:) }.to reason { :provider_failure }
    end
  end

  describe "packed serialization for an opaque single-blob field" do
    it "round-trips a sealed value through pack/unpack" do
      sealed = described_class.seal(key:, plaintext:, aad:)
      restored = described_class.unpack(sealed.pack)
      expect(restored.nonce).to eq(sealed.nonce)
      expect(restored.tag).to eq(sealed.tag)
      expect(restored.ciphertext).to eq(sealed.ciphertext)
    end

    it "rejects a short or wrong-version packed blob as malformed_envelope" do
      expect { described_class.unpack("x".b) }.to reason { :malformed_envelope }
      expect { described_class.unpack(("\x02".b + ("y" * 40).b)) }.to reason { :malformed_envelope }
    end
  end
end
