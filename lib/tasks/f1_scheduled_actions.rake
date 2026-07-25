# frozen_string_literal: true

# F-04 Background Execution — the committed scheduler entrypoint (BACKGROUND_PROCESSING.md :67,
# :116). The `scheduler` is a separate, LONG-LIVED singleton process, not a Sidekiq worker. This
# is the ONLY committed way to run it, and it is singleton-guarded: it acquires
# Platform::ScheduledActions::SchedulerLease ONCE and holds it for the process lifetime while it
# loops, so a second scheduler process cannot acquire the lease and exits without dispatching.
# Running more than one EFFECTIVE scheduler requires the full leader-election lease (G6, deferred).
#
# A deployment runs exactly one instance:
#   bundle exec rake f1:scheduled_actions:run
namespace :f1 do
  namespace :scheduled_actions do
    desc "Run the singleton scheduler: hold the leader lease and loop (recover leases, dispatch due)"
    task run: :environment do
      outcome = Platform::BackgroundExecution.run_scheduler(
        on_pass: ->(r) { puts "[f1.scheduler] recovered=#{r[:recovered]} dispatched=#{r[:dispatched]}" }
      )
      warn "[f1.scheduler] another scheduler already holds the leader lease; exiting" if outcome == :not_leader
    end
  end
end
