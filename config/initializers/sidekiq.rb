# frozen_string_literal: true

require "sidekiq"

# F-04 Background Execution operational wiring (FOUNDATION-004 property 10;
# BACKGROUND_PROCESSING.md :7-10, :46-47). Sidekiq is TRANSPORT ONLY — PostgreSQL is the
# sole timer/lease/idempotency authority. Sidekiq automatic retry and the Dead set are
# disabled for every F1 job (each job also declares `retry: false, dead: false`); the
# PostgreSQL infrastructure-retry schedule and quarantine are exclusive. Loss, duplication,
# reordering and delayed delivery are recovered from persisted leases and idempotency
# identities, never from Sidekiq/Redis controls.
redis_url = ENV.fetch("REDIS_URL", "redis://127.0.0.1:6379/0")

# Production MUST use an authenticated TLS Redis/Valkey (rediss://); plaintext is restricted to
# development and test. The envelope carries only opaque identifiers, but transport-level auth+TLS
# is a ratified requirement — fail startup rather than run plaintext in production. (Never echo the
# URL: it may carry credentials — report only the scheme.)
if Rails.env.production? && !redis_url.start_with?("rediss://")
  raise "F1 production requires an authenticated TLS Redis URL (rediss://); refusing to start on " \
        "#{redis_url.split('://').first}:// transport"
end

Sidekiq.configure_client do |config|
  config.redis = { url: redis_url }
end

Sidekiq.configure_server do |config|
  config.redis = { url: redis_url }
end

# Belt-and-suspenders alongside each job's own options: never auto-retry, never dead-set.
#
# This is a MODULE-level default, not a server-config one, and it is set outside both
# blocks on purpose. `Sidekiq::Job::ClassMethods` seeds a job class's options from
# `Sidekiq.default_job_options` and `Sidekiq::JobUtil` normalizes every enqueued job
# against it, so the default has to exist in the CLIENT process (the web process that
# enqueues) as much as in the server, and `Sidekiq::Config` has no such writer at all.
# Written as `config.default_job_options =` inside `configure_server` it raised
# NoMethodError on boot, which no test caught because nothing in the suite boots a
# Sidekiq server process: every worker process died at startup, so the scheduler
# dispatched work to queues that had no live consumer and every Crawl stayed `queued`.
Sidekiq.default_job_options = { "retry" => false, "dead" => false }
