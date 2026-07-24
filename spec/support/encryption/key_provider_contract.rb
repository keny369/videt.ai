# frozen_string_literal: true

# The FOUNDATION-002 KeyProvider contract, as shared examples. Any provider — the
# in-memory test double and the production platform key ring — must satisfy it, so
# EnvelopeCipher can depend on the contract and never on a concrete provider.
#
# The including group provides `let(:provider)` and `let(:aad)` (any canonical AAD bytes).
RSpec.shared_examples "a KeyProvider" do
  let(:dek) { Platform::Encryption::Aes256Gcm.random_key }
  let(:err) { Platform::Encryption::Error }

  it "has a stable, non-empty string id recorded in envelopes" do
    expect(provider.id).to be_a(String)
    expect(provider.id).not_to be_empty
  end

  it "reports the active version as usable" do
    expect(provider.status(provider.active_version)).to eq(:usable)
  end

  it "wraps a DEK under the active version and round-trips it back" do
    wrapped = provider.wrap(dek:, aad:)
    expect(wrapped.version).to eq(provider.active_version)
    expect(provider.unwrap(wrapped: wrapped.bytes, version: wrapped.version, aad:)).to eq(dek)
  end

  it "does not leak the wrapping key: the wrapped bytes are not the DEK" do
    wrapped = provider.wrap(dek:, aad:)
    expect(wrapped.bytes).not_to include(dek)
    expect(wrapped.bytes.bytesize).to be > dek.bytesize
  end

  it "fails authentication when the AAD differs from the wrap AAD" do
    wrapped = provider.wrap(dek:, aad:)
    expect { provider.unwrap(wrapped: wrapped.bytes, version: wrapped.version, aad: "#{aad}-other".b) }
      .to raise_error(err) { |e| expect(e.reason).to eq(:authentication_failed) }
  end

  it "fails authentication when the wrapped bytes are tampered" do
    wrapped = provider.wrap(dek:, aad:)
    tampered = wrapped.bytes.dup
    tampered.setbyte(tampered.bytesize - 1, tampered.getbyte(tampered.bytesize - 1) ^ 0x01)
    expect { provider.unwrap(wrapped: tampered, version: wrapped.version, aad:) }
      .to raise_error(err) { |e| expect(e.reason).to eq(:authentication_failed) }
  end

  it "rejects an unknown version" do
    wrapped = provider.wrap(dek:, aad:)
    expect { provider.unwrap(wrapped: wrapped.bytes, version: "no-such-version", aad:) }
      .to raise_error(err) { |e| expect(e.reason).to eq(:key_version_unknown) }
  end

  it "reports :unknown for a version it has never held" do
    expect(provider.status("no-such-version")).to eq(:unknown)
  end
end
