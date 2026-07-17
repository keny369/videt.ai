# Loaded by every example that needs Rails. The test database schema is prepared
# out of band by the schema owner (bin/f1db db:test:prepare); the runtime test
# role f1_web has no DDL and cannot maintain a schema, which is exactly the
# property TESTING_ARCHITECTURE.md requires us to preserve.
require "spec_helper"
ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
abort("The Rails environment is running in production mode!") if Rails.env.production?
require "rspec/rails"

# Support files (matchers, shared contexts, harness). Never name one *_spec.rb.
Rails.root.glob("spec/support/**/*.rb").sort_by(&:to_s).each { |f| require f }

# Fail loudly if the owner-prepared test schema is behind the migration set,
# without attempting any DDL from the runtime role.
begin
  ActiveRecord::Migration.check_all_pending!
rescue ActiveRecord::PendingMigrationError => e
  abort "#{e.message.strip}\nRun: bin/f1db db:test:prepare"
end

RSpec.configure do |config|
  config.use_transactional_fixtures = true
  config.filter_rails_from_backtrace!

  # The frozen test runtime is deterministic: UTC clock, en-AU locale.
  config.before(:suite) do
    Time.zone = "UTC"
    I18n.locale = :"en-AU" if I18n.available_locales.include?(:"en-AU")
  end
end
