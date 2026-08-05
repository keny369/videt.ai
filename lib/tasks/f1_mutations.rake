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

      AutonomousBuild::MutationHarness.verify_bindings!(rows, root:)
      File.write(out, JSON.pretty_generate({
        "generated_by" => "rake f1:mutations:regenerate (AutonomousBuild::MutationHarness)",
        "definitions" => "automation/lib/autonomous_build/s07_009_mutation_set.rb",
        "binding" => "each row's binding_sha256 covers the patch, target bytes, proof bytes, outcome " \
                     "and commit; see MutationHarness::BOUND_FIELDS",
        "trigger_mutations" => AutonomousBuild::S07009MutationSet::TRIGGER_MUTATIONS,
        "mutations" => rows
      }) + "\n")
      killed = rows.count { |r| r["verdict"] == "killed" }
      warn "\nwrote #{out}: #{killed}/#{rows.length} killed, " \
           "#{rows.count { |r| r['verdict'] == 'survived' }} survived, " \
           "#{rows.count { |r| r['verdict'] == 'broken' }} broken"
    end
  end
end
