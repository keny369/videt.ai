# frozen_string_literal: true

require "json"
require "yaml"
require "time"
require "fileutils"
require "securerandom"
require "open3"

# The F1 Autonomous Build Controller — repository-native, state-driven, bounded orchestration of the
# governed build programme (specification/automation/AUTONOMOUS_BUILD_CONTROLLER.md). Plain Ruby with
# NO Rails dependency: it must run and be testable even if the product app is broken, and it drives
# the app only as subprocesses (git, verification commands, provider adapters). Authoritative state
# is version-controlled files, never conversational memory (§3.1).
module AutonomousBuild
  VERSION = "0.1.0"

  # automation/lib/autonomous_build.rb -> repo root
  ROOT = File.expand_path("../..", __dir__)

  class Error < StandardError; end
  class InvalidState < Error; end
  class InvalidTransition < Error; end
  class SchemaError < Error; end
  class PolicyViolation < Error; end
  class UnsafePath < Error; end
  class LockError < Error; end
end

require_relative "autonomous_build/state_machine"
require_relative "autonomous_build/paths"
require_relative "autonomous_build/build_state"
