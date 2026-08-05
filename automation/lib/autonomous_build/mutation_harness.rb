# frozen_string_literal: true

require "digest"
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

    # THE VERDICT IS BOUND TO THE EXACT EVIDENCE IT CAME FROM (D5 family 5; R10-5, R10-19).
    #
    # WHAT WAS WRONG. `verify_applicable!` proves an entry COULD be replayed here. It does not prove
    # its recorded verdict WAS measured here, so a row stayed "valid" while the production code it
    # mutated, the proof it named, or the failure it observed all changed underneath it. The gate then
    # compared the recorded verdict against the recorded expectation — a self-report checked against
    # itself, which is round 9's `landed` boolean one level along.
    #
    # WHAT A ROW IS NOW BOUND TO. Every input that could change what the replay would find: the patch
    # bytes, the target file's bytes, the target path, the proof command, the bytes of every proof
    # file, the failing example identities, a normalised digest of the failure output, the equivalence
    # justification where one is claimed, the repository commit, and whether restoration succeeded.
    # Changing any of them changes `binding_sha256`, and a row whose recomputed binding differs from
    # the one it carries is STALE, TRANSPLANTED or FABRICATED — the three cases are indistinguishable
    # from the outside and are all rejected.
    BOUND_FIELDS = %w[id file from to proof expectation verdict result failing_examples
                      failure_digest equivalence_reason commit restored file_sha256 proof_sha256].freeze

    def canonical(entry)
      # Canonical encoding: sorted keys, no whitespace variance, so an equal row hashes equally
      # whatever order the generator wrote its keys in.
      JSON.generate(BOUND_FIELDS.to_h { |k| [k, entry[k]] }.sort.to_h)
    end

    def binding_for(entry) = Digest::SHA256.hexdigest(canonical(entry))

    def proof_digest(entry, root:)
      files = entry["proof"].to_s.split(/\s+/).map { |arg| arg.split(":").first }.reject(&:empty?)
      material = files.sort.map { |f| [f, File.exist?(File.join(root, f)) ? File.read(File.join(root, f)) : ""] }
      Digest::SHA256.hexdigest(JSON.generate([entry["proof"], material]))
    end

    def binding_errors(entry, root:)
      errors = []
      errors << "carries no binding_sha256, so its verdict is bound to nothing" if entry["binding_sha256"].nil?
      errors << "records no verdict" if entry["verdict"].nil?
      errors << "records verdict `broken`, which proves nothing: the run aborted before any example ran" if
        entry["verdict"] == "broken"

      actual_file = File.exist?(File.join(root, entry["file"].to_s)) ?
        Digest::SHA256.hexdigest(File.read(File.join(root, entry["file"]))) : nil
      if actual_file != entry["file_sha256"]
        errors << "was measured against #{entry['file']} @ #{entry['file_sha256'].to_s[0, 12]} but the " \
                  "tree now has #{actual_file.to_s[0, 12]}; the verdict is stale"
      end

      actual_proof = proof_digest(entry, root:)
      if actual_proof != entry["proof_sha256"]
        errors << "names proof `#{entry['proof']}`, whose bytes have changed since the verdict was " \
                  "measured; the proof that failed is not the proof that exists"
      end

      errors << "restoration was not verified after the replay" unless entry["restored"] == true
      if entry["expectation"] == "equivalent" && entry["equivalence_reason"].to_s.length < 200
        errors << "claims equivalence with no independently executable justification"
      end
      if entry["verdict"] == "killed" && Array(entry["failing_examples"]).empty?
        errors << "records a kill with no failing example identities; the proof may have failed for " \
                  "another reason, or not run at all"
      end

      recomputed = binding_for(entry)
      if recomputed != entry["binding_sha256"]
        errors << "its binding does not match its own contents (recorded #{entry['binding_sha256'].to_s[0, 12]}, " \
                  "recomputed #{recomputed[0, 12]}); the row is fabricated, transplanted or edited"
      end
      errors
    end

    # Seal a completed row. Called by the generator AFTER the replay, so the binding covers the
    # measured outcome rather than the intention.
    def seal(entry) = entry.merge("binding_sha256" => binding_for(entry))

    def verify_bindings!(entries, root:)
      failures = entries.flat_map { |e| binding_errors(e, root:).map { |r| "#{e['id']}: #{r}" } }
      raise "mutation ledger verdict bindings are invalid:\n#{failures.join("\n")}" unless failures.empty?

      true
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
        summary = output[/(\d+) examples?, (\d+) failures?/]
        examples, failures = summary&.scan(/\d+/)&.map(&:to_i)
        # A NON-ZERO EXIT IS NOT A KILL. A mutation that makes the file unparseable, or aborts the run
        # before any example executes, exits non-zero having proved NOTHING — recording that as
        # `killed` is how a proof system credits itself for a defect it never detected.
        verdict =
          if summary.nil? || examples.to_i.zero? || output.include?("error occurred outside of examples")
            "broken"
          elsif failures.to_i.positive? then "killed"
          elsif status.success? then "survived"
          else "broken"
          end
        failing = output.scan(%r{^rspec '?\./(spec/[^'\s]+)}).flatten.uniq
        { "id" => entry["id"], "landed" => landed, "verdict" => verdict, "result" => summary,
          "failing_examples" => failing,
          # THE REASON, not just the count. A proof that starts failing for an unrelated reason must
          # not keep a verdict it earned for the right one.
          "failure_digest" => Digest::SHA256.hexdigest(
            output.scan(/^\s*(?:Failure\/Error|[A-Z]\w*(?:::\w+)*Error):.*/).join("\n")
          ),
          "file_sha256" => Digest::SHA256.hexdigest(original),
          "proof_sha256" => proof_digest(entry, root:),
          "commit" => Open3.capture2e("git", "-C", root, "rev-parse", "HEAD").first.strip,
          # Set here rather than by the caller: the `ensure` below raises if restoration failed, so
          # reaching this point IS the verification. A ledger row cannot claim it without it happening.
          "restored" => true }
      ensure
        File.write(path, original)
        raise "#{entry['id']}: RESTORE FAILED" unless File.read(path) == original
      end
    end
  end
end
