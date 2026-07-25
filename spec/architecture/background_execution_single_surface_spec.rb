# frozen_string_literal: true

require "rails_helper"

# F-04 Background Execution — the single-surface architecture fitness check (FOUNDATION-004;
# owner rule 2026-07-25). The same philosophy as outbound transport, encryption and evidence,
# applied to background execution: there is exactly ONE Sidekiq job and exactly ONE enqueue
# surface, so Sidekiq stays transport-only and no code reaches around the durable, binding-
# mediated dispatch. This fails CI the moment production code outside the adapter defines a second
# Sidekiq job, pushes to Redis directly, or bypasses the ExecutionJob/Dispatcher.
RSpec.describe "Background execution single-surface fitness", type: :model do
  # The transport adapter (the ScheduledActions module) and the frozen façade.
  def in_transport_module?(rel)
    rel.start_with?("app/platform/scheduled_actions/") || rel == "app/platform/background_execution.rb"
  end

  # Only the ExecutionJob may BE a Sidekiq job.
  def the_only_job_file?(rel) = rel == "app/platform/scheduled_actions/execution_job.rb"

  # Direct transport primitives that must live only inside the adapter — the Dispatcher is the
  # single enqueue surface, and only the ExecutionJob is a Sidekiq worker.
  ENQUEUE_PRIMITIVES = {
    "perform_async" => /\bperform_async\b/,
    "perform_in" => /\bperform_in\b/,
    "perform_at" => /\bperform_at\b/,
    "Sidekiq::Client" => /\bSidekiq::Client\b/,
    "Sidekiq.redis" => /\bSidekiq\.redis\b/,
    "Redis.new" => /\bRedis\.new\b/
  }.freeze

  SIDEKIQ_JOB = { "Sidekiq::Job" => /\bSidekiq::Job\b/ }.freeze

  def production_files
    (Dir[Rails.root.join("app/**/*.rb")] + Dir[Rails.root.join("lib/**/*.rb")]).sort
  end

  def relative(path) = Pathname.new(path).relative_path_from(Rails.root).to_s

  def scan(patterns)
    violations = []
    production_files.each do |path|
      rel = relative(path)
      yield_ok = block_given? && yield(rel)
      next if yield_ok

      File.read(path).each_line.with_index(1) do |line, number|
        next if line.lstrip.start_with?("#")

        patterns.each { |label, pattern| violations << "#{rel}:#{number} references #{label}" if line.match?(pattern) }
      end
    end
    violations
  end

  it "confines every Redis enqueue to the transport adapter — the Dispatcher is the single egress" do
    violations = scan(ENQUEUE_PRIMITIVES) { |rel| in_transport_module?(rel) }
    expect(violations).to be_empty, <<~MESSAGE
      Only the F-04 Dispatcher may enqueue to Redis (FOUNDATION-004 FROZEN contract). Schedule work
      with ScheduledActions::Store#create and let the scheduler dispatch it. These files push directly:
      #{violations.join("\n")}
    MESSAGE
  end

  it "confines Sidekiq::Job to the single ExecutionJob — no second durable-execution class" do
    violations = scan(SIDEKIQ_JOB) { |rel| the_only_job_file?(rel) }
    expect(violations).to be_empty, <<~MESSAGE
      ExecutionJob is the only Sidekiq job (FOUNDATION-004 FROZEN contract). All durable execution
      goes through the registered scheduled-action handler path, never an ad-hoc Sidekiq worker:
      #{violations.join("\n")}
    MESSAGE
  end

  it "disables Sidekiq retry and the Dead set on the one job (PostgreSQL owns retry and quarantine)" do
    options = Platform::ScheduledActions::ExecutionJob.sidekiq_options
    expect(options["retry"]).to be(false)
    expect(options["dead"]).to be(false)
  end

  it "carries identifiers only — the scalar envelope is exactly the eight ratified fields" do
    expect(Platform::ScheduledActions::Envelope::FIELDS).to contain_exactly(
      "schema_version", "organization_id", "work_type", "work_id",
      "product_generation", "claim_generation", "correlation_id", "causation_id"
    )
  end

  it "exposes the operational scheduler front door and nothing that schedules or executes product work" do
    expect(Platform::BackgroundExecution).to respond_to(:run_scheduler)
    # F-04 makes the substrate runnable; it does not interpret, validate or score product work.
    %i[schedule execute validate score interpret adjudicate].each do |verb|
      expect(Platform::BackgroundExecution).not_to respond_to(verb)
    end
  end

  it "actually scans the tree it claims to" do
    expect(production_files.length).to be > 60
    expect(production_files).to include(a_string_ending_with("app/platform/scheduled_actions/execution_job.rb"))
    expect(production_files).to include(a_string_ending_with("app/platform/scheduled_actions/dispatcher.rb"))
  end
end
