# frozen_string_literal: true

require "rails_helper"

# THE TAP COVERS EVERY DOOR, PROVEN AGAINST THE LIVE CLASS (round 9's proof-system audit).
#
# The audit named "sentinels that observe only one database execution API" as a defect class, and the
# governed-write sentinel was one: it hooked `exec_params` alone. That was complete only because
# nothing in `app/` happened to use another form — which is the same "complete because nobody has
# done it yet" that produced every other finding in this tranche.
RSpec.describe WireTap, type: :model do
  it "intercepts every statement-sending method PG::Connection actually defines" do
    # DERIVED FROM THE LIVE CLASS, not from a list this file maintains. A libpq upgrade that adds a
    # door fails the build rather than opening one silently.
    doors = PG::Connection.instance_methods.grep(/\A(a?sync_)?(exec|query|send_query)/)

    expect(described_class.intercepted).to match_array(doors & described_class::EXECUTION_METHODS)
    expect(doors - described_class::EXECUTION_METHODS).to be_empty,
                                                          "PG::Connection defines statement-sending " \
                                                          "methods the tap does not cover: " \
                                                          "#{(doors - described_class::EXECUTION_METHODS).inspect}"
  end

  it "publishes statements sent through a door other than exec_params" do
    # NON-VACUITY, THROUGH THE DOOR THE OLD SENTINEL COULD NOT SEE.
    seen = []
    subscription = described_class.subscribe { |sql, _error| seen << sql }
    begin
      DbInspector.connection.exec("SELECT 1 AS wire_tap_probe")
    ensure
      described_class.unsubscribe(subscription)
    end

    expect(seen).to include(a_string_matching(/wire_tap_probe/))
  end

  it "publishes a REFUSED statement before re-raising it" do
    # A refused write is the event the governed-write rule exists to observe, so it must reach
    # subscribers rather than being lost with the exception.
    seen = []
    subscription = described_class.subscribe { |sql, error| seen << [sql, error&.class] }
    begin
      expect { DbInspector.connection.exec("SELECT * FROM no_such_table_wire_tap") }.to raise_error(PG::Error)
    ensure
      described_class.unsubscribe(subscription)
    end

    expect(seen.map(&:first)).to include(a_string_matching(/no_such_table_wire_tap/))
    expect(seen.find { |(sql, _)| sql.include?("no_such_table_wire_tap") }.last).to be < PG::Error
  end
end
