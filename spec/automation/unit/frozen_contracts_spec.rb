# frozen_string_literal: true

require_relative "../automation_helper"

# Frozen-foundation escalation with the ratified additive-exception rule
# (DECISIONS.md ADR-027/ADR-029). A PROVEN-SAFE additive new-table grant to the
# runtime privilege manifest is a backwards-compatible extension and does NOT
# escalate; a privilege-boundary change (a broad/destructive privilege, a widened or
# modified existing grant, a removal, or an unprovable change) DOES, and so does every
# other frozen path. The classifier fails closed. controller_unit check.
RSpec.describe AutonomousBuild::FrozenContracts do
  # A stand-in base manifest with two existing table keys.
  BASE = <<~RUBY
    TABLE_PRIVILEGES = {
      "sources"                   => "SELECT, INSERT, UPDATE",
      "role_assignment_approvals" => "SELECT, INSERT",
    }.freeze
  RUBY

  def diff(added: [], removed: [])
    body = +"diff --git a/lib/f1/runtime_grants.rb b/lib/f1/runtime_grants.rb\n@@ -1,1 +1,1 @@\n"
    removed.each { |l| body << "-#{l}\n" }
    added.each { |l| body << "+#{l}\n" }
    body
  end

  def entry(table, privs) = %(      "#{table}"                   => "#{privs}",)

  describe "path classification" do
    it "recognizes every frozen foundation surface and permits the exception only for runtime_grants" do
      %w[
        app/platform/outbound.rb app/platform/encryption.rb app/platform/encryption/envelope_cipher.rb
        app/platform/evidence.rb app/platform/scheduled_actions/store.rb app/platform/background_execution.rb
        spec/architecture/encryption_single_surface_spec.rb lib/f1/runtime_grants.rb
      ].each { |p| expect(described_class.frozen_path?(p)).to be(true), p }
      expect(described_class.frozen_path?("app/workflows/wf003/handlers/expire_verification_request.rb")).to be(false)
      expect(described_class.additive_exception_path?("lib/f1/runtime_grants.rb")).to be(true)
      expect(described_class.additive_exception_path?("app/platform/encryption.rb")).to be(false)
    end
  end

  describe ".additive_grant_change? — the allowlist and newness invariants" do
    it "accepts a genuinely-new least-privilege table grant with comments" do
      d = diff(added: ["      # S-06 scope table", entry("source_scope_policies", "SELECT, INSERT, UPDATE"), ""])
      expect(described_class.additive_grant_change?(d, base_content: BASE)).to be(true)
    end

    it "rejects ANY privilege beyond SELECT/INSERT/UPDATE (allowlist, not a DELETE denylist)" do
      ["SELECT, INSERT, DELETE", "ALL", "ALL PRIVILEGES", "SELECT, TRUNCATE", "SELECT, REFERENCES", "TRIGGER"].each do |privs|
        d = diff(added: [entry("danger", privs)])
        expect(described_class.additive_grant_change?(d, base_content: BASE)).to be(false), privs
      end
    end

    it "rejects a duplicate key that would silently widen an existing table's grant (no removal)" do
      d = diff(added: [entry("role_assignment_approvals", "SELECT, INSERT, UPDATE")]) # existing is SELECT, INSERT
      expect(described_class.additive_grant_change?(d, base_content: BASE)).to be(false)
    end

    it "rejects any removal or in-place modification of an existing line" do
      expect(described_class.additive_grant_change?(diff(removed: [entry("sources", "SELECT, INSERT, UPDATE")]), base_content: BASE)).to be(false)
      modify = diff(removed: [entry("sources", "SELECT, INSERT, UPDATE")], added: [entry("sources", "SELECT, INSERT, UPDATE, DELETE")])
      expect(described_class.additive_grant_change?(modify, base_content: BASE)).to be(false)
    end

    it "rejects an added non-grant/non-comment line, and an empty or nil diff" do
      expect(described_class.additive_grant_change?(diff(added: ['    RUNTIME_ROLE = "f1_admin"']), base_content: BASE)).to be(false)
      expect(described_class.additive_grant_change?("", base_content: BASE)).to be(false)
      expect(described_class.additive_grant_change?(nil, base_content: BASE)).to be(false)
    end

    it "fails closed when a grant is added but the base content is unavailable (newness unprovable)" do
      d = diff(added: [entry("brand_new", "SELECT, INSERT, UPDATE")])
      expect(described_class.additive_grant_change?(d, base_content: nil)).to be(false)
    end

    it "allows a comment-only change even without base content (grants nothing)" do
      expect(described_class.additive_grant_change?(diff(added: ["      # clarifying note"]), base_content: nil)).to be(true)
    end
  end

  describe ".escalating_frozen_changes" do
    def providers(diff_text, base: BASE)
      { diff_provider: ->(_p) { diff_text }, base_content_provider: ->(_p) { base } }
    end

    it "does NOT escalate a proven-safe additive runtime_grants change" do
      d = diff(added: [entry("verification_attempts", "SELECT, INSERT, UPDATE")])
      expect(described_class.escalating_frozen_changes(["lib/f1/runtime_grants.rb", "app/workflows/x.rb"], **providers(d))).to be_empty
    end

    it "escalates a broad/destructive or duplicate-key grant change" do
      [entry("verification_attempts", "ALL"), entry("sources", "SELECT, INSERT, UPDATE")].each do |line|
        d = diff(added: [line])
        expect(described_class.escalating_frozen_changes(["lib/f1/runtime_grants.rb"], **providers(d))).to eq(["lib/f1/runtime_grants.rb"])
      end
    end

    it "fails closed and escalates with no diff/base provider" do
      expect(described_class.escalating_frozen_changes(["lib/f1/runtime_grants.rb"])).to eq(["lib/f1/runtime_grants.rb"])
      d = diff(added: [entry("verification_attempts", "SELECT, INSERT, UPDATE")])
      expect(described_class.escalating_frozen_changes(["lib/f1/runtime_grants.rb"], diff_provider: ->(_p) { d })).to eq(["lib/f1/runtime_grants.rb"])
    end

    it "always escalates a foundation façade change, ignoring any diff provider" do
      expect(described_class.escalating_frozen_changes(["app/platform/encryption.rb"], **providers("+  # harmless\n"))).to eq(["app/platform/encryption.rb"])
    end

    it "leaves non-frozen paths out of the escalation set entirely" do
      expect(described_class.escalating_frozen_changes(["app/workflows/wf003/x.rb"])).to be_empty
    end
  end
end
