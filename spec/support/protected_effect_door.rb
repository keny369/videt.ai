# frozen_string_literal: true

require "json"

# WHICH STATEMENTS COMMIT A PROTECTED SIDE EFFECT, ANSWERED BY POSTGRESQL (D7).
#
# THE TERM IS THE SPECIFICATION'S OWN. `WORKFLOW_SPECIFICATIONS.md :335` says a running privileged
# operation "rechecks at each durable checkpoint and STOPS BEFORE THE NEXT PROTECTED SIDE EFFECT
# after revocation". That — not "wrote" — is the antecedent of the tranche's completeness rule. This
# module is the observation of it, and "governed write" in the D7 record means exactly ":335's
# protected side effect".
#
# WHY IT EXISTS. `AuthoritySentinel`'s door was a verb regex, and every form of it has been wrong:
#
#   * anchored to the start of the statement — blind to every CTE-shaped write, which is what all
#     three of this tranche's protected writes are;
#   * `UPDATE\s+\w` with a following `\b` — `\w` matches ONE character, so it saw `UPDATE c` and
#     nothing else, and was blind to every update in the repository;
#   * `\b(?:INSERT\s+INTO|UPDATE|DELETE\s+FROM)\b` — the form at HEAD, which counts
#     `SELECT ... FOR UPDATE` AS A WRITE. Measured on this branch: an idempotent `CancelCrawl` replay,
#     which writes nothing at all, was reported as issuing one write, because `lock_crawl` takes
#     `FOR UPDATE`. The blocker record read that as "a replay writes its execution record"; it does
#     not. The antecedent was being satisfied by A LOCKING READ.
#
# Three regexes, three different wrong answers, and each was greener than the last. A fourth would be
# the same bet with different characters.
#
# SO NOTHING HERE PARSES SQL. The question "does this statement modify a table, and which" is one
# PostgreSQL answers exactly, for the real statement, without executing it:
#
#     EXPLAIN (GENERIC_PLAN, FORMAT JSON) <the statement, parameter placeholders and all>
#
# The plan carries a `ModifyTable` node for each relation the statement modifies, with the operation
# and the relation name. `SELECT ... FOR UPDATE` plans to `LockRows` and yields none, which is the
# defect above closed by construction rather than by one more character class. `GENERIC_PLAN` (PG 16+)
# is what makes this possible on the production statement: it plans `$1` placeholders with no values,
# so the statement observed IS the statement executed.
#
# WHAT IS GOVERNED, READ FROM THE CATALOGUE. A relation carries product facts when PostgreSQL itself
# enforces rules over its rows — the `f1_*_guard`, `f1_*_lifecycle_guard`, `f1_*_immutable` and
# `f1_crawl_child_fact_closed` triggers. The command-evidence ledgers carry none, because nothing
# about them is a product fact: `command_executions`, `command_results`, `audit_record_registry`,
# `event_registry`, `authorization_decisions` and `idempotency_records` record THAT a command was
# processed, and a denial and a replay write them exactly as a transition does. The set is read from
# `pg_trigger` on first use and never listed here.
#
# THAT DERIVATION IS CHECKED AGAINST AN INDEPENDENT PROPERTY, not trusted — and this comment used to
# claim a check that does not exist (round-15 contract finding R15-CTR-3). It said `AuthoritySentinel`
# asserts over the whole suite that every relation a REFUSED human-authorized command writes is
# classified INCIDENTAL, "two derivations that must agree". No such limb was ever written, and it
# could not be: a refusal reaches the write and the statement's PLAN still modifies the guarded
# relation, so the census cannot tell a refused protected write from a committed one by planning.
#
# WHAT IS ACTUALLY CHECKED, AND IT IS ONE PROPERTY RATHER THAN A SECOND DERIVATION. `governed` comes
# from `pg_trigger`; `AuthoritySentinel.assert_observed!` reads `pg_attribute` and fails the run if any
# relation a WF-005 command wrote carries a `state` lifecycle and NO PostgreSQL guard. That catches the
# dangerous direction — a product aggregate silently classified as command evidence — for every
# relation whose lifecycle is spelled `state`, which includes both relations this tranche is about.
# It does not catch a lifecycle spelled otherwise; that limit is recorded rather than papered over.
module ProtectedEffectDoor
  # PostgreSQL's own class for "this is not an optimizable statement". A utility statement (`BEGIN`,
  # `SET`, `SAVEPOINT`, DDL) cannot be planned and fails here. ANY OTHER failure on a statement that
  # then executed successfully IS a blind spot and is recorded as one.
  #
  # THE ABSENCE OF A PLAN IS NOT AN ANSWER, AND THIS COMMENT USED TO SAY IT WAS (FU-51). It read "it
  # also carries no `ModifyTable`, so the absence of a plan is the correct answer rather than a blind
  # spot". `EXPLAIN` accepts only `ExplainableStmt`, and several statements OUTSIDE that production
  # modify tables. Measured on PostgreSQL 17.10 through this very method:
  #
  #     EXPLAIN (GENERIC_PLAN, FORMAT JSON) TRUNCATE crawl_host_gates   -> SQLSTATE 42601
  #
  # so a statement that EMPTIES A GOVERNED TABLE took the limb below and was returned as `[]` — "no
  # write". `COPY ... FROM STDIN` did the same and demonstrably wrote 2 rows while the door reported
  # nothing. `DO $$..$$` and `CALL` are the same shape. Three regexes were replaced by a planner
  # because each swallowed a write; this limb swallowed four more classes of write in the planner's
  # name.
  SYNTAX_ERROR = "42601"

  # The verdict for a statement PostgreSQL WILL NOT PLAN. It is deliberately NOT `[]` and NOT `nil`:
  # it is "ask the statement that actually ran". See `tag_verdict`.
  NOT_PLANNABLE = :not_plannable

  Effect = Struct.new(:operation, :relation, keyword_init: true)

  # WHICH COMMAND TAGS MEAN "THIS TOUCHED NO TABLE ROW", AND WHY IT IS AN ALLOWLIST.
  #
  # PostgreSQL reports the statement it actually executed as a command tag on the result — the one
  # thing that answers "did this modify a relation" for a statement it refused to plan, and it
  # answers WITHOUT A REGEX over the statement text. Measured against PostgreSQL 17.10:
  # `TRUNCATE` -> "TRUNCATE TABLE", `COPY ... FROM STDIN` -> "COPY 2", `DO $$..$$` -> "DO",
  # `BEGIN` -> "BEGIN", `SET` -> "SET", `CREATE INDEX` -> "CREATE INDEX", `LOCK TABLE` -> "LOCK TABLE".
  #
  # IT IS AN ALLOWLIST BECAUSE THE FAIL-SAFE DIRECTION IS THE ONLY ONE THAT SURVIVES BEING WRONG. A
  # denylist of "statements that write" is one entry short the day PostgreSQL grows another utility
  # statement, and being one entry short means SWALLOWING A WRITE — silently, and in the direction
  # that makes the suite greener. Being one entry short on the allowlist means a LOUD blind spot on a
  # statement that was harmless, which is a report a human reads and fixes.
  #
  # THE MEMBERS ARE VERBS THAT CANNOT REACH A ROW: transaction control, session state, table-level
  # locking, statement preparation, notification and maintenance. Nothing here can INSERT, UPDATE,
  # DELETE or TRUNCATE. Cursor verbs (`DECLARE`, `FETCH`, `MOVE`, `CLOSE`) are DELIBERATELY ABSENT:
  # the repository executes none, and a cursor is a way to run a query in instalments, so admitting
  # one would be admitting a verb on argument rather than on measurement.
  BENIGN_TAG_HEADS = %w[
    BEGIN START COMMIT END ROLLBACK ABORT SAVEPOINT RELEASE
    SET RESET SHOW DISCARD LOAD
    LOCK PREPARE DEALLOCATE
    LISTEN UNLISTEN NOTIFY
    ANALYZE VACUUM CHECKPOINT REINDEX CLUSTER EXPLAIN
  ].to_set.freeze

  # SCHEMA MANAGEMENT, WHICH IS BENIGN ONLY WHERE IT IS NOT A COMMAND'S SIDE EFFECT.
  #
  # DDL changes the shape of the schema rather than the rows of a table, and the harness runs plenty
  # of it — `protected_effect_door_spec` itself installs and drops triggers to prove the governed set
  # is derived. But `DROP TABLE` destroys governed rows, and the tag names the VERB AND NEVER THE
  # RELATION, so the door could not attribute one if it wanted to.
  #
  # So the judgement is split rather than fudged: OUTSIDE a WF-005 command frame DDL is the harness
  # managing its own schema and is benign; INSIDE one it is a statement the door cannot account for,
  # and it is reported as a blind spot. No WF-005 handler issues DDL today, so this costs nothing
  # now and is loud the day one does. `AuthoritySentinel#resolve_by_tag` is where the frame is known.
  SCHEMA_TAG_HEADS = %w[CREATE ALTER DROP GRANT REVOKE COMMENT SECURITY IMPORT].to_set.freeze

  class << self
    def mutex = (@mutex ||= Mutex.new)

    # The statement text -> effects cache. Keyed by the statement PostgreSQL was handed, so an
    # alternate but equivalent formatting of the same write is a separate key that is planned on its
    # own merits rather than recognised from a remembered shape.
    def plans = (@plans ||= {})

    # Statements that executed successfully and could not be planned for a reason other than "not an
    # optimizable statement". Each is an instrument blind spot and fails the run.
    def unplannable = (@unplannable ||= {})

    def classifying? = Thread.current[:protected_effect_door_classifying] == true

    # A DEDICATED CONNECTION, AND NOT THE ONE EXECUTING THE STATEMENT. Planning on the caller's
    # connection would abort the caller's transaction the moment a plan failed — an instrument that
    # changes the behaviour it observes. It is a superuser connection so that planning is never
    # refused for privilege, which would otherwise report a blind spot for every statement a harness
    # runs as the schema owner.
    def connection
      @connection ||= PgTestConnection.connect(user: DbInspector.superuser)
    end

    def reset_connection!
      @connection&.close
      @connection = nil
    rescue PG::Error
      @connection = nil
    end

    # Statements PostgreSQL would not plan, counted by the command tag they turned out to carry, for
    # the ones a WF-005 command did NOT execute. They are outside the invariant's subject — the
    # harness's own `TRUNCATE ... RESTART IDENTITY CASCADE` between examples is the bulk of it — so
    # they do not fail the run, but they are counted rather than discarded: an instrument that silently
    # drops the class it was just repaired for cannot be shown to have been repaired. A proof reads
    # this back and requires it to be NON-EMPTY.
    def unclassified_tags = (@unclassified_tags ||= Hash.new(0))

    # Every relation this statement MODIFIES, taken from its plan. `[]` for a read, a lock or a
    # function call. `nil` when PostgreSQL refused to plan it for a reason that is not "this is not an
    # optimizable statement". `NOT_PLANNABLE` when it is exactly that — which is NOT "no write", and
    # is answered by `tag_verdict` once the statement has run.
    def effects_of(sql)
      text = sql.to_s
      cached = mutex.synchronize { plans[text] }
      return cached if cached

      computed = plan(text)
      mutex.synchronize { plans[text] = computed } unless computed.nil?
      computed
    end

    def plan(text)
      Thread.current[:protected_effect_door_classifying] = true
      json = mutex.synchronize do
        connection.exec("EXPLAIN (GENERIC_PLAN, FORMAT JSON) #{text}").getvalue(0, 0)
      end
      modify_table_nodes(JSON.parse(json))
    rescue PG::Error => e
      # A utility statement is not optimizable, so the PLAN has nothing to say about it. That is a
      # DEFERRAL, not an answer — the statement may still be a `TRUNCATE`. Everything else is unknown,
      # and unknown must not read as "no write".
      if e.respond_to?(:result) && e.result&.error_field(PG::PG_DIAG_SQLSTATE) == SYNTAX_ERROR
        return NOT_PLANNABLE
      end

      reconnect_if_dead(e)
      nil
    ensure
      Thread.current[:protected_effect_door_classifying] = false
    end

    # WHAT THE STATEMENT THAT ACTUALLY RAN SAYS ABOUT ITSELF (FU-51).
    #
    # `:benign` — the verb cannot reach a row. `:schema` — DDL, whose standing depends on whether a
    # command executed it. `:unknown` — the door has NO ANSWER, which includes `TRUNCATE TABLE`,
    # `COPY n`, `DO`, `CALL`, `MERGE`, and every tag nobody has adjudicated.
    #
    # `:unknown` IS THE ONLY POSSIBLE VERDICT FOR A TRUNCATE, AND THAT IS THE CORRECT OUTCOME RATHER
    # THAN A SHORTFALL. A command tag names the VERB AND NEVER THE RELATION: "TRUNCATE TABLE" carries
    # no table. So a TRUNCATE can be recorded as an instrument BLIND SPOT and can never be recorded as
    # an `Effect` against a relation. The door's job here is to stop CLAIMING "no write"; recovering
    # WHICH relation was emptied is beyond what PostgreSQL offers at this seam, and pretending
    # otherwise would put a guessed relation into the census the architecture gate reads back.
    def tag_verdict(tag)
      head = tag.to_s.strip.split(/\s+/).first.to_s.upcase
      return :benign if BENIGN_TAG_HEADS.include?(head)
      return :schema if SCHEMA_TAG_HEADS.include?(head)

      :unknown
    end

    def note_unclassified(tag)
      key = tag.to_s.strip.split(/\s+/).first.to_s.upcase
      mutex.synchronize { unclassified_tags[key] = unclassified_tags.fetch(key, 0) + 1 }
    end

    def reconnect_if_dead(error)
      reset_connection! if error.is_a?(PG::ConnectionBad) || error.is_a?(PG::UnableToSend)
    end

    def modify_table_nodes(plan)
      found = []
      walk = lambda do |node|
        return unless node.is_a?(Hash)

        if node["Node Type"] == "ModifyTable"
          found << Effect.new(operation: node["Operation"], relation: node["Relation Name"])
          Array(node["Target Tables"]).each do |t|
            found << Effect.new(operation: node["Operation"], relation: t["Relation Name"]) if t["Relation Name"]
          end
        end
        # `Plans` is the only child key PostgreSQL's JSON EXPLAIN emits: InitPlans and SubPlans are
        # members of it, distinguished by `Parent Relationship`. A `Subplans` traversal was here and
        # was dead code that read as coverage (round-15 schema observation).
        Array(node["Plans"]).each { |child| walk.call(child) }
      end
      Array(plan).each { |entry| walk.call(entry["Plan"]) }
      found.uniq { |e| [e.operation, e.relation] }
    end

    # Relations PostgreSQL enforces its own rules over: the product facts. Read from the catalogue,
    # never listed.
    #
    # MEMOIZED PER PROCESS, AND THE CATALOGUE *CAN* MOVE UNDER A RUN - this comment used to say it
    # could not (round-15 schema observation). At least ten specs install non-internal triggers on
    # public tables while the suite runs, and `protected_effect_door_spec.rb` deliberately resets this
    # memo.
    #
    # THE MOVEMENT IS ADDITIVE, AND "ADDITIVE" IS NOT THE SAME AS "LOUDER" - round 16 corrected that
    # too. A relation joining the governed set makes the headline violation rule LOUDER, but it makes
    # two emptiness limbs QUIETER: `unreached_handlers` subtracts handlers observed writing a governed
    # relation, and every WF-005 command writes `command_executions` on every path, so a spec-installed
    # trigger on THAT table would leave the limb unfireable; and `lifecycle_but_unguarded` inspects
    # only relations recorded UNGOVERNED, so a relation that joined leaves that check. No
    # spuriously-green whole-suite run has been reproduced, and the memo is load-bearing, so the honest
    # statement is this one rather than a reassurance.
    def governed_relations
      @governed_relations ||= mutex.synchronize do
        Thread.current[:protected_effect_door_classifying] = true
        begin
          connection.exec(<<~SQL).map { |r| r["relname"] }.to_set
            SELECT DISTINCT c.relname
            FROM pg_trigger t
            JOIN pg_class c ON c.oid = t.tgrelid
            JOIN pg_namespace n ON n.oid = c.relnamespace
            WHERE NOT t.tgisinternal AND n.nspname = 'public'
          SQL
        ensure
          Thread.current[:protected_effect_door_classifying] = false
        end
      end
    end

    def governed?(relation) = governed_relations.include?(relation)

    # THE COMPLEMENTARY PROPERTY, AND THE ONE THAT CATCHES THE DANGEROUS DIRECTION. A relation
    # classified INCIDENTAL because nothing guards it, but which carries a `state` column, is a
    # product aggregate someone forgot to guard — and misclassifying one of those is silent: the
    # antecedent simply stops being satisfied and the suite goes GREENER. So the sentinel asserts
    # over the run that no relation a WF-005 command wrote has a lifecycle and no guard.
    def lifecycle_relations
      @lifecycle_relations ||= mutex.synchronize do
        Thread.current[:protected_effect_door_classifying] = true
        begin
          connection.exec(<<~SQL).map { |r| r["relname"] }.to_set
            SELECT c.relname
            FROM pg_class c
            JOIN pg_namespace n ON n.oid = c.relnamespace
            JOIN pg_attribute a ON a.attrelid = c.oid
            WHERE n.nspname = 'public' AND c.relkind = 'r'
              AND a.attname = 'state' AND a.attnum > 0 AND NOT a.attisdropped
          SQL
        ensure
          Thread.current[:protected_effect_door_classifying] = false
        end
      end
    end

    def lifecycle?(relation) = lifecycle_relations.include?(relation)

    # The one question the sentinel asks: which of this statement's effects are protected side
    # effects. `:unknown` when the statement could not be planned, so a caller can tell "no governed
    # write" from "no answer" — the distinction every previous door collapsed.
    # `:unknown` for BOTH ways of having no answer — a plan PostgreSQL refused, and a statement it
    # would not plan at all. The second used to be `[]` here, which is the FU-51 defect seen from the
    # caller's side.
    def governed_effects(sql)
      effects = effects_of(sql)
      return :unknown if effects.nil? || effects == NOT_PLANNABLE

      effects.select { |e| governed?(e.relation) }
    end

    # The tag is recorded WITH the statement. A blind-spot report naming only the SQL leaves a reader
    # deriving by hand the one fact that decided it.
    def note_unplannable(sql, tag = nil)
      text = sql.to_s.strip[0, 200]
      text = "[#{tag}] #{text}" if tag
      mutex.synchronize { unplannable[text] = unplannable.fetch(text, 0) + 1 }
    end
  end
end
