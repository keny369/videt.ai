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
require_relative "autonomous_build/schema"
require_relative "autonomous_build/redaction"
require_relative "autonomous_build/command_policy"
require_relative "autonomous_build/command_runner"
require_relative "autonomous_build/verifier"
require_relative "autonomous_build/adapters"
require_relative "autonomous_build/git"
require_relative "autonomous_build/controller_lock"
require_relative "autonomous_build/run_record"
require_relative "autonomous_build/frozen_contracts"
require_relative "autonomous_build/controller"
require_relative "autonomous_build/plan"
require_relative "autonomous_build/self_test"
require_relative "autonomous_build/cli"
