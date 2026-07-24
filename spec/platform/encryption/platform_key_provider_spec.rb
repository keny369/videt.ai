# frozen_string_literal: true

require "rails_helper"

# F-02 Envelope Encryption — the production KeyProvider (FOUNDATION-002), unit-tested with
# the metadata boundary faked and the wrapping-key material injected, so the provider's
# logic (active version, fingerprint verification, typed failures) is proven with no DB.
RSpec.describe Platform::Encryption::PlatformKeyProvider, type: :model do
  let(:provider_id) { "platform-keyring" }
  let(:key) { Platform::Encryption::Aes256Gcm.random_key }
  let(:metadata) { EncryptionSupport::FakeMetadataStore.new }
  let(:key_source) { Platform::Encryption::DeploymentKeySource.new(keys: { provider_id => { "v1" => key } }) }
  let(:provider) { described_class.new(id: provider_id, metadata:, key_source:) }
  let(:aad) { "canonical-aad".b }
  let(:err) { Platform::Encryption::Error }

  before { metadata.register("v1", key) }

  it_behaves_like "a KeyProvider"

  def reason(sym, &block) = raise_error(err) { |e| expect(e.reason).to eq(sym) }

  describe "resolution failures are typed and fail closed" do
    it "is key_unavailable when no version is active" do
      metadata.clear_active
      expect { provider.active_version }.to reason(:key_unavailable)
    end

    it "is key_unavailable when the deployment source lacks the material" do
      empty = described_class.new(id: provider_id, metadata:, key_source: Platform::Encryption::DeploymentKeySource.new(keys: {}))
      expect { empty.wrap(dek: key, aad:) }.to reason(:key_unavailable)
    end

    it "refuses to encrypt under a non-active version (key_retired_for_encryption)" do
      metadata.set_state("v1", "retired") # active pointer still on v1: a resolve/describe race
      expect { provider.wrap(dek: key, aad:) }.to reason(:key_retired_for_encryption)
    end

    it "refuses to unwrap a destroyed version" do
      wrapped = provider.wrap(dek: key, aad:)
      metadata.set_state("v1", "destroyed")
      expect { provider.unwrap(wrapped: wrapped.bytes, version: "v1", aad:) }.to reason(:key_destroyed)
    end

    it "treats a fingerprint mismatch as a provider_failure (deployment misconfiguration)" do
      wrong = described_class.new(
        id: provider_id, metadata:,
        key_source: Platform::Encryption::DeploymentKeySource.new(keys: { provider_id => { "v1" => Platform::Encryption::Aes256Gcm.random_key } })
      )
      expect { wrong.wrap(dek: key, aad:) }.to reason(:provider_failure)
    end
  end

  describe "#status maps lifecycle state" do
    it "reports usable / retired / destroyed / unknown" do
      expect(provider.status("v1")).to eq(:usable)
      metadata.set_state("v1", "retired")
      expect(provider.status("v1")).to eq(:retired)
      metadata.set_state("v1", "destroyed")
      expect(provider.status("v1")).to eq(:destroyed)
      expect(provider.status("v9")).to eq(:unknown)
    end
  end

  describe "a retired version still decrypts" do
    it "unwraps a DEK wrapped before the version was retired" do
      wrapped = provider.wrap(dek: key, aad:)
      metadata.set_state("v1", "retired")
      expect(provider.unwrap(wrapped: wrapped.bytes, version: "v1", aad:)).to eq(key)
    end
  end
end
