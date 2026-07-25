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
  # it. A PURELY ADDITIVE new-table grant (no existing grant changed, no line removed, no DELETE
  # introduced, FORCE RLS untouched) is a backwards-compatible extension under the Foundation
  # Consumption Rule and does NOT escalate; any other change to it — a new DELETE, a widened role, a
  # modified or removed existing grant, or an unparseable change — still escalates, and every OTHER
  # frozen path escalates unconditionally. The classifier fails closed.
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

    def frozen_path?(path) = FROZEN.any? { |re| path.match?(re) }
    def additive_exception_path?(path) = ADDITIVE_EXCEPTION.any? { |re| path.match?(re) }

    # The subset of changed files that touch a frozen foundation (path-level; no content judgment).
    def frozen_changes(changed_files) = changed_files.select { |p| frozen_path?(p) }

    def modifies_frozen?(changed_files) = frozen_changes(changed_files).any?

    # The subset of frozen changes that MUST escalate. A frozen path with a ratified additive
    # exception whose change is PROVEN purely additive (via `diff_provider.call(path) -> unified diff`)
    # does not escalate; every other frozen change does. Fails closed: with no diff_provider, or a
    # change that cannot be proven additive, the path escalates.
    def escalating_frozen_changes(changed_files, diff_provider: nil)
      frozen_changes(changed_files).reject do |path|
        additive_exception_path?(path) && diff_provider && additive_grant_change?(diff_provider.call(path))
      end
    end

    def escalates?(changed_files, diff_provider: nil) = escalating_frozen_changes(changed_files, diff_provider:).any?

    # True only for a purely-additive change: a non-empty unified diff that REMOVES no line and whose
    # every added line is a comment, a blank line, or a least-privilege table-grant entry with no
    # DELETE. Any removal or modification of an existing line, any DELETE, or any added line that is
    # not a recognizable grant/comment fails the test (→ escalate).
    def additive_grant_change?(diff)
      return false if diff.nil?

      added = []
      diff.to_s.each_line do |line|
        next if line.start_with?("+++", "---", "diff ", "index ", "@@", "new file", "deleted file", "rename ")
        if line.start_with?("+")
          added << line[1..].to_s
        elsif line.start_with?("-")
          return false # a removed or modified existing line is not purely additive
        end
      end
      return false if added.empty?

      added.all? { |body| additive_grant_line?(body.strip) }
    end

    # A single added line that is safe in a purely-additive grant extension: a comment, a blank line,
    # or a `"table" => "SELECT, INSERT, UPDATE"` entry that grants no DELETE.
    def additive_grant_line?(body)
      return true if body.empty? || body.start_with?("#")
      return false if body.match?(/\bDELETE\b/i)

      body.match?(/\A"[^"]+"\s*=>\s*"[A-Z][A-Z, ]*",?\z/)
    end
  end
end
