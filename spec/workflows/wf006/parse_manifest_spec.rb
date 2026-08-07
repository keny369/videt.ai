# frozen_string_literal: true

require "rails_helper"

# The ordered parse manifest and its five invalidities (WORKFLOW_SPECIFICATIONS.md :470).
#
# Each invalidity gets its own example because :470 ends "an implementation cannot silently
# drop it" — the failure mode being guarded against is a manifest that narrows itself to the
# members that look right, so what matters is that each case REFUSES rather than shrinks.
RSpec.describe Workflows::Wf006::ParseManifest, type: :model do
  let(:org) { "11111111-1111-4111-8111-111111111111" }

  def tuple(overrides = {})
    {
      "organization_id" => org, "project_id" => "p1", "source_id" => "s1", "crawl_id" => "c1",
      "ingestion_job_id" => "j1", "document_id" => "d1", "input_evidence_id" => "e1",
      "canonical_url" => "https://example.com/", "media_type" => "text/html",
      "content_digest" => "aa" * 32, "document_content_digest" => "aa" * 32,
      "data_classification" => "public", "source_root" => true
    }.merge(overrides)
  end

  def build(rows, succeeded: nil)
    described_class.build(rows:, organization_id: org,
                          succeeded_ingestion_job_ids: succeeded || rows.map { |r| r["ingestion_job_id"] })
  end

  describe "a valid manifest" do
    it "orders by Source ID, then canonical URL bytes, then Document ID" do
      rows = [
        tuple("source_id" => "s2", "document_id" => "d3", "ingestion_job_id" => "j3", "canonical_url" => "https://b/"),
        tuple("source_id" => "s1", "document_id" => "d2", "ingestion_job_id" => "j2", "canonical_url" => "https://z/"),
        tuple("source_id" => "s1", "document_id" => "d1", "ingestion_job_id" => "j1", "canonical_url" => "https://a/")
      ]

      manifest = build(rows)

      expect(manifest).to be_valid
      expect(manifest.entries.map { |e| e["document_id"] }).to eq(%w[d1 d2 d3])
    end

    it "compares URLs as bytes, so the order does not depend on database collation" do
      rows = [
        tuple("document_id" => "d2", "ingestion_job_id" => "j2", "canonical_url" => "https://example.com/Z"),
        tuple("document_id" => "d1", "ingestion_job_id" => "j1", "canonical_url" => "https://example.com/a")
      ]

      # Byte order puts uppercase Z (0x5A) before lowercase a (0x61); a locale-aware
      # collation would not, and would seal a different snapshot hash on another server.
      expect(build(rows).entries.map { |e| e["document_id"] }).to eq(%w[d2 d1])
    end

    it "reports which entries are Source roots" do
      rows = [tuple, tuple("document_id" => "d2", "ingestion_job_id" => "j2", "source_root" => false)]

      expect(build(rows).source_root_entries.map { |e| e["document_id"] }).to eq(["d1"])
    end
  end

  describe "the five invalidities" do
    it "refuses a manifest tuple missing a required member" do
      manifest = build([tuple("input_evidence_id" => nil)])

      expect(manifest).not_to be_valid
      expect(manifest.invalid_reason).to eq("input_manifest_invalid")
      expect(manifest.invalid_detail).to start_with("manifest_tuple_incomplete")
      expect(manifest.entries).to be_empty
    end

    it "refuses a duplicate Document rather than de-duplicating it" do
      manifest = build([tuple, tuple("ingestion_job_id" => "j2")])

      expect(manifest.invalid_detail).to eq("manifest_duplicate_document:d1")
    end

    it "refuses a cross-Organization reference" do
      manifest = build([tuple, tuple("document_id" => "d2", "ingestion_job_id" => "j2",
                                     "organization_id" => "22222222-2222-4222-8222-222222222222")])

      expect(manifest.invalid_detail).to eq("manifest_cross_organization_reference:d2")
    end

    it "refuses a manifest/content-digest mismatch" do
      manifest = build([tuple("document_content_digest" => "bb" * 32)])

      expect(manifest.invalid_detail).to eq("manifest_content_digest_mismatch:d1")
    end

    it "refuses a manifest that OMITS a succeeded IngestionJob" do
      # The omission is invisible from the manifest alone — it just looks smaller — so the
      # check compares against an independent reading of the succeeded set.
      manifest = build([tuple], succeeded: %w[j1 j2])

      expect(manifest.invalid_detail).to eq("manifest_omits_succeeded_ingestion_job:j2")
      expect(manifest.entries).to be_empty
    end

    it "reports the FIRST invalidity in the contract's order" do
      rows = [tuple("input_evidence_id" => nil), tuple("ingestion_job_id" => "j2")]

      expect(build(rows).invalid_detail).to start_with("manifest_tuple_incomplete")
    end
  end
end
