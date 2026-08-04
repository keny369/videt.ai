# frozen_string_literal: true

require "json"
require "open3"

module AutonomousBuild
  # A MUTATION RECORD THAT THE REPOSITORY CAN REPLAY (round 9, R9-6).
  #
  # WHAT WAS WRONG. The round-9 ledger was written by a harness that lived OUTSIDE the repository, its
  # `worktree` field pointed at a path no checkout contains, and no entry recorded a file, a line or a
  # diff. The gate that "confirms the mutation LANDED" asserted a boolean the ledger's own author
  # wrote, so a fabricated entry that never ran passed it. Every entry a reviewer re-ran did in fact
  # reproduce — the defect was not dishonesty, it was that NOTHING IN THE REPOSITORY COULD ESTABLISH
  # THAT, while a gate said it did.
  #
  # WHAT AN ENTRY MUST NOW CARRY, and why each part is load-bearing:
  #
  #   file / from / to  — the exact substitution, so the mutation can be APPLIED here rather than
  #                       described. `from` must occur EXACTLY ONCE in the file, which is what stops
  #                       an entry landing at a different identical site: FU-44 was invalidated
  #                       because three identical comparisons existed and the edit hit the wrong one.
  #   proof             — the spec that must reject it.
  #   expectation       — `kill`, or `equivalent` with a recorded reason.
  #
  # `verify_applicable!` is the cheap, deterministic half: it proves every entry still names a real,
  # unique site in the current tree, which rejects fabricated, stale and wrong-site entries without
  # running anything. `replay` is the expensive half, which applies the mutation, runs the named
  # proof, and restores from a CONTENT SNAPSHOT rather than from git — because during a repair the
  # tree is legitimately dirty, and `git checkout` would silently discard the repair being proved.
  module MutationHarness
    module_function

    def load(path) = JSON.parse(File.read(path)).fetch("mutations")

    # Every reason this entry could not be replayed as written, or [] if it can.
    def applicability_errors(entry, root:)
      file = entry["file"]
      return ["names no file"] if file.nil?

      path = File.join(root, file)
      return ["#{file} does not exist"] unless File.exist?(path)

      source = File.read(path)
      occurrences = source.scan(entry.fetch("from")).length
      return ["#{file} contains #{occurrences} occurrences of its `from` text; a replay needs exactly one"] \
        unless occurrences == 1

      # A proof may name several files; every one must exist, or a replay would silently run less
      # than the entry claims.
      missing = entry["proof"].to_s.split(/\s+/).map { |arg| arg.split(":").first }
                     .reject { |f| f.empty? || File.exist?(File.join(root, f)) }
      return missing.map { |f| "names proof #{f}, which does not exist" } unless missing.empty?

      []
    end

    def verify_applicable!(entries, root:)
      failures = entries.flat_map do |entry|
        applicability_errors(entry, root:).map { |reason| "#{entry['id']}: #{reason}" }
      end
      raise "mutation ledger is not replayable:\n#{failures.join("\n")}" unless failures.empty?

      true
    end

    # Apply, run, restore. Returns what happened, WITHOUT a field the caller can assert instead of the
    # measurement: `landed` is computed here from the file's own bytes, never accepted as input.
    def replay(entry, root:, env: {})
      path = File.join(root, entry.fetch("file"))
      original = File.read(path)
      mutated = original.sub(entry.fetch("from"), entry.fetch("to"))
      raise "#{entry['id']}: substitution changed nothing" if mutated == original

      File.write(path, mutated)
      landed = File.read(path) == mutated && File.read(path) != original
      begin
        # NO SHELL. The proof's arguments come from a JSON file this module exists to distrust, and a
        # `from`/`proof` field carrying `$(...)` would otherwise execute — the same reasoning
        # `repository_truth_spec.rb` already records for its own git calls. argv form, explicit status.
        output, status = Open3.capture2e(env.transform_keys(&:to_s),
                                         "bundle", "exec", "rspec", *entry.fetch("proof").split(/\s+/),
                                         chdir: root)
        { "id" => entry["id"], "landed" => landed, "verdict" => status.success? ? "survived" : "killed",
          "result" => output[/(\d+) examples?, (\d+) failures?/],
          "failing_examples" => output.scan(%r{^rspec '?\./(spec/[^'\s]+)}).flatten.uniq }
      ensure
        File.write(path, original)
        raise "#{entry['id']}: RESTORE FAILED" unless File.read(path) == original
      end
    end
  end
end
