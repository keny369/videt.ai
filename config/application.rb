require_relative "boot"

require "rails"
# F1 is a modular monolith. We load only the frameworks the frozen architecture
# uses. Action Cable, Action Mailbox and Action Text are intentionally absent:
# RAILS_APPLICATION_ARCHITECTURE.md forbids Action Cable/WebSocket/SSE, and no
# baseline behaviour uses inbound mail or rich text.
require "active_model/railtie"
require "active_job/railtie"
require "active_record/railtie"
require "active_storage/engine"
require "action_controller/railtie"
require "action_mailer/railtie"
require "action_view/railtie"
require "sprockets/railtie" if false # never; Propshaft is the pipeline

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

# Namespace roots for the shared platform kernel and the workflow coordinators.
# app/platform maps to Platform::, app/workflows to Workflows::, and each
# app/contexts/<context> maps to its context constant (a plain root, no config),
# per architecture/RAILS_APPLICATION_ARCHITECTURE.md § Source Layout.
module Platform; end
module Workflows; end

module F1
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 8.1

    # `lib` holds only pure Ruby that is not autoloadable domain code.
    config.autoload_lib(ignore: %w[assets tasks])

    # app/platform is the Platform:: namespace root (a namespaced autoload dir,
    # not a plain root that would make app/platform/clock.rb resolve to ::Clock).
    # app/contexts is a plain root, so app/contexts/identity_access/... resolves
    # to IdentityAccess::... with no extra configuration.
    platform_dir = File.expand_path("../app/platform", __dir__)
    Rails.autoloaders.main.push_dir(platform_dir, namespace: Platform)
    workflows_dir = File.expand_path("../app/workflows", __dir__)
    Rails.autoloaders.main.push_dir(workflows_dir, namespace: Workflows)

    # The frozen baseline runs in UTC everywhere; product decisions use an
    # injected clock, never wall-clock in domain code (architecture fitness).
    config.time_zone = "UTC"
    config.active_record.default_timezone = :utc

    # Background runtime is Sidekiq. Solid Queue is prohibited as the Active Job
    # backend (architecture fitness check).
    config.active_job.queue_adapter = :sidekiq

    # The canonical schema uses SECURITY DEFINER functions, forced RLS policies,
    # partial and NULLS-NOT-DISTINCT indexes and CHECK vocabularies that the Ruby
    # schema DSL cannot represent. structure.sql is the authoritative dump, and
    # schema tests inspect pg_catalog (TESTING_ARCHITECTURE.md).
    config.active_record.schema_format = :sql

    # RSpec is the canonical framework; generators never emit Minitest, and we
    # do not scaffold unrequested helpers/assets.
    config.generators do |g|
      g.test_framework :rspec,
        fixtures: false,
        view_specs: false,
        helper_specs: false,
        routing_specs: false,
        controller_specs: false
      g.factory_bot dir: "spec/factories"
      g.system_tests = nil
      g.helper false
      g.assets false
    end
  end
end
