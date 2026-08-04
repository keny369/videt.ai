# frozen_string_literal: true

module Workflows
  module Wf005
    # ":442 — AT 60 ELAPSED MINUTES, NO NEW REQUEST STARTS", ENFORCED WHERE REQUESTS ACTUALLY LEAVE.
    #
    # THE DEFECT THIS CLOSES, reproduced by the round-9 concurrency lens. A pass consults the wall
    # clock ONCE, at its entry, and then performs the robots fetch and sitemap discovery — both real
    # network calls — against that entry instant. A pass that enters one second inside its deadline
    # and spends 1.6 seconds resolving robots therefore STARTS A SITEMAP REQUEST 0.659 SECONDS AFTER
    # THE RUN IS OVER, and can still mint a forward action from work performed after expiry. The
    # repository asserts the opposite by name — `wf005_record_fetch_attempt_spec.rb`'s "starts NO
    # request past the deadline, not even robots or a sitemap" — and that example only ever enters an
    # ALREADY-expired run, so it never crosses the boundary during the pass.
    #
    # WHY THE DECORATOR RATHER THAN A CHECK BEFORE EACH FETCH. A check before each fetch is a list of
    # request sites, and this tranche's whole history is lists being one entry short: the pass makes
    # three kinds of request today and a later tranche will add a fourth. Every request in a pass goes
    # through the outbound façade it was handed, so binding the deadline to THAT is what makes the
    # rule true for requests nobody has written yet.
    #
    # THE INSTANT IS READ AT THE MOMENT OF THE REQUEST, not carried from the pass's entry. That is the
    # whole point: the elapsed time this defect is about is the time between entering the pass and
    # reaching the request.
    #
    # IT REFUSES BY RAISING, and `CrawlDriver#advance` translates that into the pass's own halt. A
    # refusal outcome would be indistinguishable from a network failure and would be RETRIED, which
    # would schedule more work for a run that is over — the opposite of ":442 stop scheduling
    # affected work".
    class RunBoundedOutbound
      # Raised INSTEAD OF starting a request the run's clock no longer permits.
      #
      # IT DESCENDS FROM `Exception`, NOT `StandardError`, AND THAT IS THE POINT. Every producer in
      # this pass wraps its network call in a `rescue StandardError` that turns a fault into a
      # RETRYABLE outcome — which is right for a host that failed and catastrophic for a run that is
      # over, because it schedules another attempt for a run whose clock has stopped. Round 9's repair
      # first added an explicit re-raise to `FetchContent`, and then `DiscoverSitemaps` swallowed it
      # anyway: a list of rescues to teach is a list, and this tranche has learned what those are
      # worth. Descending from `Exception` means no generic rescue catches it — not the two that exist
      # today, and not the ones a later tranche writes. `CrawlDriver#advance` names it explicitly.
      class DeadlinePassed < Exception; end # rubocop:disable Lint/InheritException

      def initialize(outbound, deadline:, clock:)
        @outbound = outbound
        @deadline = deadline
        @clock = clock
      end

      def fetch(*args, **kwargs, &block)
        refuse_if_expired!
        @outbound.fetch(*args, **kwargs, &block)
      end

      def fetch_dns_txt(*args, **kwargs, &block)
        refuse_if_expired!
        @outbound.fetch_dns_txt(*args, **kwargs, &block)
      end

      # F-01's façade is frozen and small, but it is not this object's business to know its shape: a
      # method added to it must be bounded too, so anything else is forwarded AFTER the same check
      # rather than silently bypassing it.
      def respond_to_missing?(name, include_private = false) = @outbound.respond_to?(name, include_private)

      def method_missing(name, *args, **kwargs, &block)
        return super unless @outbound.respond_to?(name)

        refuse_if_expired!
        @outbound.public_send(name, *args, **kwargs, &block)
      end

      private

      def refuse_if_expired!
        return unless @deadline.expired?(at: @clock.call)

        raise DeadlinePassed, "the run's 60-minute wall clock passed before this request started"
      end
    end
  end
end
