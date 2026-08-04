# frozen_string_literal: true

module Workflows
  module Wf005
    # THE APPLICATION SIDE OF OWNER RULING 2, AND THE ONLY IMPLEMENTATION OF IT (round 7, C-2).
    #
    # `f1_crawl_child_fact_closed` refuses any governed child fact for a terminal Crawl. That is the
    # canonical enforcement and it is correct. Ruling 2 has a second half the round-6 repair left at one
    # producer: "a stale or late worker must receive a CONTROLLED DOMAIN OUTCOME and must not append
    # facts after terminalization." A raw `PG::RaiseException` escaping to a scheduled-action worker is
    # classified `scheduled_action_execution_failed`, which is the token meaning DEFECT — so an
    # ordinary, expected, correctly-refused race was being reported as a bug in the platform.
    #
    # WHY IT IS A MODULE AND NOT A COPIED RESCUE. Round 6 repaired this at `DiscoverSitemaps` alone, and
    # round 7 found `EnsureRobots` and the driver's gate creation writing the same governed columns with
    # no translation at all. That is the failure mode this whole tranche exists to stop: a rule enforced
    # once per producer stays one producer behind. There is one translation, every producer wraps its
    # unit of work in it, and `spec/persistence/crawl_terminal_fact_closure_spec.rb` derives the
    # producer list rather than restating it.
    #
    # IT TRANSLATES, IT DOES NOT SWALLOW. The refusal still aborts the transaction and still writes
    # nothing; only its SHAPE changes, from an exception the worker cannot classify into a domain
    # outcome the caller already knows how to report. Every other error is re-raised untouched.
    module ClosedFactSet
      # The token `f1_crawl_child_fact_closed` raises. Matched on the message rather than on SQLSTATE
      # because the guard family it joins all raise `raise_exception`, and the message is what
      # distinguishes a closed fact set from an immutability violation.
      TOKEN = "crawl_child_fact_after_terminal"

      # The controlled reason every producer reports. Deliberately NOT a :450 or :452 outcome token: the
      # run ending proves nothing about the host, and inventing an observation is exactly what owner
      # ruling 3 withdrew.
      REASON = "crawl_terminal"

      # Raised only by `translate`, caught only by a producer's public entry point.
      class CrawlWentTerminal < StandardError; end

      # Run a unit of work, converting the database's closure refusal into a domain-level signal.
      def self.translate
        yield
      rescue StandardError => e
        raise CrawlWentTerminal, e.message if e.message.to_s.include?(TOKEN)

        raise
      end

      # True when this error is the closure refusal, for a caller that would rather branch than rescue.
      def self.refusal?(error) = error.message.to_s.include?(TOKEN)
    end
  end
end
