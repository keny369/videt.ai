# frozen_string_literal: true

require "rails_helper"

# F-02 Envelope Encryption — the versioned envelope serialization (FOUNDATION-002).
RSpec.describe Platform::Encryption::Envelope, type: :model do
  let(:err) { Platform::Encryption::Error }

  def sample
    described_class.new(
      format_version: described_class::FORMAT_VERSION,
      algorithm: described_class::ALGORITHM,
      key_provider: "in-memory-test",
      wrapping_key_version: "v1",
      wrapped_dek: "wrapped-dek-bytes".b,
      ciphertext: "cipher".b,
      nonce: ("n" * 12).b,
      authentication_tag: ("t" * 16).b,
      aad_schema_version: "record-aad-v1"
    )
  end

  it "round-trips through serialize/deserialize preserving every field" do
    restored = described_class.deserialize(sample.serialize)
    expect(restored).to eq(sample)
  end

  it "serializes to deterministic canonical bytes" do
    expect(sample.serialize).to eq(sample.serialize)
    expect(sample.serialize.encoding).to eq(Encoding::ASCII_8BIT)
  end

  it "rejects a non-JSON blob as malformed_envelope" do
    expect { described_class.deserialize("not json".b) }
      .to raise_error(err) { |e| expect(e.reason).to eq(:malformed_envelope) }
  end

  it "rejects a wrong format_version as unsupported_format" do
    tampered = JSON.parse(sample.serialize).merge("format_version" => 2)
    expect { described_class.deserialize(JSON.generate(tampered)) }
      .to raise_error(err) { |e| expect(e.reason).to eq(:unsupported_format) }
  end

  it "rejects a missing field as malformed_envelope" do
    without_nonce = JSON.parse(sample.serialize).except("nonce")
    expect { described_class.deserialize(JSON.generate(without_nonce)) }
      .to raise_error(err) { |e| expect(e.reason).to eq(:malformed_envelope) }
  end

  it "rejects invalid base64 in a binary field as malformed_envelope" do
    bad = JSON.parse(sample.serialize).merge("ciphertext" => "!!!not-base64!!!")
    expect { described_class.deserialize(JSON.generate(bad)) }
      .to raise_error(err) { |e| expect(e.reason).to eq(:malformed_envelope) }
  end
end
