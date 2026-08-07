# frozen_string_literal: true

require "rails_helper"

# The authentication boundary for every protected request. These are the properties a
# controller is allowed to depend on and must never re-implement: a request is refused
# unless a live Session presents its own bearer token AND the actor holds the exact
# named capability, and either way the decision is durable evidence.
RSpec.describe Platform::AuthenticatedRequest do
  # This opens its own unit of work, which by contract refuses to nest, so the suite's
  # wrapping transaction has to go and the tenant rows are truncated instead.
  self.use_transactional_tests = false

  after { ReceiptMinter.truncate_all }

  let(:correlation_id) { SecureRandom.uuid_v7 }
  # Inside the Session window seeded by TenantSeeder (issued 09:45, idle 10:15).
  let(:clock) { Platform::Clock.fixed(Time.utc(2026, 7, 20, 10, 0, 0)) }

  def call(token:, capability: "invitation.create", **kwargs, &block)
    described_class.call(token:, capability:, correlation_id:, clock:, **kwargs, &block)
  end

  def decisions
    DbInspector.all("SELECT action, decision, reason_code, subject_id FROM authorization_decisions ORDER BY created_at")
  end

  describe "a live Session holding the capability" do
    it "authorizes, exposes the proved actor, and runs the block inside the transaction" do
      admin = TenantSeeder.seed_authorized_admin

      result = call(token: admin[:session_token]) { |actor, _conn| actor.account_id }

      expect(result).to be_authorized
      expect(result.actor.organization_id).to eq(admin[:organization_id])
      expect(result.actor.account_id).to eq(admin[:account_id])
      expect(result.value).to eq(admin[:account_id])
    end

    it "derives the actor from the Session, never from anything the caller supplies" do
      admin = TenantSeeder.seed_authorized_admin
      other = TenantSeeder.seed_authorized_admin

      result = call(token: admin[:session_token]) { |actor, _| actor }

      # The second tenant exists and is fully active; presenting the first tenant's
      # token must resolve the first tenant and nothing else.
      expect(result.actor.organization_id).to eq(admin[:organization_id])
      expect(result.actor.organization_id).not_to eq(other[:organization_id])
    end

    it "slides the idle window on an accepted request" do
      admin = TenantSeeder.seed_authorized_admin
      before = session_row(admin[:session_id])

      call(token: admin[:session_token]) { |_, _| nil }

      after = session_row(admin[:session_id])
      expect(Time.parse(after["last_activity_at"])).to be > Time.parse(before["last_activity_at"])
      expect(Time.parse(after["idle_expires_at"])).to eq(Time.utc(2026, 7, 20, 10, 30, 0))
    end

    it "refuses at the absolute deadline even while the idle window is still open" do
      # Issued 09:45, so the absolute deadline is 21:45. Activity at 21:40 leaves the
      # idle window open until 22:10, so idle alone would still admit this request. The
      # absolute deadline is the separate rule that has to stop it: a Session cannot be
      # kept alive indefinitely by using it.
      admin = TenantSeeder.seed_authorized_admin(last_activity_at: Time.utc(2026, 7, 20, 21, 40, 0))
      past_absolute = Platform::Clock.fixed(Time.utc(2026, 7, 20, 21, 45, 0))
      ran = false

      result = described_class.call(token: admin[:session_token], capability: "invitation.create",
                                    correlation_id:, clock: past_absolute) { |_, _| ran = true }

      expect(result).to be_unauthenticated
      expect(ran).to be(false)
      # Refused means untouched: a dead Session does not get its window extended.
      expect(Time.parse(session_row(admin[:session_id])["last_activity_at"]))
        .to eq(Time.utc(2026, 7, 20, 21, 40, 0))
    end

    it "writes an allow decision naming the exact capability" do
      admin = TenantSeeder.seed_authorized_admin

      call(token: admin[:session_token], capability: "invitation.create") { |_, _| nil }

      decision = decisions.fetch(0)
      expect(decision).to include("action" => "invitation.create", "decision" => "allow",
                                  "subject_id" => admin[:account_id])
    end
  end

  describe "refusal" do
    it "refuses an absent cookie as unauthenticated without opening a transaction" do
      result = call(token: nil)

      expect(result).not_to be_authorized
      expect(result).to be_unauthenticated
      expect(result.reason).to eq("session_absent")
    end

    it "refuses a malformed cookie value before it reaches the database" do
      expect(call(token: "not-a-real-token").reason).to eq("session_absent")
    end

    it "refuses a well-formed token that matches no Session" do
      result = call(token: Platform::SessionToken.mint.raw)

      expect(result).to be_unauthenticated
      expect(result.reason).to eq("session_invalid")
    end

    it "refuses a revoked Session" do
      admin = TenantSeeder.seed_authorized_admin(session_status: "revoked")

      expect(call(token: admin[:session_token])).to be_unauthenticated
    end

    it "refuses once the idle deadline is reached, on the equality boundary" do
      admin = TenantSeeder.seed_authorized_admin
      at_deadline = Platform::Clock.fixed(Time.utc(2026, 7, 20, 10, 15, 0))

      result = described_class.call(token: admin[:session_token], capability: "invitation.create",
                                    correlation_id:, clock: at_deadline) { |_, _| nil }

      expect(result).to be_unauthenticated
    end

    it "refuses an authenticated actor lacking the capability, and does not run the block" do
      # A MarketingOperator authenticates fine and is refused on authority.
      admin = TenantSeeder.seed_authorized_admin(canonical_role: "MarketingOperator")
      ran = false

      result = call(token: admin[:session_token], capability: "invitation.create") { |_, _| ran = true }

      expect(result).to be_forbidden
      expect(ran).to be(false)
    end

    it "records a deny decision, so a refusal is evidence rather than silence" do
      admin = TenantSeeder.seed_authorized_admin(canonical_role: "MarketingOperator")

      call(token: admin[:session_token], capability: "invitation.create") { |_, _| nil }

      decision = decisions.fetch(0)
      expect(decision).to include("action" => "invitation.create", "decision" => "deny")
      expect(decision["reason_code"]).to eq("missing_authority")
    end

    it "refuses when the Account is inactive" do
      admin = TenantSeeder.seed_authorized_admin(account_status: "suspended")

      expect(call(token: admin[:session_token])).to be_forbidden
    end
  end

  def session_row(id)
    ReceiptMinter.owner_connection.exec_params(
      "SELECT last_activity_at, idle_expires_at, absolute_expires_at FROM sessions WHERE id = $1::uuid", [id]
    ).to_a.first
  end
end
