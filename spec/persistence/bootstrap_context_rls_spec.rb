# frozen_string_literal: true

require "rails_helper"

# Proves the pretenant security posture for the WF-001 grant path: the runtime
# role is forced through proof-validated RLS, cannot forge context with a raw SET,
# cannot reach another principal's rows, and cannot read the restricted receipt
# store at all. This is the property TESTING_ARCHITECTURE.md requires be proven
# independently of any application check.
RSpec.describe "Bootstrap context RLS", type: :persistence do
  self.use_transactional_tests = false # we drive real transactions to test SET LOCAL scoping

  let(:conn) { ActiveRecord::Base.connection }

  after { ReceiptMinter.truncate_all }

  def hexlit(bytes) = "decode('#{bytes.unpack1('H*')}','hex')"

  def enter_context(receipt_digest)
    conn.execute("SELECT * FROM f1_enter_bootstrap_context(#{hexlit(receipt_digest)}, gen_random_uuid())")
  end

  def insert_grant(principal_digest)
    id = SecureRandom.uuid_v7
    conn.execute(<<~SQL)
      INSERT INTO bootstrap_grants
        (id, created_at, updated_at, correlation_id, causation_id,
         bootstrap_principal_digest, allowed_action, issuer_service_identity_id, policy_version,
         issued_at, expires_at, state)
      VALUES
        ('#{id}', now(), now(), gen_random_uuid(), gen_random_uuid(),
         #{hexlit(principal_digest)}, 'organization.bootstrap', gen_random_uuid(), 'onboarding-interim-v1',
         now(), now() + interval '15 minutes', 'issued')
    SQL
    id
  end

  def grant_count = conn.select_value("SELECT count(*) FROM bootstrap_grants").to_i

  it "denies the runtime role any direct access to the restricted receipt store" do
    expect { conn.select_value("SELECT count(*) FROM identity_receipt_nonces") }
      .to raise_error(ActiveRecord::StatementInvalid, /permission denied/)
  end

  it "hides every grant when no context is established" do
    receipt = ReceiptMinter.mint_bootstrap_grant_receipt(validated_at: Time.now.utc)
    conn.transaction do
      enter_context(receipt[:receipt_digest])
      insert_grant(receipt[:principal_digest])
    end
    # New transaction, no context: RLS hides the row.
    conn.transaction { expect(grant_count).to eq(0) }
  end

  it "shows a principal only its own grant, never another principal's" do
    a = ReceiptMinter.mint_bootstrap_grant_receipt(validated_at: Time.now.utc)
    b = ReceiptMinter.mint_bootstrap_grant_receipt(validated_at: Time.now.utc)
    conn.transaction { enter_context(a[:receipt_digest]); insert_grant(a[:principal_digest]) }
    conn.transaction { enter_context(b[:receipt_digest]); insert_grant(b[:principal_digest]) }

    conn.transaction do
      enter_context(a[:receipt_digest])
      expect(grant_count).to eq(1)
      expect(conn.select_value("SELECT encode(bootstrap_principal_digest,'hex') FROM bootstrap_grants"))
        .to eq(a[:principal_digest].unpack1("H*"))
    end
  end

  it "rejects a forged context: a raw SET without a valid proof yields no principal" do
    receipt = ReceiptMinter.mint_bootstrap_grant_receipt(validated_at: Time.now.utc)
    conn.transaction { enter_context(receipt[:receipt_digest]); insert_grant(receipt[:principal_digest]) }

    conn.transaction do
      # Attacker sets the principal digest directly but cannot produce app.f1_proof.
      conn.execute("SET LOCAL app.bootstrap_principal_digest = '#{receipt[:principal_digest].unpack1('H*')}'")
      conn.execute("SET LOCAL app.context_org = '00000000-0000-0000-0000-000000000000'")
      expect(conn.select_value("SELECT f1_current_bootstrap_principal()")).to be_nil
      expect(grant_count).to eq(0)
    end
  end

  it "scopes context to the transaction: it does not survive commit onto a pooled connection" do
    receipt = ReceiptMinter.mint_bootstrap_grant_receipt(validated_at: Time.now.utc)
    conn.transaction { enter_context(receipt[:receipt_digest]) }
    conn.transaction do
      expect(conn.select_value("SELECT f1_current_context_org()")).to be_nil
      expect(conn.select_value("SELECT f1_current_bootstrap_principal()")).to be_nil
    end
  end

  it "forbids inserting a grant for a principal other than the established context" do
    a = ReceiptMinter.mint_bootstrap_grant_receipt(validated_at: Time.now.utc)
    b = ReceiptMinter.mint_bootstrap_grant_receipt(validated_at: Time.now.utc)
    expect do
      conn.transaction do
        enter_context(a[:receipt_digest])
        insert_grant(b[:principal_digest]) # WITH CHECK denies a cross-principal write
      end
    end.to raise_error(ActiveRecord::StatementInvalid, /row-level security/)
  end
end
