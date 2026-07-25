# frozen_string_literal: true

module AutonomousBuild
  # Frozen foundations are consumed, not modified (mandate §3.9, §7.1). F-01..F-04 are reachable only
  # through their frozen public façades; any change to a foundation façade, its adapter internals, or
  # its single-surface fitness spec is a MANDATORY human escalation — the controller never edits a
  # frozen contract on its own. (An already-ratified Evolution Rule could permit a specific change;
  # version one has none, so every match escalates.)
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

    def frozen_path?(path) = FROZEN.any? { |re| path.match?(re) }

    # The subset of changed files that touch a frozen foundation.
    def frozen_changes(changed_files) = changed_files.select { |p| frozen_path?(p) }

    def modifies_frozen?(changed_files) = frozen_changes(changed_files).any?
  end
end
