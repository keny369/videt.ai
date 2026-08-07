# frozen_string_literal: true

require "rails_helper"

# F-04 Background Execution — the Sidekiq initializer must survive being loaded BY A
# SERVER PROCESS, not only by a client one.
#
# WHY THIS EXISTS. `Sidekiq.configure_server` yields only when `Sidekiq.server?`, which is
# false in every web process and in this suite. So the server half of
# `config/initializers/sidekiq.rb` was never executed by anything: it called a writer
# `Sidekiq::Config` does not have, every `bundle exec sidekiq` died at boot with
# NoMethodError, and the failure was invisible from the application's side. The scheduler
# went on claiming due work and enqueueing it to queues with no live consumer, so a Crawl
# queued from the product simply stayed `queued` — a completely green suite over a
# background runtime that could not start.
#
# The check is the real one: force the server role and load the initializer, which is
# exactly the sequence a worker process performs.
RSpec.describe "Sidekiq server boot", type: :model do
  let(:initializer) { Rails.root.join("config/initializers/sidekiq.rb") }

  it "loads cleanly in the server role, as `bundle exec sidekiq` does" do
    allow(Sidekiq).to receive(:server?).and_return(true)

    expect { load initializer }.not_to raise_error
  end

  it "disables Sidekiq retry and the Dead set for every job, in client processes too" do
    # PostgreSQL owns retry and quarantine (BACKGROUND_PROCESSING.md :7). Sidekiq's own
    # retry would be a second, competing schedule. The default has to hold in the WEB
    # process, which is the one that enqueues, so it cannot live inside `configure_server`.
    expect(Sidekiq.default_job_options).to include("retry" => false, "dead" => false)
  end

  it "still refuses plaintext Redis in production" do
    allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new("production"))
    allow(ENV).to receive(:fetch).and_call_original
    allow(ENV).to receive(:fetch).with("REDIS_URL", anything).and_return("redis://127.0.0.1:6379/0")

    expect { load initializer }.to raise_error(/authenticated TLS Redis URL/)
  end

  # The committed per-queue configs a deployment actually runs. Each names exactly one
  # queue at the ratified concurrency; a process that listens to two queues, or a queue
  # with no committed process, is the defect this pins.
  describe "the committed worker configs" do
    {
      "config/sidekiq.yml" => ["control", 3],
      "config/sidekiq_crawl.yml" => ["crawl", 10],
      "config/sidekiq_pipeline.yml" => ["pipeline", 5],
      "config/sidekiq_lifecycle.yml" => ["lifecycle", 2]
    }.each do |path, (queue, concurrency)|
      it "#{path} owns exactly the #{queue} queue at concurrency #{concurrency}" do
        config = YAML.safe_load_file(Rails.root.join(path), permitted_classes: [Symbol], aliases: true)

        expect(config[:queues]).to eq([queue])
        expect(config[:concurrency]).to eq(concurrency)
      end
    end

    it "has a committed process for every queue the action catalogue dispatches to" do
      registry = Platform::ScheduledActions::Registry.default
      dispatched = Platform::ScheduledActions::Catalogue.kinds
                                                       .select { |kind| registry.kind_registered?(kind) }
                                                       .map { |kind| Platform::ScheduledActions::Catalogue.queue_for(kind) }
                                                       .uniq
      committed = Dir[Rails.root.join("config/sidekiq*.yml")].flat_map do |path|
        config = YAML.safe_load_file(path, permitted_classes: [Symbol], aliases: true)
        Array(config[:queues]) + config.fetch(:capsules, {}).values.flat_map { |c| Array(c[:queues]) }
      end.uniq

      expect(dispatched - committed).to be_empty,
                                        "these queues receive dispatched work and no committed process consumes them: " \
                                        "#{(dispatched - committed).join(", ")}"
    end
  end
end
