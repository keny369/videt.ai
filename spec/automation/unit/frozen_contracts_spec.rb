# frozen_string_literal: true

require_relative "../automation_helper"

# Frozen-foundation escalation with the ratified additive-exception rule
# (DECISIONS.md ADR-027/ADR-029). A purely-additive new-table grant to the runtime
# privilege manifest is a backwards-compatible extension and does NOT escalate; every
# other frozen change does, and the classifier fails closed. controller_unit check.
RSpec.describe AutonomousBuild::FrozenContracts do
  describe "path classification" do
    it "recognizes every frozen foundation surface" do
      %w[
        app/platform/outbound.rb app/platform/outbound/guarded_http_client.rb
        app/platform/encryption.rb app/platform/encryption/envelope_cipher.rb
        app/platform/evidence.rb app/platform/scheduled_actions/store.rb
        app/platform/background_execution.rb
        spec/architecture/encryption_single_surface_spec.rb
        lib/f1/runtime_grants.rb
      ].each { |p| expect(described_class.frozen_path?(p)).to be(true), p }
      expect(described_class.frozen_path?("app/workflows/wf003/handlers/expire_verification_request.rb")).to be(false)
    end

    it "permits the additive exception only for the runtime privilege manifest" do
      expect(described_class.additive_exception_path?("lib/f1/runtime_grants.rb")).to be(true)
      expect(described_class.additive_exception_path?("app/platform/encryption.rb")).to be(false)
    end
  end

  describe ".additive_grant_change?" do
    def diff(added: [], removed: [])
      body = +"diff --git a/lib/f1/runtime_grants.rb b/lib/f1/runtime_grants.rb\n@@ -1,1 +1,1 @@\n"
      removed.each { |l| body << "-#{l}\n" }
      added.each { |l| body << "+#{l}\n" }
      body
    end

    it "accepts a purely-additive least-privilege new-table grant with comments" do
      d = diff(added: ["      # S-06 scope table", '      "source_scope_policies"           => "SELECT, INSERT, UPDATE",', ""])
      expect(described_class.additive_grant_change?(d)).to be(true)
    end

    it "rejects a grant that introduces DELETE" do
      d = diff(added: ['      "danger"                          => "SELECT, INSERT, DELETE",'])
      expect(described_class.additive_grant_change?(d)).to be(false)
    end

    it "rejects any change that removes or modifies an existing line" do
      expect(described_class.additive_grant_change?(diff(removed: ['      "sources" => "SELECT, INSERT",']))).to be(false)
      modify = diff(removed: ['      "sources" => "SELECT, INSERT, UPDATE",'],
                    added: ['      "sources" => "SELECT, INSERT, UPDATE, DELETE",'])
      expect(described_class.additive_grant_change?(modify)).to be(false)
    end

    it "rejects an added line that is not a grant entry or comment (a code change)" do
      expect(described_class.additive_grant_change?(diff(added: ["    RUNTIME_ROLE = \"f1_admin\""]))).to be(false)
    end

    it "rejects an empty or nil diff (nothing proven additive)" do
      expect(described_class.additive_grant_change?("")).to be(false)
      expect(described_class.additive_grant_change?(nil)).to be(false)
    end
  end

  describe ".escalating_frozen_changes" do
    let(:additive) { diff_added('      "verification_attempts" => "SELECT, INSERT, UPDATE",') }
    let(:with_delete) { diff_added('      "verification_attempts" => "SELECT, INSERT, DELETE",') }

    def diff_added(line)
      "diff --git a/lib/f1/runtime_grants.rb b/lib/f1/runtime_grants.rb\n@@ -1,0 +1,1 @@\n+#{line}\n"
    end

    it "does NOT escalate a purely-additive runtime_grants change" do
      escalating = described_class.escalating_frozen_changes(
        ["lib/f1/runtime_grants.rb", "app/workflows/wf003/x.rb"],
        diff_provider: ->(_p) { additive }
      )
      expect(escalating).to be_empty
    end

    it "escalates a runtime_grants change that introduces DELETE" do
      escalating = described_class.escalating_frozen_changes(
        ["lib/f1/runtime_grants.rb"], diff_provider: ->(_p) { with_delete }
      )
      expect(escalating).to eq(["lib/f1/runtime_grants.rb"])
    end

    it "fails closed and escalates when no diff provider can prove the change additive" do
      expect(described_class.escalating_frozen_changes(["lib/f1/runtime_grants.rb"]))
        .to eq(["lib/f1/runtime_grants.rb"])
    end

    it "always escalates a foundation façade change, ignoring any diff provider" do
      escalating = described_class.escalating_frozen_changes(
        ["app/platform/encryption.rb"], diff_provider: ->(_p) { "+  # harmless comment\n" }
      )
      expect(escalating).to eq(["app/platform/encryption.rb"])
    end

    it "leaves non-frozen paths out of the escalation set entirely" do
      expect(described_class.escalating_frozen_changes(["app/workflows/wf003/x.rb"])).to be_empty
    end
  end
end
