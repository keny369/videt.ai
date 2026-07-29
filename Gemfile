source "https://rubygems.org"

# ---------------------------------------------------------------------------
# F1 runtime baseline. These versions are the frozen Volume II runtime contract
# in architecture/RAILS_APPLICATION_ARCHITECTURE.md and are pinned exactly. A
# change here is a compatibility-tested runtime-baseline change, never incidental.
# ---------------------------------------------------------------------------

ruby file: ".ruby-version"

gem "rails", "8.1.3.1"

# Persistence: PostgreSQL 17 only. No SQLite, no second datastore.
gem "pg", "1.6.3"

# Web server.
gem "puma", "8.0.2"

# Background runtime: Sidekiq on Valkey/Redis (never Solid Queue).
gem "sidekiq", "8.1.6"
gem "redis-client", "0.30.0"
gem "connection_pool", "3.0.2"

# Asset pipeline: Propshaft + Importmap. No Node runtime, no JS bundler.
gem "propshaft"
gem "importmap-rails"

# Hotwire.
gem "turbo-rails", "2.0.23"
gem "stimulus-rails", "1.3.4"

# Bounded-context package enforcement.
gem "packwerk", "3.3.0"

# Boot cache.
gem "bootsnap", require: false

# Windows/JRuby zoneinfo (no-op on the Linux/macOS baseline).
gem "tzinfo-data", platforms: %i[windows jruby]

group :development, :test do
  # Canonical test framework (RSpec, not Minitest).
  gem "rspec-rails", "8.0.4"
  gem "factory_bot_rails", "6.5.1"

  gem "debug", platforms: %i[mri windows], require: "debug/prelude"

  # Security scanning wired into the CI quality gates.
  gem "bundler-audit", require: false
  gem "brakeman", require: false

  # Ruby styling.
  gem "rubocop-rails-omakase", require: false
end

group :test do
  # System / accessibility stack: Capybara + Cuprite (headless Chromium) + axe.
  gem "capybara", "3.40.0"
  gem "cuprite", "0.17"
  gem "axe-core-capybara", "4.12.0"
end

group :development do
  gem "web-console"
end
