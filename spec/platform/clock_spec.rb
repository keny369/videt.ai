# frozen_string_literal: true

require "rails_helper"

RSpec.describe Platform::Clock do
  it "returns the system time in UTC" do
    expect(described_class.system.now_utc.utc_offset).to eq(0)
  end

  it "freezes at a fixed instant, normalized to UTC, for deterministic tests" do
    instant = Time.new(2026, 7, 19, 10, 0, 0, "+10:00")
    clock = described_class.fixed(instant)
    expect(clock.now_utc).to eq(instant)
    expect(clock.now_utc.utc_offset).to eq(0)
    expect(clock.now_utc).to eq(clock.now_utc)
  end
end
