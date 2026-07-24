# frozen_string_literal: true

require "rails_helper"

# F-02 Envelope Encryption — the deterministic in-memory KeyProvider (FOUNDATION-002).
# It satisfies the shared KeyProvider contract and adds the lifecycle behaviour the
# rotation/erasure tranches depend on.
RSpec.describe EncryptionSupport::InMemoryKeyProvider, type: :model do
  let(:provider) { described_class.new }
  let(:aad) { "canonical-aad".b }
  let(:err) { Platform::Encryption::Error }

  it_behaves_like "a KeyProvider"

  describe "lifecycle" do
    let(:dek) { Platform::Encryption::Aes256Gcm.random_key }

    it "rotation activates a new version and retires the previous one, which still decrypts" do
      wrapped_v1 = provider.wrap(dek:, aad:)
      provider.rotate!("v2")

      expect(provider.active_version).to eq("v2")
      expect(provider.status("v1")).to eq(:retired)
      expect(provider.status("v2")).to eq(:usable)
      # a v1-wrapped DEK still unwraps after rotation
      expect(provider.unwrap(wrapped: wrapped_v1.bytes, version: "v1", aad:)).to eq(dek)
    end

    it "a retired version cannot be the active version" do
      provider.retire!("v1")
      expect { provider.active_version }.to raise_error(err) { |e| expect(e.reason).to eq(:key_unavailable) }
    end

    it "a destroyed version cannot unwrap and reports :destroyed" do
      wrapped = provider.wrap(dek:, aad:)
      provider.destroy!("v1")

      expect(provider.status("v1")).to eq(:destroyed)
      expect { provider.unwrap(wrapped: wrapped.bytes, version: "v1", aad:) }
        .to raise_error(err) { |e| expect(e.reason).to eq(:key_destroyed) }
    end
  end
end
