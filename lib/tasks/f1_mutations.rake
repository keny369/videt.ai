# frozen_string_literal: true

# REGENERATE THE MUTATION LEDGER FROM THE REPOSITORY'S OWN MACHINERY (D5 family 5).
#
# The ledger is never edited by hand. Every verdict here is measured by applying the substitution,
# confirming from the file's own bytes that it landed, running the bound proof, capturing the failing
# example identities and a digest of the failure reasons, restoring, and verifying the restoration.
# The row is then SEALED: its `binding_sha256` covers the patch, the target bytes, the proof bytes,
# the outcome and the commit, so a row cannot be transplanted, fabricated or left stale.
namespace :f1 do
  namespace :mutations do
    desc "Replay the S-07-009 mutation set and regenerate its ledger"
    task :regenerate do
      $LOAD_PATH.unshift File.expand_path("../../automation/lib", __dir__)
      require "autonomous_build/mutation_harness"
      require "autonomous_build/s07_009_mutation_set"
      require "json"

      root = Dir.pwd
      out = ENV.fetch("LEDGER", "specification/automation/S-07-009_MUTATION_LEDGER.json")
      env = { "RAILS_ENV" => "test",
              "F1_DATABASE_NAME" => ENV.fetch("F1_DATABASE_NAME", "f1_test_r12"),
              "REDIS_URL" => ENV.fetch("REDIS_URL", "redis://127.0.0.1:6470/0") }

      entries = AutonomousBuild::S07009MutationSet::ENTRIES
      AutonomousBuild::MutationHarness.verify_applicable!(entries, root:)
      warn "all #{entries.length} definitions are applicable against the current tree"

      rows = entries.map do |entry|
        outcome = AutonomousBuild::MutationHarness.replay(entry, root:, env:)
        row = AutonomousBuild::MutationHarness.seal(entry.merge(outcome))
        warn format("%-34s landed=%-5s %-9s %s", row["id"], row["landed"], row["verdict"], row["result"])
        row
      end

      # TRIGGER MUTATIONS ARE REPLAYED TOO, and sealed and verified with the same machinery. They
      # used to be copied into the ledger as literals, which is the unbound channel the architecture
      # and schema lenses both found.
      trigger_rows = AutonomousBuild::S07009MutationSet::TRIGGER_MUTATIONS.map do |entry|
        outcome = AutonomousBuild::MutationHarness.replay_trigger(entry, root:, env:)
        row = AutonomousBuild::MutationHarness.seal(entry.merge(outcome))
        warn format("%-34s landed=%-5s %-9s %s", row["id"], row["landed"], row["verdict"], row["result"])
        row
      end

      all_rows = rows + trigger_rows
      # The verifier needs a reader for the live trigger definition, or a trigger row's staleness
      # cannot be checked — it used to be compared against its own recorded digest, which is no check
      # at all. The harness already talks to PostgreSQL, so the reader is its own.
      reader = lambda do |name, table|
        AutonomousBuild::MutationHarness.send(
          :pg_value, env.fetch("F1_DATABASE_NAME"), ENV.fetch("USER"),
          "SELECT pg_get_triggerdef(t.oid) FROM pg_trigger t JOIN pg_class c ON c.oid = t.tgrelid " \
          "WHERE t.tgname = '#{name}' AND c.relname = '#{table}' AND NOT t.tgisinternal"
        )
      end
      AutonomousBuild::MutationHarness.verify_bindings!(all_rows, root:, trigger_definition: reader)
      File.write(out, JSON.pretty_generate({
        "generated_by" => "rake f1:mutations:regenerate (AutonomousBuild::MutationHarness)",
        "definitions" => "automation/lib/autonomous_build/s07_009_mutation_set.rb",
        "binding" => "each row's binding_sha256 covers the patch, target bytes, proof bytes, outcome " \
                     "and commit; see MutationHarness::BOUND_FIELDS",
        "mutations" => all_rows
      }) + "\n")
      killed = all_rows.count { |r| r["verdict"] == "killed" }
      warn "\nwrote #{out}: #{killed}/#{all_rows.length} killed, " \
           "#{all_rows.count { |r| r['verdict'] == 'survived' }} survived, " \
           "#{all_rows.count { |r| r['verdict'] == 'broken' }} broken"
    end
  end
end
