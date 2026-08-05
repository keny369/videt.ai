# frozen_string_literal: true

require "rails_helper"
require_relative "../acceptance/support/wf005_crawl_chain"

# THE DOOR'S OWN PROOF (D7). It replaces PROOF 232.
#
# WHY THE OLD PROOF WAS NOT ENOUGH, stated plainly because the same mistake is available again. PROOF
# 232 read the three stores' write statements out of the production files and asserted the verb regex
# MATCHED each one. Every version of the regex passed it. The version at HEAD passed it while also
# matching `SELECT ... FOR UPDATE`, so `lock_crawl`'s row lock was counted as a write and an
# idempotent `CancelCrawl` replay — which executes no data-modifying statement at all — satisfied the
# headline invariant's antecedent. A proof that only asks "does the door see the writes" cannot see
# that; it has to ask what ELSE the door sees, against statements nobody chose for it.
#
# SO THIS PROOF DRIVES THE REAL COMMANDS AND READS BACK WHAT THE DOOR DECIDED ABOUT THE STATEMENTS
# THEY ACTUALLY EXECUTED. The corpus is production's, not the author's.
RSpec.describe ProtectedEffectDoor, type: :architecture do
  include Wf005CrawlChain
  self.use_transactional_tests = false
  after { ReceiptMinter.truncate_all }

  # Every heredoc statement in a store, as production wrote it. The scan LOCATES statements; the
  # PLANNER classifies them, so nothing here depends on the text beyond finding it.
  def statements_in(relative_path)
    File.read(Rails.root.join(relative_path)).scan(/<<~SQL[^\n]*\n(.*?)^\s*SQL$/m).flatten
  end

  def cancel(ctx, key: "cx-#{SecureRandom.hex(6)}", expected: nil)
    version = expected || DbInspector.one("SELECT state_version FROM crawls WHERE id = $1::uuid",
                                          [ctx[:crawl_id]])["state_version"].to_i
    Workflows::Wf005::Handlers::CancelCrawl.new.call(
      command: Workflows::Wf005::Commands::CancelCrawl.new(
        command_id: SecureRandom.uuid_v7, idempotency_key: key, schema_version: "1.0",
        session_id: ctx[:g][:session_id], organization_id: ctx[:g][:organization_id],
        project_id: ctx[:g][:project_id], crawl_id: ctx[:crawl_id],
        expected_state_version: version, requested_at_utc: start_now
      ),
      request_context: Platform::RequestContext.for_actor(
        clock: Platform::Clock.fixed(start_now), ids: Platform::Ids.system,
        correlation_id: SecureRandom.uuid_v7
      )
    )
  end

  # The sentinel's own counters, read for ONE command rather than inferred from the suite total.
  def governed_writes_of
    before = AuthoritySentinel.observed_governed_writes
    effects = AuthoritySentinel.observed_effects
    result = yield
    [result, AuthoritySentinel.observed_governed_writes - before,
     AuthoritySentinel.observed_effects - effects]
  end

  # ---- the mechanism itself --------------------------------------------------

  describe "what PostgreSQL says a statement modifies" do
    it "PROOF 232 — recognises every shape the three protected writes are actually written in" do
      # READ VERBATIM FROM THE PRODUCTION FILES, then handed to the planner. A store whose statement
      # stops being recognised fails here rather than quietening the sentinel.
      sources = {
        "D3 cancellation" => ["app/contexts/identity_access/infrastructure/crawl_start_store.rb", "crawls"],
        "D6 queue insert" => ["app/contexts/identity_access/infrastructure/crawl_store.rb", "crawls"],
        "D6 policy activation" => ["app/contexts/identity_access/infrastructure/crawl_policy_store.rb",
                                   "crawl_policies"]
      }

      sources.each do |label, (path, expected_relation)|
        statements = statements_in(path)
        expect(statements).not_to be_empty, "no statement found in the #{label} store"

        governed = statements.flat_map do |sql|
          effects = described_class.effects_of(sql)
          expect(effects).not_to be_nil,
                                 "PostgreSQL could not plan a production statement in #{label}:\n#{sql[0, 240]}"
          effects.map(&:relation).select { |r| described_class.governed?(r) }
        end

        expect(governed.uniq).to include(expected_relation),
                                 "the door does not see the #{label} protected write; it saw #{governed.uniq.inspect}"
      end
    end

    it "PROOF 232b — a locking READ is not a write, which is the defect that produced D7" do
      # THE EXACT STATEMENT THE REPLAY EXECUTED. `CrawlStartStore#lock_crawl` is a `SELECT ... FOR
      # UPDATE`; the HEAD regex matched `\bUPDATE\b` inside `FOR UPDATE` and reported it as a write,
      # so an idempotent replay satisfied the sentinel's antecedent through a row lock.
      lock_read = statements_in("app/contexts/identity_access/infrastructure/crawl_start_store.rb")
                  .find { |sql| sql.strip.start_with?("SELECT") && sql.include?("FOR UPDATE") }
      expect(lock_read).not_to be_nil, "lock_crawl's statement is no longer recognisable in the store"

      expect(described_class.effects_of(lock_read)).to eq([])
      expect(described_class.governed_effects(lock_read)).to eq([])
    end

    it "PROOF 232c — rejects every other statement shape that merely mentions a write verb" do
      irrelevant = [
        "SELECT updated_at FROM crawls WHERE id = $1::uuid",
        "SELECT count(*) FROM crawl_policies",
        "SELECT id FROM crawls WHERE id = $1::uuid FOR NO KEY UPDATE",
        "SELECT id FROM organizations WHERE id = $1::uuid FOR SHARE",
        "SELECT pg_advisory_xact_lock(hashtextextended($1, 0))",
        "SELECT txid_current() AS id"
      ]
      irrelevant.each do |sql|
        expect(described_class.effects_of(sql)).to eq([]), "the door called this a write: #{sql}"
      end
    end

    it "PROOF 232d — the answer does not depend on how the production statement is FORMATTED" do
      # A door keyed to text is a door a reformatting silently blinds, which is how the second regex
      # came to match one-character table names only. The planner sees through every valid spelling.
      canonical = <<~SQL
        UPDATE crawls
        SET state = 'canceled', state_version = state_version + 1
        WHERE id = $1::uuid
      SQL
      variants = {
        "collapsed to one line" => "UPDATE crawls SET state = 'canceled', " \
                                   "state_version = state_version + 1 WHERE id = $1::uuid",
        "schema-qualified" => "UPDATE public.crawls SET state = 'canceled' WHERE id = $1::uuid",
        "quoted identifier" => %(UPDATE "crawls" SET state = 'canceled' WHERE id = $1::uuid),
        "lower case verb" => "update crawls set state = 'canceled' where id = $1::uuid",
        "aliased" => "UPDATE crawls c SET state = 'canceled' WHERE c.id = $1::uuid",
        "wrapped in a data-modifying CTE" => "WITH m AS (UPDATE crawls SET state = 'canceled' " \
                                             "WHERE id = $1::uuid RETURNING 1) SELECT count(*) FROM m"
      }

      expect(described_class.effects_of(canonical).map(&:relation)).to eq(["crawls"])
      variants.each do |label, sql|
        expect(described_class.effects_of(sql).map(&:relation)).to eq(["crawls"]),
                                                                    "the door lost the write when it was #{label}"
      end
    end

    it "PROOF 232e — a statement it cannot plan is reported as a blind spot, never as a read" do
      # THE DIFFERENCE THAT MATTERS. `[]` means "PostgreSQL planned this and it modifies nothing".
      # `nil` means "no answer", and the sentinel turns that into a run failure rather than silence.
      expect(described_class.effects_of("SELECT id FROM a_relation_that_does_not_exist")).to be_nil
      # A utility statement is a real answer: it is not optimizable, so it carries no ModifyTable.
      expect(described_class.effects_of("SET lock_timeout = '400ms'")).to eq([])
    end
  end

  # ---- the classification ----------------------------------------------------

  describe "which relations carry product facts" do
    it "PROOF 237 — reads the governed set from the CATALOGUE, so a new guarded relation joins it" do
      # THE OWNER'S TEST OF A DERIVED MECHANISM: add the property and see whether the set changes.
      # Nothing here is edited when a later tranche adds a guarded table.
      probe = "d7_governed_probe_#{SecureRandom.hex(4)}"
      owner = PgTestConnection.connect(user: DbInspector.superuser)
      begin
        owner.exec("CREATE TABLE #{probe} (id int PRIMARY KEY)")
        described_class.instance_variable_set(:@governed_relations, nil)
        expect(described_class.governed?(probe)).to be(false), "an unguarded relation is not a product fact"

        owner.exec("CREATE TRIGGER #{probe}_guard BEFORE UPDATE ON #{probe} " \
                   "FOR EACH ROW EXECUTE FUNCTION f1_crawls_guard()")
        described_class.instance_variable_set(:@governed_relations, nil)
        expect(described_class.governed?(probe)).to be(true),
                                                    "a guarded relation did not join the governed set"
      ensure
        owner.exec("DROP TABLE IF EXISTS #{probe} CASCADE")
        owner.close
        described_class.instance_variable_set(:@governed_relations, nil)
      end
    end

    it "PROOF 238 — checks its own classification against a property it does not use" do
      # THE INDEPENDENT CHECK, AND THE DIRECTION THAT MATTERS. Governed is derived from `pg_trigger`.
      # This reads `pg_attribute`. The dangerous misclassification is a product aggregate called
      # command evidence, because that one is SILENT: the antecedent stops being satisfied and the
      # run goes GREENER. So every relation the run saw a WF-005 command write and classify
      # INCIDENTAL must carry no `state` lifecycle either.
      #
      # THE POPULATION IS THE RUN'S, NOT A LIST — it is the census the sentinel built from what
      # actually executed, which is why this example drives a real command first.
      ctx = running_crawl
      expect(cancel(ctx).success?).to be(true)

      expect(AuthoritySentinel.observed_relations(governed: false)).not_to be_empty,
                                                                          "no incidental relation was observed, so this checks nothing"
      expect(AuthoritySentinel.lifecycle_but_unguarded).to be_empty,
                                                           "a relation WF-005 wrote carries product lifecycle state with no PostgreSQL " \
                                                           "guard: #{AuthoritySentinel.lifecycle_but_unguarded.join(', ')}"
    end

    it "PROOF 238b — and that check is not vacuous: the shape it looks for exists in this schema" do
      # A check whose predicate is false of everything would pass forever. These relations carry a
      # `state` lifecycle and no guard; WF-005 does not write them, and the day it does, PROOF 238
      # fails rather than quietly reclassifying them as command evidence.
      unguarded_with_state = DbInspector.all(<<~SQL).map { |r| r["relname"] }
        SELECT c.relname FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
        WHERE n.nspname = 'public' AND c.relkind = 'r'
          AND NOT EXISTS (SELECT 1 FROM pg_trigger t WHERE t.tgrelid = c.oid AND NOT t.tgisinternal)
          AND EXISTS (SELECT 1 FROM pg_attribute a WHERE a.attrelid = c.oid AND a.attname = 'state'
                        AND a.attnum > 0 AND NOT a.attisdropped)
        ORDER BY 1
      SQL

      expect(unguarded_with_state).not_to be_empty,
                                          "no relation has this shape, so PROOF 238's check cannot be shown to fire"
      unguarded_with_state.each do |relation|
        expect(described_class.governed?(relation)).to be(false)
        expect(described_class.lifecycle?(relation)).to be(true),
                                                        "#{relation} would pass PROOF 238 while being exactly what it looks for"
      end
    end

    it "PROOF 238c — the command-evidence ledgers are classified INCIDENTAL" do
      # Stated where a reader looks for it. If any of these were a product fact, EVERY successful
      # command would satisfy the antecedent and the rule would be the over-broad one D7 removed.
      %w[command_executions command_results audit_record_registry authorization_decisions
         event_registry idempotency_records].each do |ledger|
        expect(described_class.governed?(ledger)).to be(false), "#{ledger} is classified as a product fact"
        expect(described_class.lifecycle?(ledger)).to be(false), "#{ledger} carries a product lifecycle"
      end
    end
  end

  # ---- the antecedent, driven through production ------------------------------

  describe "what the antecedent is satisfied by, observed end to end" do
    it "PROOF 233 — a real cancellation DOES commit a protected side effect" do
      # NON-VACUITY FIRST. A narrowed antecedent that nothing satisfies is not a sharper rule, it is
      # a switched-off one.
      ctx = running_crawl

      result, governed, effects = governed_writes_of { cancel(ctx) }

      expect(result.success?).to be(true), result.inspect
      expect(governed).to be >= 1, "the cancellation committed no protected side effect the door saw"
      # AND NOT EVERY WRITE IS ONE. A door that counted its whole traffic would satisfy the line above
      # forever while restoring exactly the over-broad antecedent D7 removed: the cancellation also
      # writes its execution, decision, audit, event, result and idempotency rows, none of which is a
      # product fact. `effects` counts every relation-modifying statement; `governed` counts the ones
      # over guarded relations, and the two MUST differ.
      expect(governed).to be < effects,
                          "every relation-modifying effect the cancellation executed was counted as a " \
                          "protected side effect (#{governed} of #{effects}); the antecedent is 'wrote' again"
    end

    it "PROOF 234 — an idempotent REPLAY commits none, so it needs no exemption" do
      # THE WHOLE OF D7's THIRD REQUIREMENT, PROVED RATHER THAN ASSERTED. The sentinel used to carry
      # a written exemption for replays resting on "a replay WRITES NOTHING". That was TRUE; the DOOR
      # was wrong, and counted `lock_crawl`'s `FOR UPDATE` as the write. With the door asking
      # PostgreSQL, correct replay behaviour falls outside the antecedent by what it does.
      ctx = running_crawl
      key = "replay-#{SecureRandom.hex(6)}"
      version = DbInspector.one("SELECT state_version FROM crawls WHERE id = $1::uuid",
                                [ctx[:crawl_id]])["state_version"].to_i
      first = cancel(ctx, key:, expected: version)
      expect(first.success?).to be(true), first.inspect

      replay, governed, = governed_writes_of { cancel(ctx, key:, expected: version) }

      expect(replay.success?).to be(true), replay.inspect
      expect(replay.replayed).to be(true), "this was not a replay, so it proves nothing about one"
      expect(governed).to eq(0),
                          "the replay was observed committing #{governed} protected side effect(s); the " \
                          "antecedent is over-broad again and a replay exemption would be needed"
    end

    it "PROOF 235 — and the sentinel records NO violation for that replay" do
      # The consequence of 234, stated where a reader looks for it: the rule does not fire.
      ctx = running_crawl
      key = "replay2-#{SecureRandom.hex(6)}"
      version = DbInspector.one("SELECT state_version FROM crawls WHERE id = $1::uuid",
                                [ctx[:crawl_id]])["state_version"].to_i
      expect(cancel(ctx, key:, expected: version).success?).to be(true)
      before = AuthoritySentinel.violations.length

      cancel(ctx, key:, expected: version)

      expect(AuthoritySentinel.violations.length).to eq(before),
                                                     AuthoritySentinel.violations.map(&:to_s).last.to_s
    end

    it "PROOF 236 — a DENIAL leaves command evidence and moves no product fact" do
      ctx = running_crawl
      before = DbInspector.one("SELECT state, state_version FROM crawls WHERE id = $1::uuid", [ctx[:crawl_id]])

      stale = cancel(ctx, expected: 9999)

      expect(stale).not_to be_success
      expect(stale.reason_code).to eq("stale_state_version")
      after = DbInspector.one("SELECT state, state_version FROM crawls WHERE id = $1::uuid", [ctx[:crawl_id]])
      expect(after).to eq(before), "a refused command moved product state"
    end
  end
end
