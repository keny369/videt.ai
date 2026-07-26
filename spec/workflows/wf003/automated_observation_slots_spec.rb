# frozen_string_literal: true

require "rails_helper"

# S-05-007 — the fixed automated observation slot schedule as a pure value module
# (SCORE_EVIDENCE_MODEL.md :151; contracts/S-05.json MTX-028). The ten due offsets and
# the half-open windows they define; the boundary rule "earlier slot closed, later slot
# open" is the exclusive upper bound of each window.
RSpec.describe Workflows::Wf003::AutomatedObservationSlots do
  it "lists exactly the ten ratified due offsets in ascending order" do
    expect(described_class.offsets_minutes).to eq([0, 5, 15, 30, 60, 120, 240, 480, 960, 1380])
  end

  it "recognises each ratified offset as a slot and nothing else" do
    described_class.offsets_minutes.each { |m| expect(described_class.slot?(m)).to be(true) }
    [-1, 1, 7, 1381, 1440].each { |m| expect(described_class.slot?(m)).to be(false) }
  end

  it "gives each slot the next offset as its exclusive window upper bound" do
    expect(described_class.window_end_minutes(0)).to eq(5)
    expect(described_class.window_end_minutes(5)).to eq(15)
    expect(described_class.window_end_minutes(60)).to eq(120)
    expect(described_class.window_end_minutes(960)).to eq(1380)
  end

  it "ends the final slot's window at expiry (1,440 minutes), so the windows tile the lifetime" do
    expect(described_class.window_end_minutes(1380)).to eq(described_class::EXPIRY_OFFSET_MINUTES)
    expect(described_class::EXPIRY_OFFSET_MINUTES).to eq(1440)
    # No gap, no overlap: each window's end is the next window's start, up to expiry.
    offsets = described_class.offsets_minutes
    ends = offsets.map { |m| described_class.window_end_minutes(m) }
    expect(ends).to eq(offsets.drop(1) + [1440])
  end

  it "raises for a value that is not a due offset" do
    expect { described_class.window_end_minutes(7) }.to raise_error(ArgumentError, /not an automated slot offset/)
  end
end
