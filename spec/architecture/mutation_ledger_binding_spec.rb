# frozen_string_literal: true

require "rails_helper"
require_relative "../../automation/lib/autonomous_build/mutation_harness"

# THE LEDGER VERIFIER'S OWN PROOF (D5 family 5; R10-5, R10-19).
#
# A ledger is evidence only if a false row cannot survive it. Each example below constructs one of
# the ways a row can be false and requires the repository-contained verifier to reject it.
RSpec.describe AutonomousBuild::MutationHarness, type: :architecture do
  LEDGER_ROOT = Rails.root.to_s

  # A row that is true right now, sealed the way the generator seals it.
  def truthful_row(overrides = {})
    file = "app/platform/run_deadline.rb"
    proof = "spec/platform/run_deadline_spec.rb"
    row = {
      "id" => "zz-truthful", "file" => file, "from" => "def present? = true", "to" => "def present? = false",
      "proof" => proof, "expectation" => "kill", "verdict" => "killed",
      "result" => "5 examples, 1 failure", "failing_examples" => ["spec/platform/run_deadline_spec.rb:1"],
      "failure_digest" => "d" * 64, "equivalence_reason" => nil,
      "commit" => "0" * 40, "restored" => true,
      "file_sha256" => Digest::SHA256.hexdigest(File.read(File.join(LEDGER_ROOT, file))),
      "proof_sha256" => described_class.proof_digest({ "proof" => proof }, root: LEDGER_ROOT)
    }.merge(overrides)
    described_class.seal(row)
  end

  it "accepts a row whose binding matches the tree it was measured against" do
    expect { described_class.verify_bindings!([truthful_row], root: LEDGER_ROOT) }.not_to raise_error
  end

  it "rejects a FABRICATED verdict — a row sealed over different contents than it carries" do
    forged = truthful_row.merge("verdict" => "killed", "failing_examples" => ["spec/made_up_spec.rb:1"])
    expect { described_class.verify_bindings!([forged], root: LEDGER_ROOT) }
      .to raise_error(/fabricated, transplanted or edited/)
  end

  it "rejects a STALE verdict — the production file has changed since it was measured" do
    stale = truthful_row("file_sha256" => "0" * 64)
    expect { described_class.verify_bindings!([stale], root: LEDGER_ROOT) }.to raise_error(/verdict is stale/)
  end

  it "rejects a verdict TRANSPLANTED from another mutation" do
    a = truthful_row
    b = truthful_row("id" => "zz-other", "from" => "def inspect", "to" => "def inspect2")
    transplanted = b.merge("binding_sha256" => a["binding_sha256"])
    expect { described_class.verify_bindings!([transplanted], root: LEDGER_ROOT) }
      .to raise_error(/fabricated, transplanted or edited/)
  end

  it "rejects a row whose PROOF bytes have changed since the verdict was measured" do
    moved = truthful_row("proof_sha256" => "1" * 64)
    expect { described_class.verify_bindings!([moved], root: LEDGER_ROOT) }
      .to raise_error(/the proof that failed is not the proof that exists/)
  end

  it "rejects a `broken` verdict, which proves nothing" do
    broken = truthful_row("verdict" => "broken")
    expect { described_class.verify_bindings!([broken], root: LEDGER_ROOT) }
      .to raise_error(/the run aborted before any example ran/)
  end

  it "rejects a kill with no failing example identities" do
    vague = truthful_row("failing_examples" => [])
    expect { described_class.verify_bindings!([vague], root: LEDGER_ROOT) }
      .to raise_error(/no failing example identities/)
  end

  it "rejects a row whose tree was left DIRTY after the replay" do
    dirty = truthful_row("restored" => false)
    expect { described_class.verify_bindings!([dirty], root: LEDGER_ROOT) }
      .to raise_error(/restoration was not verified/)
  end

  it "rejects an equivalence claim with no executable justification" do
    hand_waved = truthful_row("expectation" => "equivalent", "verdict" => "survived",
                              "equivalence_reason" => "it looks the same")
    expect { described_class.verify_bindings!([hand_waved], root: LEDGER_ROOT) }
      .to raise_error(/no independently executable justification/)
  end

  it "rejects a row carrying no binding at all" do
    unbound = truthful_row.tap { |r| r.delete("binding_sha256") }
    expect { described_class.verify_bindings!([unbound], root: LEDGER_ROOT) }
      .to raise_error(/bound to nothing/)
  end

  describe "applicability, which the binding does not replace" do
    it "rejects a mutation that no longer applies" do
      gone = [{ "id" => "zz-gone", "file" => "app/no/such/file.rb", "from" => "x", "to" => "y",
                "proof" => "spec/platform/run_deadline_spec.rb", "expectation" => "kill" }]
      expect { described_class.verify_applicable!(gone, root: LEDGER_ROOT) }.to raise_error(/not replayable/)
    end

    it "rejects a mutation that would land at an IDENTICAL BUT WRONG site" do
      # The shape that invalidated FU-44: several identical texts in one file, so an unscoped
      # substitution lands somewhere the record does not name.
      ambiguous = [{ "id" => "zz-ambiguous", "file" => "app/platform/entitlement/service.rb",
                     "from" => "now >= effective_deadline(r)", "to" => "now > effective_deadline(r)",
                     "proof" => "spec/platform/run_deadline_spec.rb", "expectation" => "kill" }]
      expect { described_class.verify_applicable!(ambiguous, root: LEDGER_ROOT) }
        .to raise_error(/occurrences of its `from` text/)
    end
  end
end
