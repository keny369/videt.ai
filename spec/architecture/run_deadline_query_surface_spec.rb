# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Platform::RunDeadline query surface", type: :architecture do
  it "PROOF 215 — no deadline question exists that production never asks" do
    # A WHOLE-SUITE PROPERTY, AND IT SAYS SO RATHER THAN PASSING QUIETLY. Reporting `skip` under a
    # partial run is deliberate: a gate that reports success without having looked is worse than one
    # that fails, because it is indistinguishable from a gate that looked and found nothing.
    unless DeadlineQueryCensus.whole_suite?
      skip "whole-suite property; this run loaded " \
           "#{RSpec.configuration.files_to_run.length}/#{DeadlineQueryCensus.spec_file_count} spec files"
    end

    expect(DeadlineQueryCensus.declared_queries).not_to be_empty, "the derivation found no queries"
    expect(DeadlineQueryCensus.unasked).to be_empty, <<~MSG
      #{DeadlineQueryCensus.unasked.length} question(s) Platform::RunDeadline answers were never asked
      by any production code path in the entire suite:
        #{DeadlineQueryCensus.unasked.join("\n  ")}
      A question nothing asks cannot be defended by a behavioural proof — replacing its body with a
      constant would survive. Drive it from production, or remove it.
    MSG
    # NON-VACUITY: an empty census would make the assertion above trivially true.
    expect(DeadlineQueryCensus.observed.values.flatten).not_to be_empty
  end
end
