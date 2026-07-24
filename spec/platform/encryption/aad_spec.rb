# frozen_string_literal: true

require "rails_helper"

# F-02 Envelope Encryption — the AAD binding (FOUNDATION-002 §AAD). Canonicalisation must
# be deterministic; the binding fields are what make relocation fail authentication.
RSpec.describe Platform::Encryption::Aad, type: :model do
  def build(**overrides)
    described_class.for(**{
      application: "verification", record_type: "verification_request",
      record_id: "req-1", purpose: "challenge_token", tenant: "org-1"
    }.merge(overrides))
  end

  describe "canonicalisation is deterministic" do
    it "produces identical bytes for equal fields" do
      expect(build.canonical_bytes).to eq(build.canonical_bytes)
    end

    it "produces canonical, sorted-key JSON bytes" do
      bytes = build(tenant: nil).canonical_bytes
      expect(bytes.encoding).to eq(Encoding::ASCII_8BIT)
      # RFC 8785: keys sorted; tenant present as null
      expect(bytes).to eq(
        %({"application":"verification","purpose":"challenge_token","record_id":"req-1",) +
        %("record_type":"verification_request","schema_version":"record-aad-v1","tenant":null}).b
      )
    end

    it "changes the bytes when any binding field changes" do
      base = build.canonical_bytes
      expect(build(record_id: "req-2").canonical_bytes).not_to eq(base)
      expect(build(record_type: "other").canonical_bytes).not_to eq(base)
      expect(build(purpose: "other").canonical_bytes).not_to eq(base)
      expect(build(tenant: "org-2").canonical_bytes).not_to eq(base)
      expect(build(application: "crawl").canonical_bytes).not_to eq(base)
    end
  end

  describe "construction" do
    it "allows a nil tenant (not tenant-scoped)" do
      expect { build(tenant: nil) }.not_to raise_error
    end

    it "requires the location fields" do
      %i[application record_type record_id purpose].each do |field|
        expect { build(field => nil) }.to raise_error(ArgumentError)
        expect { build(field => "") }.to raise_error(ArgumentError)
      end
    end

    it "carries the schema version" do
      expect(build.schema_version).to eq("record-aad-v1")
    end
  end
end
