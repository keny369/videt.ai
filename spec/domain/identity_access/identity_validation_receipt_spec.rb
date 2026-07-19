# frozen_string_literal: true

require "rails_helper"

RSpec.describe IdentityAccess::Domain::IdentityValidationReceipt, type: :model,
               acceptance_ids: ["AC-CAP-001"], test_types: ["TYP-SEC"] do
  NOW = Time.utc(2026, 7, 20, 10, 0, 0)

  def receipt(overrides = {})
    described_class.new(**{
      receipt_id: SecureRandom.uuid_v7, purpose: "bootstrap_grant_request",
      validated_at: NOW, expires_at: NOW + 600, email_verified: true,
      issuer_key: "https://id.example/oidc", schema_version: "onboarding-interim-v1",
      bootstrap_principal_digest: "ab" * 32, context_org: SecureRandom.uuid_v7
    }.merge(overrides))
  end

  it "accepts a fresh, verified, purpose-matching receipt" do
    expect(receipt.grant_request_reason(now_utc: NOW)).to be_nil
  end

  it "rejects an unsupported issuer first" do
    expect(receipt(issuer_key: "https://evil.example").grant_request_reason(now_utc: NOW))
      .to eq("identity_issuer_unsupported")
  end

  it "rejects an unsupported schema" do
    expect(receipt(schema_version: "onboarding-v2").grant_request_reason(now_utc: NOW))
      .to eq("identity_schema_unsupported")
  end

  it "rejects a purpose mismatch" do
    expect(receipt(purpose: "existing_account_sign_in").grant_request_reason(now_utc: NOW))
      .to eq("identity_receipt_purpose_mismatch")
  end

  it "rejects an unverified email" do
    expect(receipt(email_verified: false).grant_request_reason(now_utc: NOW))
      .to eq("identity_email_unverified")
  end

  it "accepts strictly before expiry and rejects at the boundary and after (expiry wins at equality)" do
    expect(receipt.grant_request_reason(now_utc: NOW + 600 - 1)).to be_nil
    expect(receipt.grant_request_reason(now_utc: NOW + 600)).to eq("identity_receipt_expired")
    expect(receipt.grant_request_reason(now_utc: NOW + 600 + 1)).to eq("identity_receipt_expired")
  end
end
