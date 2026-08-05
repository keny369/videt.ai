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
      # A trigger mutation names a trigger and a DDL rather than a file substitution; its
      # replayability is established by `replay_trigger` reading the catalogue, and its verdict is
      # bound by the same seal.
      return trigger_applicability_errors(entry, root:) if entry["mechanism"] == "trigger"

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
    # WHAT THE BINDING DOES AND DOES NOT ESTABLISH, corrected after the architecture lens refuted the
    # stronger claim. `binding_sha256` is a plain digest of the row's own bound fields and `seal` is
    # public, so it detects a row that was EDITED, TRANSPLANTED from another mutation, or left STALE
    # against the tree — but it CANNOT detect a row that was fabricated whole and sealed correctly,
    # because there is no secret and no external anchor. The lens minted exactly such a row and both
    # verifiers accepted it.
    #
    # FABRICATION IS REFUTED BY RE-EXECUTION, not by hashing: `rake f1:mutations:regenerate` replays
    # every definition and overwrites every verdict from measurement. The checks below narrow what a
    # fabricated row can claim — its commit must be an ancestor of HEAD, its failing examples must name
    # spec files that exist, its proof and target bytes must match the tree — but they do not replace
    # regeneration and this comment no longer says they do.
    # EVERY FIELD A ROW CARRIES, not a chosen subset.
    #
    # The list used to enumerate fifteen names while the real ledger carried seven more — `blocker`,
    # `description`, `landed`, `mechanism`, `mutant_ddl`, `table`, `trigger`. That is not merely
    # incomplete: `mechanism` STEERS THE VERIFIER, so appending `mechanism: "trigger"` to a correctly
    # sealed stale row switched the staleness check off without disturbing the binding. A bound-field
    # list beside a growing row shape is one more enumeration one case short, so the binding now
    # covers whatever the row actually has, with the digest itself excluded.
    UNBOUND = %w[binding_sha256].freeze

    def bound_fields(entry) = (entry.keys - UNBOUND).sort

    def canonical(entry)
      # Canonical encoding: sorted keys, no whitespace variance, so an equal row hashes equally
      # whatever order the generator wrote its keys in.
      JSON.generate(bound_fields(entry).to_h { |k| [k, entry[k]] })
    end

    def binding_for(entry) = Digest::SHA256.hexdigest(canonical(entry))

    def proof_digest(entry, root:)
      files = entry["proof"].to_s.split(/\s+/).map { |arg| arg.split(":").first }.reject(&:empty?)
      material = files.sort.map { |f| [f, File.exist?(File.join(root, f)) ? File.read(File.join(root, f)) : ""] }
      Digest::SHA256.hexdigest(JSON.generate([entry["proof"], material]))
    end

    def binding_errors(entry, root:, trigger_definition: nil)
      errors = []
      errors << "carries no binding_sha256, so its verdict is bound to nothing" if entry["binding_sha256"].nil?
      errors << "records no verdict" if entry["verdict"].nil?
      errors << "records verdict `broken`, which proves nothing: the run aborted before any example ran" if
        entry["verdict"] == "broken"

      # A trigger row's `file_sha256` is the digest of the ORIGINAL TRIGGER DEFINITION as the
      # catalogue reported it, not of a file. The first version compared that field TO ITSELF, so for
      # ten of fifty-nine rows the verifier performed no staleness check at all on the thing the
      # verdict was measured against — while the comment above claimed it did. The caller supplies a
      # reader for the live definition; without one the row is reported as UNVERIFIABLE rather than
      # silently passed.
      actual_file =
        if entry["mechanism"] == "trigger"
          if trigger_definition.nil?
            errors << "is a trigger mutation and no live definition reader was supplied, so its " \
                      "staleness cannot be checked; pass `trigger_definition:` to verify it"
            entry["file_sha256"]
          else
            live = trigger_definition.call(entry["trigger"], entry["table"]).to_s
            live.empty? ? nil : Digest::SHA256.hexdigest(live)
          end
        elsif File.exist?(File.join(root, entry["file"].to_s))
          Digest::SHA256.hexdigest(File.read(File.join(root, entry["file"])))
        end
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

      # THE COMMIT RECORDS PROVENANCE AND MUST BE REACHABLE — not equal to HEAD.
      #
      # Requiring equality was unsatisfiable and I had to watch it fail to see why: regenerating the
      # ledger produces a file that must itself be committed, which moves HEAD, which invalidates
      # every row that was just measured. Provenance is the property that can hold: the row names a
      # commit this history actually contains. Byte-level staleness — the thing that would make a
      # verdict wrong — is caught by `file_sha256` and `proof_sha256`, which compare against the
      # working tree and do not care what HEAD is.
      recorded_commit = entry["commit"].to_s
      if recorded_commit.empty?
        errors << "records no commit, so its verdict has no provenance"
      else
        _, status = Open3.capture2e("git", "-C", root, "merge-base", "--is-ancestor",
                                    recorded_commit, "HEAD")
        unless status.success?
          errors << "was measured at commit #{recorded_commit[0, 12]}, which is not an ancestor of " \
                    "HEAD; the verdict comes from a history this branch does not contain"
        end
      end

      # A kill must name failing examples that EXIST. A fabricated row naming invented spec paths is
      # rejected here even though its binding is internally consistent.
      Array(entry["failing_examples"]).each do |identity|
        # RSpec identifies an example either as `path:line` or, for a grouped example, as
        # `path[1:2:3]`. Both suffixes have to come off before the path is a path — the first version
        # split on ":" alone and turned `spec/x.rb[1:2:3]` into `spec/x.rb[1`, rejecting rows that
        # were perfectly true.
        file = identity.to_s.sub(/\[[\d:]+\]\z/, "").split(":").first
        next if File.exist?(File.join(root, file))

        errors << "records a failing example in #{file}, which does not exist"
      end

      recomputed = binding_for(entry)
      if recomputed != entry["binding_sha256"]
        errors << "its binding does not match its own contents (recorded #{entry['binding_sha256'].to_s[0, 12]}, " \
                  "recomputed #{recomputed[0, 12]}); the row is fabricated, transplanted or edited"
      end
      errors
    end

    # REPLAY A TRIGGER MUTATION, so a database-level claim is measured rather than declared.
    #
    # WHAT THIS CLOSES. The four D4 trigger mutations were written into the ledger VERBATIM by the
    # regeneration task and never passed through `replay`, `seal` or either verifier — an unbound
    # channel sitting beside the bound one, carrying `expectation: "kill"` with no verdict and no
    # gate. `d4-column-dropped` was false for four of the seven columns, and nothing could have said
    # so. That is round 9's self-report defect in a second place, and D5 family 5 closed only the
    # first.
    #
    # The mutation is applied as DDL, the bound proof is run, and the ORIGINAL definition is restored
    # from what the catalogue reported before the change — never from a literal in the ledger, so a
    # wrong restoration cannot be written into the record it is supposed to be checked against.
    def replay_trigger(entry, root:, env: {}, database: nil, superuser: nil)
      db = database || env["F1_DATABASE_NAME"] || raise("replay_trigger needs a database")
      su = superuser || ENV.fetch("USER")
      name = check_identifier!(entry.fetch("trigger"), "trigger")
      table = check_identifier!(entry.fetch("table"), "table")
      # SCOPED TO THE TABLE. Trigger names are unique per table, not per database, so identifying by
      # name alone could capture — and later "restore" — an arbitrary row.
      original = pg_value(db, su, <<~SQL).strip
        SELECT pg_get_triggerdef(t.oid) FROM pg_trigger t
        JOIN pg_class c ON c.oid = t.tgrelid
        WHERE t.tgname = '#{name}' AND c.relname = '#{table}' AND NOT t.tgisinternal
      SQL
      # THE WHOLE TABLE'S TRIGGER SET, not just the one being mutated. A `mutant_ddl` that creates or
      # drops anything else would otherwise persist while the row recorded `"restored": true` — which
      # it did: a one-character typo in a trigger name left the mutant installed after a "successful"
      # replay.
      before_set = trigger_set(db, su, table)
      raise "#{entry['id']}: trigger #{name} does not exist" if original.empty?

      pg_exec(db, "f1_schema_owner", "DROP TRIGGER #{name} ON #{table}; #{entry.fetch('mutant_ddl')}")
      landed = pg_value(db, su, "SELECT pg_get_triggerdef(oid) FROM pg_trigger WHERE tgname = '#{name}' " \
                                "AND NOT tgisinternal").strip != original
      begin
        output, status = Open3.capture2e(env.transform_keys(&:to_s), "bundle", "exec", "rspec",
                                         *entry.fetch("proof").split(/\s+/), chdir: root)
        summary = output[/(\d+) examples?, (\d+) failures?/]
        examples, failures = summary&.scan(/\d+/)&.map(&:to_i)
        verdict =
          # `broken` MEANS WHAT ITS MESSAGE SAYS: no example ran. An `after(:suite)` error is NOT that —
          # and treating it as such misclassified two real kills, because the mutation they apply also
          # trips `AuthoritySentinel`'s suite-wide rule, so the run reports both a failing example and
          # a suite-level error. A mutation that kills its proof AND trips a suite-wide invariant is
          # the strongest possible kill, and it was being recorded as proving nothing.
          if summary.nil? || examples.to_i.zero?
            "broken"
          elsif failures.to_i.positive? then "killed"
          elsif status.success? then "survived"
          else "broken"
          end
        { "id" => entry["id"], "landed" => landed, "verdict" => verdict, "result" => summary,
          "failing_examples" => output.scan(%r{^rspec '?\./(spec/[^'\s]+)}).flatten.uniq,
          "failure_digest" => failure_digest(output),
          "file_sha256" => Digest::SHA256.hexdigest(original),
          "proof_sha256" => proof_digest(entry, root:),
          "commit" => Open3.capture2e("git", "-C", root, "rev-parse", "HEAD").first.strip,
          "restored" => true }
      ensure
        pg_exec(db, "f1_schema_owner", "DROP TRIGGER IF EXISTS #{name} ON #{table}; #{original};")
        after_set = trigger_set(db, su, table)
        unless after_set == before_set
          raise "#{entry['id']}: TRIGGER RESTORE FAILED — #{table}'s trigger set differs from what it " \
                "was before the replay.\n  before: #{before_set.inspect}\n  after:  #{after_set.inspect}"
        end
      end
    end

    # A DIGEST OF WHY THE PROOF FAILED, not of the word "Failure".
    #
    # The first version scanned for `/^\s*Failure\/Error:.*/`, and RSpec puts NOTHING after that colon
    # when the expectation spans several lines — which is the dominant style here. Four mutations in
    # four different files, killing four different examples, therefore shared one digest:
    # `sha256("     Failure/Error:")`. A field whose stated job is "a proof that starts failing for an
    # unrelated reason must not keep a verdict it earned for the right one" was carrying no reason.
    #
    # It now captures the failing example identities, the exception classes and messages, and the
    # assertion text RSpec prints under each header — so two different failures cannot collide.
    def failure_digest(output)
      material = output.scan(/^\s*\d+\)\s+.+$/) +
                 output.scan(/^\s*[A-Z]\w*(?:::\w+)*(?:Error|Exception|Violation):.*$/) +
                 output.scan(/^\s*(?:expected|got|Diff:|# ---).*$/) +
                 output.scan(%r{^rspec '?\./(spec/[^'\s]+)})
      Digest::SHA256.hexdigest(material.flatten.join("\n"))
    end

    # NO SUBPROCESS. An earlier version shelled out to `psql` with the statement in `-c`. It used the
    # argv form, so no shell ever saw it, but it still handed a string assembled from a JSON file this
    # module exists to DISTRUST to an external program — and Brakeman was right to call that a command
    # injection surface. Connecting directly removes the surface rather than suppressing the finding:
    # there is no process to inject into, no PATH to manipulate, and no shell.
    #
    # The identifiers are validated anyway, because a ledger entry is untrusted input and DDL cannot
    # be parameterised: a trigger or table name is only ever a plain SQL identifier here.
    IDENTIFIER = /\A[a-z_][a-z0-9_]*\z/

    def check_identifier!(value, what)
      return value if value.to_s.match?(IDENTIFIER)

      raise "#{what} #{value.inspect} is not a plain SQL identifier; a ledger entry may not carry " \
            "arbitrary SQL in a name position"
    end

    def pg_exec(db, user, sql)
      require "pg"
      conn = PG.connect(host: ENV.fetch("F1_DATABASE_HOST", "localhost"),
                        port: ENV.fetch("F1_DATABASE_PORT", "5433"), user:, dbname: db)
      begin
        conn.exec(sql)
      ensure
        conn.close
      end
    end

    # Every non-internal trigger on the table, as definition text. Compared whole, so a replay that
    # adds, drops or alters ANY trigger on the table is caught rather than only the named one.
    def trigger_set(db, user, table)
      result = pg_exec(db, user, <<~SQL)
        SELECT pg_get_triggerdef(t.oid) AS def FROM pg_trigger t
        JOIN pg_class c ON c.oid = t.tgrelid
        WHERE c.relname = '#{table}' AND NOT t.tgisinternal
        ORDER BY t.tgname
      SQL
      result.map { |row| row["def"] }.sort
    end

    def pg_value(db, user, sql)
      result = pg_exec(db, user, sql)
      result.ntuples.zero? ? "" : result.getvalue(0, 0).to_s
    end

    # Seal a completed row. Called by the generator AFTER the replay, so the binding covers the
    # measured outcome rather than the intention.
    def seal(entry) = entry.merge("binding_sha256" => binding_for(entry))

    def verify_bindings!(entries, root:, trigger_definition: nil)
      failures = entries.flat_map do |e|
        binding_errors(e, root:, trigger_definition:).map { |r| "#{e['id']}: #{r}" }
      end
      raise "mutation ledger verdict bindings are invalid:\n#{failures.join("\n")}" unless failures.empty?

      true
    end

    def trigger_applicability_errors(entry, root:)
      errors = []
      errors << "names no trigger" if entry["trigger"].to_s.empty?
      errors << "names no mutant_ddl" if entry["mutant_ddl"].to_s.empty?
      missing = entry["proof"].to_s.split(/\s+/).map { |a| a.split(":").first }
                     .reject { |f| f.empty? || File.exist?(File.join(root, f)) }
      errors.concat(missing.map { |f| "names proof #{f}, which does not exist" })
      errors
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
        #
        # AND AN `after(:suite)` ERROR IS NOT "NO EXAMPLE RAN" (D7). The round-two repair established
        # exactly this and applied it to `replay_trigger` ALONE, leaving the file path — which carries
        # 79 of the 89 definitions — still treating an outside error as `broken`. Measured here: both
        # `d7-door-regex-restored` (13 examples, 7 failures) and `d7-antecedent-dropped` (13 examples,
        # 1 failure) trip `AuthoritySentinel`'s suite-wide rule as well as failing their proof, which
        # is the STRONGEST possible kill, and both were recorded as proving nothing. A repair applied
        # to one of two paths is the enumeration defect one level up.
        verdict =
          if summary.nil? || examples.to_i.zero?
            "broken"
          elsif failures.to_i.positive? then "killed"
          elsif status.success? && !output.include?("error occurred outside of examples") then "survived"
          else "killed"
          end
        failing = output.scan(%r{^rspec '?\./(spec/[^'\s]+)}).flatten.uniq
        { "id" => entry["id"], "landed" => landed, "verdict" => verdict, "result" => summary,
          "failing_examples" => failing,
          # THE REASON, not just the count. A proof that starts failing for an unrelated reason must
          # not keep a verdict it earned for the right one.
          "failure_digest" => failure_digest(output),
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
