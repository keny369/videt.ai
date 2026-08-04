# frozen_string_literal: true

# WHICH OF THE RUN DEADLINE'S QUESTIONS PRODUCTION ACTUALLY ASKS — observed over the whole suite.
#
# THIS IS THE MECHANISM THAT FOUND D1. `Platform::RunDeadline#iso8601` sat on the object, defended by
# nothing, asked by nothing, through an entire tranche and ten reviews. No behavioural proof could
# have caught it, because no behaviour depended on it.
#
# THE SET IS TAKEN FROM THE OBJECT, NOT PARSED OUT OF THE CORPUS. An earlier version of this census
# derived its expected set by scanning `app/` for `.expired?` call sites, and that was wrong in a way
# worth recording: it matched on the MESSAGE NAME and ignored the receiver, so `budget.expired?` in
# `fetch_content.rb` — a request-timeout object with its own `expired?` defined thirty lines below —
# was reported as an undriven `:442` gate. Ruby cannot decide a receiver's type statically, so no
# amount of extending that parse would have made it right.
#
# THE EXCLUSION IS `inspect` AND `to_s`, AND THIS IS THE ONE PLACE A TWO-NAME LIST IS DEFENSIBLE.
# Ruby's rendering protocol is exactly those two methods, so the list is the complete contract surface
# rather than a sample of it — the only condition under which this repository permits a syntactic
# rule. Subtracting `Object.instance_methods` instead, which the first version did, looked more
# principled and was strictly worse: ActiveSupport defines `present?` on `Object`, so a REAL deadline
# question that production calls was silently removed from the census and could never be checked.
module DeadlineQueryCensus
  APP = "app"
  # Defined in the module body, NOT inside `class << self` — a constant declared there lands on the
  # singleton class and is invisible as `DeadlineQueryCensus::RENDERING`.
  RENDERING = %i[inspect to_s].freeze

  class << self
    def observed = (@observed ||= Hash.new { |h, k| h[k] = [] })

    def spec_file_count = @spec_file_count ||= Dir[Rails.root.join("spec/**/*_spec.rb")].length

    # Did this run load the whole suite? Derived by comparing what RSpec was told to run against every
    # spec file that exists, so it cannot drift.
    def whole_suite? = RSpec.configuration.files_to_run.length >= spec_file_count

    def declared_queries = (Platform::RunDeadline.instance_methods(false) - RENDERING).sort

    def unasked = declared_queries.reject { |m| observed.key?(m) }

    def arm!
      return if @armed

      @traces = declared_queries.map do |method|
        TracePoint.new(:call) do |tp|
          next unless tp.defined_class == Platform::RunDeadline && tp.method_id == method

          site = caller_locations(2, 1)&.first
          next if site.nil?

          path = site.absolute_path.to_s
          observed[method] << "#{path.split("/#{APP}/").last}:#{site.label}" if path.include?("/#{APP}/")
        end
      end
      @traces.each(&:enable)
      @armed = true
    end
  end
end

RSpec.configure { |config| config.before(:suite) { DeadlineQueryCensus.arm! } }
