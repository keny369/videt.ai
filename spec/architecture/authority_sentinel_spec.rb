# frozen_string_literal: true

require "rails_helper"

# THE SENTINEL'S OWN PROOF (D5 family 4; R10-9, R10-11).
#
# The suite-wide rule it enforces is only worth what the instrument is worth. These examples are
# about the instrument: what it discovers, how it accounts, and whether it can go blind quietly.
RSpec.describe AuthoritySentinel, type: :architecture do
  describe "discovery" do
    it "covers EVERY WF-005 handler, derived from the directory rather than matched in source" do
      # R10-9. The set was decided by matching each file's source against
      # `/authenticate\(session_id:/`, which covered 3 of 6 handlers on this branch and which a merely
      # reformatted call defeats. Discovery is now the directory, and human-authorization is decided
      # per execution by whether `CommandAuthorizer#authenticate` RAN.
      files = Dir[Rails.root.join(described_class::HANDLER_DIR, "*.rb")].sort
      expect(files.length).to be >= 5, "the handler directory scan found #{files.length} files"

      expected = files.map { |f| File.basename(f, ".rb").camelize }.sort
      expect(described_class.observed_handlers.map { |h| h.name.split("::").last }.sort).to eq(expected),
             "a handler exists that the sentinel does not observe"
    end

    it "picks up a NEW production path without anyone updating a list" do
      # The owner's test of a derived mechanism: add a producer and see whether discovery finds it.
      # The directory is re-read, so a handler added by a later tranche joins the rule by existing.
      new_file = Rails.root.join(described_class::HANDLER_DIR, "sentinel_discovery_probe.rb")
      File.write(new_file, <<~RUBY)
        module Workflows
          module Wf005
            module Handlers
              class SentinelDiscoveryProbe
                def call(**) = nil
              end
            end
          end
        end
      RUBY
      described_class.instance_variable_set(:@observed_handlers, nil)
      load new_file

      expect(described_class.observed_handlers.map { |h| h.name.split("::").last })
        .to include("SentinelDiscoveryProbe")
    ensure
      FileUtils.rm_f(new_file)
      described_class.instance_variable_set(:@observed_handlers, nil)
      Workflows::Wf005::Handlers.send(:remove_const, :SentinelDiscoveryProbe) if
        Workflows::Wf005::Handlers.const_defined?(:SentinelDiscoveryProbe, false)
    end
  end

  describe "accounting" do
    it "keeps each thread's frame separate, so one command cannot erase another's" do
      # R10-11. The counters lived in module state, so one thread's `ensure` restored the other's
      # frame: writes were attributed to the wrong command and a real violation could be ERASED by a
      # concurrent well-behaved command. Two threads open frames simultaneously and each must see
      # only its own.
      barrier = Queue.new
      results = {}
      threads = %i[a b].map do |name|
        Thread.new do
          described_class.around_command(Struct.new(:name).new("T#{name}")) do
            described_class.frame[:writes] += 1
            barrier << name
            sleep 0.05 # hold the frame open while the other thread opens its own
            results[name] = described_class.frame[:writes]
            nil
          end
        end
      end
      2.times { barrier.pop }
      threads.each { |t| t.join(5) || raise("a sentinel thread did not finish within 5s") }

      expect(results.values).to eq([1, 1]),
                                "frames leaked across threads: #{results.inspect}"
    end

    it "restores the enclosing frame exactly, so nesting cannot corrupt the outer command" do
      outer = Struct.new(:name).new("Outer")
      inner = Struct.new(:name).new("Inner")
      described_class.around_command(outer) do
        described_class.frame[:writes] += 3
        described_class.around_command(inner) { described_class.frame[:writes] += 1 }
        expect(described_class.frame[:writes]).to eq(3), "the inner frame leaked into the outer"
        nil
      end
    end
  end

  describe "non-vacuity" do
    it "REFUSES to report success from an empty census" do
      # The failure mode this forecloses is the worst kind: blinding the instrument makes the suite
      # GREENER, because a sentinel that observes nothing records no violations. Removing either
      # observer must therefore fail the run rather than quieten it.
      # DRIVEN DIRECTLY, so this does not depend on what other files ran first. An earlier version
      # asserted the live counters and was order-dependent — which is itself one of the defects this
      # family exists to remove.
      expect { described_class.assert_observed!(commands: 0, writes: 5) }
        .to raise_error(/observed ZERO WF-005 command executions/)
      expect { described_class.assert_observed!(commands: 5, writes: 0) }
        .to raise_error(/observed ZERO writes/)
      expect { described_class.assert_observed!(commands: 5, writes: 5) }.not_to raise_error
    end
  end
end
