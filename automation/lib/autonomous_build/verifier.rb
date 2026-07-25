# frozen_string_literal: true

module AutonomousBuild
  # Deterministic verification (mandate §3.7, §10; VERIFICATION_MANIFEST.yml). Verification is
  # tooling, not model opinion: the verifier resolves the required check set for a tranche (always
  # -required plus the sets selected by the changed paths), runs each real command, and returns a
  # schema-valid verifier result. A `pass` is invalid if any mandatory check is missing or was not
  # actually run — model prose can never substitute for an objective check (§13). A check that is
  # `covered_by` another (no dedicated tool) is recorded, not independently run.
  class Verifier
    def initialize(manifest:, runner: CommandRunner.new, clock: -> { Time.now.utc })
      @manifest = manifest
      @runner = runner
      @clock = clock
    end

    def self.load_manifest(path)
      YAML.safe_load_file(path)
    end

    # Resolve the ordered, de-duplicated list of check definitions for a tranche given its changed
    # paths. always_required is always included; a path-matched set is included when any changed path
    # matches one of its match_paths.
    def resolve_checks(changed_paths)
      sets = @manifest.fetch("check_sets")
      selected = ["always_required"]
      sets.each do |name, definition|
        next if name == "always_required"

        patterns = definition["match_paths"] || []
        selected << name if changed_paths.any? { |p| patterns.any? { |pat| path_matches?(pat, p) } }
      end
      selected.uniq.flat_map { |name| checks_for(sets, name) }
    end

    # Run the resolved checks and return a validated verifier result hash.
    def run(run_id:, block_id:, tranche_id:, verified_commit:, changed_paths:)
      definitions = resolve_checks(changed_paths)
      results = definitions.map { |check| run_check(check) }

      mandatory = definitions.select { |c| c["mandatory"] }.map { |c| c["id"] }
      ran_ids = results.reject { |r| r[:skipped] }.map { |r| r[:id] }
      missing = mandatory - ran_ids - covered_ids(definitions)
      failed = results.select { |r| r[:status] == "fail" }

      status =
        if !missing.empty? then "incomplete"
        elsif failed.any? then "fail"
        else "pass"
        end

      Schema.validate("verifier", {
        "schema_version" => 1, "role" => "verifier", "run_id" => run_id, "block_id" => block_id,
        "tranche_id" => tranche_id, "status" => status, "generated_at" => @clock.call.iso8601,
        "verified_commit" => verified_commit,
        "checks" => results.map { |r| r.reject { |k, _| k == :status || k == :skipped }.transform_keys(&:to_s).merge("status" => r[:status]) },
        "required_checks" => mandatory,
        "missing_checks" => missing,
        "summary" => summary(status, failed, missing)
      })
    end

    private

    def checks_for(sets, name)
      return sets[name] if sets[name].is_a?(Array) # always_required is a bare list

      sets.dig(name, "checks") || []
    end

    def covered_ids(definitions)
      definitions.select { |c| c["type"] == "covered_by" || c["command"].nil? }.map { |c| c["id"] }
    end

    def run_check(check)
      if check["type"] == "covered_by" || check["command"].nil?
        return { id: check["id"], command: nil, exit_status: nil, duration_seconds: 0,
                 output_ref: "covered_by:#{check['covered_by']}", status: "covered", skipped: true }
      end

      result = @runner.run(check["command"], timeout: check["timeout_seconds"] || 3600)
      passed = result.success? && !(check["expect_empty_stdout"] && !result.output.strip.empty?)
      {
        id: check["id"], command: result.command, exit_status: result.exit_status,
        duration_seconds: result.duration_seconds,
        output_ref: truncate(result.output), status: passed ? "pass" : "fail", skipped: false
      }
    end

    # File.fnmatch does not treat a trailing /** as recursive; handle it as a directory prefix.
    def path_matches?(pattern, path)
      if pattern.end_with?("/**")
        path == pattern.delete_suffix("/**") || path.start_with?(pattern.delete_suffix("**"))
      else
        File.fnmatch?(pattern, path, File::FNM_PATHNAME | File::FNM_EXTGLOB) ||
          File.fnmatch?(pattern, path, File::FNM_EXTGLOB)
      end
    end

    def truncate(output, limit: 4000)
      out = output.to_s
      out.length > limit ? "#{out[0, limit]}\n...[truncated #{out.length - limit} chars]" : out
    end

    def summary(status, failed, missing)
      return "all required checks passed" if status == "pass"
      return "missing required checks: #{missing.join(', ')}" if status == "incomplete"

      "failed checks: #{failed.map { |f| f[:id] }.join(', ')}"
    end
  end
end
