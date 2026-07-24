# frozen_string_literal: true

require "rails_helper"

# F-03 Evidence Production — the single-surface architecture fitness check (FOUNDATION-003;
# owner rule 2026-07-25: "fail CI if anything except the canonical Evidence Producer can write
# evidence"). The same philosophy as outbound transport and encryption, applied to evidence:
# there is exactly one writer. This fails CI the moment production code outside the adapter
# references the internal EvidenceStore — the only path that appends Evidence. Consumers use
# Platform::Evidence.produce with a validated Record; test support (spec/) is not scanned.
RSpec.describe "Evidence single-surface fitness", type: :model do
  def in_adapter?(rel) = rel.start_with?("app/platform/evidence/") || rel == "app/platform/evidence.rb"

  # The single writer. Record and InvalidEvidence are public (consumers build/rescue them).
  def internal_classes
    { "EvidenceStore" => /\bEvidenceStore\b/ }
  end

  def production_files
    (Dir[Rails.root.join("app/**/*.rb")] + Dir[Rails.root.join("lib/**/*.rb")]).sort
  end

  def relative(path) = Pathname.new(path).relative_path_from(Rails.root).to_s

  def scan_outside_adapter(patterns)
    violations = []
    production_files.each do |path|
      rel = relative(path)
      next if in_adapter?(rel)

      File.read(path).each_line.with_index(1) do |line, number|
        next if line.lstrip.start_with?("#")

        patterns.each { |label, pattern| violations << "#{rel}:#{number} references #{label}" if line.match?(pattern) }
      end
    end
    violations
  end

  it "confines the single Evidence writer to the adapter — everyone else uses the producer" do
    violations = scan_outside_adapter(internal_classes)
    expect(violations).to be_empty, <<~MESSAGE
      Only the canonical Evidence producer may write Evidence (FOUNDATION-003 FROZEN contract).
      Reach it through Platform::Evidence.produce. These files write around the producer:
      #{violations.join("\n")}
    MESSAGE
  end

  it "offers a producer/reader surface only — no interpretation" do
    expect(Platform::Evidence).to respond_to(:produce)
    expect(Platform::Evidence).to respond_to(:get)
    expect(Platform::Evidence).to respond_to(:find_by_content_hash)
    # interpretation (scoring, validation heads, adjudication) is CAP-013/S-09, never here
    %i[score validate adjudicate evaluate interpret deduplicate supersede].each do |verb|
      expect(Platform::Evidence).not_to respond_to(verb)
    end
  end

  it "actually scans the tree it claims to" do
    expect(production_files.length).to be > 60
    expect(production_files).to include(a_string_ending_with("app/platform/evidence/evidence_store.rb"))
  end
end
