# frozen_string_literal: true

module AutonomousBuild
  # Frozen foundations are consumed, not modified (mandate §3.9, §7.1). F-01..F-04 are reachable only
  # through their frozen public façades; any change to a foundation façade, its adapter internals, or
  # its single-surface fitness spec is a MANDATORY human escalation — the controller never edits a
  # frozen contract on its own.
  #
  # ONE ratified evolution rule (DECISIONS.md ADR-027/ADR-029): the runtime privilege manifest
  # `lib/f1/runtime_grants.rb` is frozen because it is security-critical, but its own charter requires
  # a new grant entry for EVERY new tenant table, so every product slice that adds a table must extend
  # it. A change to it is a backwards-compatible extension that does NOT escalate ONLY when it proves,
  # against the base version of the file, that it: (a) removes/modifies no existing line; (b) adds only
  # comments/blank lines and `"table" => "<privs>"` entries; (c) grants each new table ONLY privileges
  # in the least-privilege allowlist {SELECT, INSERT, UPDATE} — never DELETE, TRUNCATE, REFERENCES,
  # TRIGGER, ALL, or any other privilege; and (d) adds only GENUINELY NEW table keys, never a duplicate
  # that Ruby's last-value-wins semantics would use to silently widen an existing table's grant. Any
  # other change to it, and every OTHER frozen path, escalates. The classifier FAILS CLOSED: without
  # both the diff and the base content, or on anything it cannot prove safe, it escalates.
  module FrozenContracts
    module_function

    # Repo-relative path patterns that constitute a frozen-foundation surface.
    FROZEN = [
      %r{\Aapp/platform/outbound\.rb\z}, %r{\Aapp/platform/outbound/},
      %r{\Aapp/platform/encryption\.rb\z}, %r{\Aapp/platform/encryption/},
      %r{\Aapp/platform/evidence\.rb\z}, %r{\Aapp/platform/evidence/},
      %r{\Aapp/platform/background_execution\.rb\z}, %r{\Aapp/platform/scheduled_actions/},
      %r{\Aspec/architecture/.*_single_surface_spec\.rb\z},
      %r{\Alib/f1/runtime_grants\.rb\z}
    ].freeze

    # Frozen paths that permit a ratified, purely-additive backwards-compatible extension WITHOUT
    # escalation. Only the runtime privilege manifest qualifies today (ADR-027/ADR-029).
    ADDITIVE_EXCEPTION = [
      %r{\Alib/f1/runtime_grants\.rb\z}
    ].freeze

    # The ONLY privileges a table grant may confer — an allowlist, not a denylist, so a broad or
    # destructive privilege (DELETE, TRUNCATE, ALL, REFERENCES, TRIGGER, …) never passes as "additive".
    SAFE_PRIVILEGES = %w[SELECT INSERT UPDATE].freeze

    # Unified-diff metadata lines (headers/hunks), matched precisely so a real content line beginning
    # with `+`/`-` after its diff prefix is never mistaken for a header.
    DIFF_METADATA = /\A(\+\+\+ |--- |@@|diff |index |new file|deleted file|rename |similarity |Binary )/

    GRANT_ENTRY = /\A"([^"]+)"\s*=>\s*"([A-Z][A-Z, ]*)",?\z/
    GRANT_KEY = /\A"([^"]+)"\s*=>/

    def frozen_path?(path) = FROZEN.any? { |re| path.match?(re) }
    def additive_exception_path?(path) = ADDITIVE_EXCEPTION.any? { |re| path.match?(re) }

    # The subset of changed files that touch a frozen foundation (path-level; no content judgment).
    def frozen_changes(changed_files) = changed_files.select { |p| frozen_path?(p) }

    def modifies_frozen?(changed_files) = frozen_changes(changed_files).any?

    # The subset of frozen changes that MUST escalate. A frozen path with a ratified additive exception
    # whose change is PROVEN a safe additive extension (via the diff and the base content) does not
    # escalate; every other frozen change does. Fails closed.
    def escalating_frozen_changes(changed_files, diff_provider: nil, base_content_provider: nil)
      frozen_changes(changed_files).reject do |path|
        additive_exception_path?(path) && diff_provider &&
          additive_grant_change?(diff_provider.call(path), base_content: base_content_provider&.call(path))
      end
    end

    def escalates?(changed_files, diff_provider: nil, base_content_provider: nil)
      escalating_frozen_changes(changed_files, diff_provider:, base_content_provider:).any?
    end

    # True only for a proven-safe additive grant extension. See the module comment for the four
    # conditions. `base_content` is the file at the base commit, used to prove genuine new-table-ness.
    def additive_grant_change?(diff, base_content: nil)
      return false if diff.nil?

      added = []
      diff.to_s.each_line do |line|
        next if line.match?(DIFF_METADATA)
        if line.start_with?("+")
          added << line[1..].to_s.strip
        elsif line.start_with?("-")
          return false # a removed or modified existing line is not purely additive
        end
      end
      return false if added.empty?
      return false unless added.all? { |body| additive_grant_line?(body) }

      # Every added grant must name a GENUINELY NEW table key. A duplicate key (last-value-wins) would
      # silently override an existing table's privileges as a pure "addition". Proving newness needs the
      # base file; without it, fail closed.
      added_keys = added.filter_map { |b| b[GRANT_KEY, 1] }
      return true if added_keys.empty? # comments/blank lines only — harmless

      # Prove newness against the base file. Fail closed if the base is missing OR yields no existing
      # keys at all (an empty or unparseable manifest would make every duplicate read as "new").
      existing = existing_grant_keys(base_content)
      return false if existing.empty?

      added_keys.none? { |k| existing.include?(k) }
    end

    # A single added line that is safe: a comment, a blank line, or a `"table" => "…"` entry that
    # grants ONLY allowlisted privileges.
    def additive_grant_line?(body)
      return true if body.empty? || body.start_with?("#")

      match = body.match(GRANT_ENTRY) or return false
      match[2].split(",").map(&:strip).all? { |priv| SAFE_PRIVILEGES.include?(priv) }
    end

    # The table keys already present in the base file (any `"key" =>` entry), so a re-added key is
    # detected as a modification rather than an addition. This relies on `TABLE_PRIVILEGES` being the
    # ONLY string-keyed hash in the manifest (verified today); if a second string-keyed hash is ever
    # added to `runtime_grants.rb`, scope this to the `TABLE_PRIVILEGES` block. Grant and comment lines
    # begin with `"` / `#`, so they never collide with the `+++ `/`--- ` diff-metadata prefixes above.
    def existing_grant_keys(base_content)
      base_content.to_s.scan(/^\s*"([^"]+)"\s*=>/).flatten
    end
  end
end
