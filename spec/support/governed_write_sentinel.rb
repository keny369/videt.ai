# frozen_string_literal: true

# WHAT ACTUALLY EXECUTED, OBSERVED AT THE WIRE (round 8, R8-2 and R8-3).
#
# Round 8's finding was not that the code was wrong. It was that the PROOFS did not reach the code
# they named: PROOF 168 terminalized before `advance`, so `authorize_run` refused at step zero and
# the branch under test never ran — while both of the proof's assertions passed. A proof that cannot
# tell "the guard refused" from "the guard was never reached" proves nothing, and no amount of
# assertion writing fixes that from the outside.
#
# This is the instrument that tells them apart. Every governed write leaves this process through
# `PG::Connection#exec_params` — the stores are handed `conn.raw_connection` and speak to it
# directly, so ActiveRecord's own instrumentation never sees these statements — so that is where it
# is observed:
#
#   * WHICH governed table was written, taken from the statement itself;
#   * WHICH WF-005 source line issued it, taken from the live call stack;
#   * WHETHER `Wf005::ClosedFactSet.translate` was on that stack at the moment of the write;
#   * WHETHER the database refused it.
#
# THE GOVERNED SET IS DERIVED FROM THE CATALOGUE, NOT LISTED HERE. `f1_crawl_child_fact_closed` is
# the rule; the tables carrying it are read out of `pg_trigger` on first use. A table a later tranche
# governs joins this instrument the moment its trigger exists, with nobody remembering to add it —
# which is the property R8-2 needed and did not have: round 7 enumerated two producers, repaired
# those two, and `FetchContent#settle` was a third that no list contained.
#
# IT ADDS NOTHING TO PRODUCTION. The translation frame is detected by reading the call stack, so
# `ClosedFactSet` carries no test-facing flag and production carries no instrumentation.
module GovernedWriteSentinel
  # A single governed write, as observed.
  Attempt = Struct.new(:table, :statement, :site, :translated, :refused, :reachable, :stack,
                       keyword_init: true) do
    def translated? = translated
    def refused? = refused
    # Was a platform-invoked WF-005 entry point on the stack, or did an example drive an internal?
    def reachable_in_production? = reachable
  end

  # The WF-005 production surface this rule governs. A DIRECTORY, not a producer list: the rule is
  # "a governed write issued by WF-005 code", and every file that is WF-005 code lives here.
  WF005_SOURCE = %r{/app/workflows/wf005/}
  # THE PLATFORM-INVOKED ENTRY POINTS. A `crawl_fetch_due` delivery enters at
  # `handlers/record_fetch_attempt.rb` and a command at its own handler; nothing else in this workflow
  # is reachable from outside a proof. The rule is about what PRODUCTION can do, so a write with no
  # handler on its stack was driven straight into an internal by an example, and says nothing about
  # what production can reach.
  WF005_ENTRY = %r{/app/workflows/wf005/handlers/}
  TRANSLATION_OWNER = %r{/app/workflows/wf005/closed_fact_set\.rb}
  # A write whose NEAREST owning frame is a spec is the harness simulating state — `pacer_for` rewrites
  # `crawl_host_gates` pacing columns to fake elapsed time — and is not a producer. Nearest wins: the
  # frame closest to the statement is the one that issued it.
  SPEC_SOURCE = %r{/spec/}
  STACK_DEPTH = 160

  # THE WRITES PRODUCTION CAN REACH THAT ARE DELIBERATELY NOT TRANSLATED, each with the reason it is
  # not, in the shape `crawl_terminal_fact_closure_spec.rb` already uses for its ungoverned tables. A
  # producer that appears in neither this list nor a translation FAILS, which is the property round 8
  # needed: `FetchContent#settle` was a third producer that no list contained and no check missed it.
  #
  # Both members are the COMMAND that changes the run's state, holding the Crawl's row lock across its
  # own re-read, not a worker arriving late against a decision someone else made. Owner ruling 2 is
  # about the latter: "a stale or late worker must receive a controlled domain outcome". A translation
  # here would convert an unreachable refusal into a typed error with no rescuer, which is worse than
  # the raw one.
  CLASSIFIED_UNTRANSLATED = {
    ["workflows/wf005/frontier.rb", "workflows/wf005/handlers/start_crawl.rb", "crawl_frontier_entries"] =>
      "StartCrawl builds the root frontier in the SAME transaction that moves the Crawl queued -> " \
      "running, holding the Crawl's row lock and re-reading its state under that lock. A concurrent " \
      "cancellation must take the same lock, so it commits either entirely before the re-read (which " \
      "refuses) or entirely after this transaction ends. The closure cannot fire; " \
      "spec/acceptance/wf005_start_cancel_concurrency_spec.rb holds that ordering.",
    ["workflows/wf005/limit_decisions.rb", "workflows/wf005/handlers/complete_crawl.rb", "crawl_limit_decisions"] =>
      "CompleteCrawl IS the terminal selection. Its limit decisions are written in the same " \
      "transaction, before the state change that would close the fact set, under the Crawl's row " \
      "lock. There is no window in which a terminal parent could refuse this handler's own write."
  }.freeze

  class << self
    # Tables closed by the ratified trigger, read from the catalogue exactly as
    # `crawl_terminal_fact_closure_spec.rb` reads it. Memoized per process, never hardcoded.
    #
    # THE VERB MATTERS, AND IT IS ALSO READ FROM THE CATALOGUE. `f1_crawl_child_fact_closed` sits on
    # INSERT for five child tables and on UPDATE for `crawl_host_gates`'s outcome columns alone
    # (PROOF 157). An UPDATE the trigger cannot fire on is not a governed write, and counting it
    # would make this instrument report writes that no closure can refuse.
    def closed_on(verb)
      @closed_on ||= {}
      @closed_on[verb] ||= DbInspector.all(<<~SQL, [verb == :insert ? 4 : 16]).map { |r| r["child"] }.freeze
        SELECT DISTINCT c.relname AS child
        FROM pg_trigger t
        JOIN pg_class c ON c.oid = t.tgrelid
        JOIN pg_proc pr ON pr.oid = t.tgfoid
        WHERE NOT t.tgisinternal AND pr.proname = 'f1_crawl_child_fact_closed'
          AND (t.tgtype & $1::int) <> 0
        ORDER BY c.relname
      SQL
    end

    def governed_tables = (closed_on(:insert) + closed_on(:update)).uniq.sort

    def write_pattern
      @write_pattern ||= begin
        inserts = closed_on(:insert).map { |t| Regexp.escape(t) }.join("|")
        updates = closed_on(:update).map { |t| Regexp.escape(t) }.join("|")
        Regexp.new("(?:INSERT\\s+INTO\\s+(?:public\\.)?\"?(?<t>#{inserts})\"?[\\s(]" \
                   "|UPDATE\\s+(?:public\\.)?\"?(?<t>#{updates})\"?[\\s(])", Regexp::IGNORECASE)
      end
    end

    # THE CENSUS. Every distinct (WF-005 site, table, translated?) triple the process has executed,
    # with a count. This is what makes the completeness claim an OBSERVATION rather than a list:
    # after a run it says exactly which lines of WF-005 wrote which governed tables, and which of
    # them did so outside the translation.
    def census = (@census ||= Hash.new(0))

    # Governed writes issued by WF-005 code with no translation frame on the stack.
    # THE COMPLETENESS QUESTION, ANSWERED FROM EXECUTION. Every (site, origin, table) production
    # could reach that wrote a governed fact with no translation frame on the stack.
    def untranslated_production_sites
      census.keys.select { |(_site, _origin, _table, translated, reachable)| reachable && !translated }
    end

    # A census key reduced to the files and table it concerns, which is what the classification is
    # keyed on: a line number moves when a comment is added, and the rule is about the producer.
    def classification_key(entry)
      site, origin, table, = entry
      [site.to_s.split(":").first, origin.to_s.split(":").first, table]
    end

    # Untranslated production-reachable writes that nobody has classified. THE FAILURE SET.
    def unclassified
      untranslated_production_sites.reject { |e| CLASSIFIED_UNTRANSLATED.key?(classification_key(e)) }
    end

    def report(entries)
      entries.map { |(site, origin, table, translated, reachable)|
        "#{table} written at #{site} (entered at #{origin}); translated=#{translated} reachable=#{reachable}"
      }.join("\n")
    end

    # Full records, kept only while a `record` block is open — the census is what runs suite-wide.
    def attempts = (@attempts ||= [])

    def armed? = @armed ||= false
    def recording? = @recording ||= false

    # Arm for the whole process. Cheap: one regexp against the statement text, and the call stack is
    # walked only for a statement that actually names a governed table.
    # THE CATALOGUE IS READ BEFORE THE HOOK IS INSTALLED, never lazily from inside it: the catalogue
    # query is itself an `exec_params`, so a lazy read re-enters the hook and recurses.
    def arm!
      return if armed?

      write_pattern
      PG::Connection.prepend(Instrumentation)
      @armed = true
    end

    # Record full detail for what happens inside the block, and hand it back.
    def record
      arm!
      previous = @recording
      @recording = true
      attempts.clear
      begin
        yield
      ensure
        @recording = previous
      end
      attempts.dup
    end

    def observe(statement, error)
      table = write_pattern.match(statement)&.[](:t)
      return if table.nil?

      stack = caller_locations(1, STACK_DEPTH) || []
      # NEAREST OWNER WINS. Whichever comes first — WF-005 code or an example — is the frame that
      # issued this statement, and a statement issued by an example is the harness, not a producer.
      own_path = __FILE__
      issuer = stack.find do |l|
        path = l.absolute_path.to_s
        next false if path == own_path

        path.match?(WF005_SOURCE) || path.match?(SPEC_SOURCE)
      end
      return if issuer.nil? || !issuer.absolute_path.to_s.match?(WF005_SOURCE)

      entry = stack.reverse.find { |l| l.absolute_path.to_s.match?(WF005_SOURCE) }
      translated = stack.any? { |l| l.absolute_path.to_s.match?(TRANSLATION_OWNER) }
      reachable = stack.any? { |l| l.absolute_path.to_s.match?(WF005_ENTRY) }
      located = "#{issuer.absolute_path.to_s.split('/app/').last}:#{issuer.lineno}"
      origin = entry && "#{entry.absolute_path.to_s.split('/app/').last}:#{entry.lineno}"
      census[[located, origin, table, translated, reachable]] += 1
      return unless recording?

      attempts << Attempt.new(
        table:, statement: statement.to_s.strip[0, 160], refused: !error.nil?, translated:,
        site: located, reachable:,
        stack: stack.map { |l| "#{l.absolute_path.to_s.split('/app/').last}:#{l.lineno}" }
      )
    end
  end

  # Both the success and the failure path are observed, because a REFUSED governed write is exactly
  # the event this instrument exists to see.
  module Instrumentation
    def exec_params(statement, *rest, &block)
      result = super
      GovernedWriteSentinel.observe(statement, nil)
      result
    rescue StandardError => e
      GovernedWriteSentinel.observe(statement, e)
      raise
    end
  end
end

RSpec.configure do |config|
  # ARMED FOR THE WHOLE SUITE, so the census is derived from everything the repository executes
  # rather than from the handful of paths one proof remembers to drive.
  config.before(:suite) { GovernedWriteSentinel.arm! }

  # AND JUDGED FOR THE WHOLE SUITE. Whatever ran — one file or all of it — a governed write that
  # production can reach, made with no translation on the stack and named in no classification, ends
  # the run. This is deliberately outside any one example: the defect it catches is a producer nobody
  # thought to write an example for, so no example can be the thing that looks for it.
  config.after(:suite) do
    unclassified = GovernedWriteSentinel.unclassified
    next if unclassified.empty?

    raise "OWNER RULING 2: #{unclassified.length} governed write(s) reachable from a WF-005 entry " \
          "point executed with no Wf005::ClosedFactSet.translate frame and no recorded reason:\n" \
          "#{GovernedWriteSentinel.report(unclassified)}"
  end
end
