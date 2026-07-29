# frozen_string_literal: true

require "rails_helper"

# `Platform::DerivedUuid` duplicates the database's `f1_bootstrap_principal_uuid` derivation, and
# its own comment justified that duplication by saying "the two implementations are pinned to each
# other by spec". Two ADR-026 lenses observed, correctly, that no such spec existed — the mitigation
# named in the code was fictional, which is worse than an unmitigated duplication because a reader
# stops looking.
#
# This is that spec. It compares the Ruby against the LIVE PL/pgSQL function rather than against a
# restatement of it, so a future edit to either side fails here instead of drifting silently into
# every limit event's `definition_versions`.
RSpec.describe Platform::DerivedUuid do
  def in_database(digest)
    DbInspector.connection
               .exec_params("SELECT f1_bootstrap_principal_uuid($1)", [{ value: digest, format: 1 }])
               .getvalue(0, 0)
  end

  # Fixed digests, not random ones: a property this small should fail the same way on every run.
  DIGESTS = {
    "all zero bytes" => ("\x00" * 32).b,
    "all high bytes" => ("\xff" * 32).b,
    "alternating" => (["a5"].pack("H*") * 32).b,
    "ascending" => (0...32).map(&:chr).join.b,
    "a real content digest" => Digest::SHA256.digest("crawl-policy-v1-global")
  }.freeze

  DIGESTS.each do |name, digest|
    it "agrees with the database for #{name}" do
      expect(described_class.v8(digest)).to eq(in_database(digest))
    end
  end

  it "stamps version 8 and the RFC 4122 variant, as the database does" do
    uuid = described_class.v8(("\xff" * 32).b)
    expect(uuid).to match(/\A\h{8}-\h{4}-8\h{3}-[89ab]\h{3}-\h{12}\z/)
  end

  it "is a pure function of the digest — the same bytes always give the same identity" do
    digest = Digest::SHA256.digest("stable")
    expect(described_class.v8(digest)).to eq(described_class.v8(digest))
  end

  it "refuses anything that is not a 32-byte digest, as the database does" do
    expect { described_class.v8("short") }.to raise_error(ArgumentError, /32-byte digest/)
    expect { described_class.v8(nil) }.to raise_error(ArgumentError, /32-byte digest/)
    expect { in_database("short") }.to raise_error(PG::RaiseException, /must be 32 bytes/)
  end

  it "pins the global Crawl Policy artifact identity the event stream depends on" do
    # `EffectiveLimits::GLOBAL_ARTIFACT_ID` reaches `definition_versions` on every limit event. A
    # governing-version reference that moved would name a different artifact run to run.
    expect(Workflows::Wf005::EffectiveLimits::GLOBAL_ARTIFACT_ID)
      .to eq(in_database(Workflows::Wf005::EffectiveLimits::GLOBAL_CONTENT_SHA256))
  end
end
