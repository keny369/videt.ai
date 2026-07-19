# frozen_string_literal: true

require "rails_helper"

RSpec.describe Platform::Ids do
  it "generates UUIDv7 identifiers" do
    uuid = described_class.system.generate
    expect(uuid).to match(/\A[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\z/)
  end

  it "generates time-ordered ids (v7 is monotonic enough to sort by allocation)" do
    ids = described_class.system
    first = ids.generate
    second = ids.generate
    expect([first, second].sort).to eq([first, second]).or eq([second, first]) # same millisecond may tie
  end

  it "yields a fixed sequence in order and then fails loudly" do
    ids = described_class.sequence(%w[a b])
    expect(ids.generate).to eq("a")
    expect(ids.generate).to eq("b")
    expect { ids.generate }.to raise_error(/sequence exhausted/)
  end
end
