# frozen_string_literal: true

require "bigdecimal"

module Workflows
  module Wf007
    # The three interim policies every catalog Check Result carries, transcribed
    # (SCORE_EVIDENCE_MODEL.md § Interim Confidence Policy `confidence-policy-v1`,
    # § Interim Effort Policy `effort-interim-v1`, and each Definition's impact rule;
    # PRULE-012, with OD-003 and OD-010 both RATIFIED).
    #
    # THEY ARE COPIED ONTO A RESULT, NEVER RE-DERIVED FROM IT. PRULE-012 is explicit: the
    # impact band is frozen on the Check Result, copied onto the Issue, and copied again onto
    # the Recommendation Artifact, and "mutating a Definition's rule after Issue creation
    # therefore changes nothing already persisted". Every function here is pure and takes its
    # inputs explicitly so that a caller cannot accidentally recompute a band from a later
    # version of the rule.
    #
    # ALL DECIMAL ARITHMETIC IS BASE-10. "Binary floating-point output MUST NOT determine a
    # persisted score", so rates are computed with BigDecimal and rendered as exact four-place
    # decimal STRINGS — which is also what the canonical-JSON hash requires, since it forbids
    # floats outright.
    module Policies
      module_function

      CONFIDENCE_POLICY_VERSION = "confidence-policy-v1"
      EFFORT_POLICY_VERSION = "effort-interim-v1"

      # A deterministic binary check uses `1.0000` unless its Definition declares a different
      # calibrated rule. All seven declare none, so every passed, failed and not-applicable
      # result carries exactly this.
      DECIDED_CONFIDENCE = "1.0000"

      # ---- confidence ------------------------------------------------------------------

      # `low` for 0.0000 <= v < 0.6000; `medium` for 0.6000 <= v < 0.8500; `high` for
      # 0.8500 <= v <= 1.0000. Rounded half up to four places BEFORE band mapping, so a value
      # of 0.59995 is `medium` rather than `low` — the rounding is part of the boundary, not a
      # display step after it.
      def confidence_band(value)
        rounded = round4(value)
        return "low" if rounded < BigDecimal("0.6000")
        return "medium" if rounded < BigDecimal("0.8500")

        "high"
      end

      # A decided result: `1.0000`, valid, band `high`.
      def decided_confidence
        { "confidence_value" => DECIDED_CONFIDENCE, "confidence_status" => "valid",
          "confidence_band" => confidence_band(DECIDED_CONFIDENCE),
          "confidence_policy_version" => CONFIDENCE_POLICY_VERSION }
      end

      # A handled error: the common null/missing/low fallback. The raw value is absent rather
      # than zero, because "the raw invalid value MUST NOT be used downstream" and a zero
      # would be a usable number.
      def missing_confidence
        { "confidence_value" => nil, "confidence_status" => "missing",
          "confidence_band" => "low", "confidence_policy_version" => CONFIDENCE_POLICY_VERSION }
      end

      # ---- impact ----------------------------------------------------------------------

      # The Definition's own exact impact rule. `nil` for a passed, not-applicable or error
      # result — the Check Result Contract requires `impact_band` NULL for all three, and the
      # database enforces the same shape.
      #
      # An unmapped FAILED outcome is not defaulted to anything: it raises, because
      # "discovery of catalog corruption or an unmapped failed outcome after activation fails
      # the Evaluation as `check_catalog_integrity_failure`; it does not create an Issue or
      # silently downgrade the outcome".
      def impact_band(definition, execution_status, outcome_code, observation)
        return nil unless execution_status == "failed"

        rule = definition["impact"][outcome_code]
        raise CatalogIntegrityFailure, "unmapped_failed_outcome:#{outcome_code}" if rule.nil?

        band_from(rule, observation, outcome_code)
      end

      # ---- effort ----------------------------------------------------------------------

      # Effort is derived ONLY from the origin Check Result and the exhaustive mapping; AI
      # cannot replace it. An unlisted failed outcome is `effort_policy_unavailable`, which
      # blocks Recommendation publication and Priority Decision creation WITHOUT changing the
      # Issue or the score — so it is returned as a null band with its basis recorded, not
      # raised.
      def effort(definition, execution_status, outcome_code, observation)
        return { "effort_band" => nil, "effort_basis" => nil } unless execution_status == "failed"

        rule = definition["effort"][outcome_code]
        if rule.nil?
          return { "effort_band" => nil,
                   "effort_basis" => basis(definition, outcome_code, "effort_policy_unavailable") }
        end

        band = band_from(rule, observation, outcome_code)
        { "effort_band" => band, "effort_basis" => basis(definition, outcome_code, matched_rule(rule, band)) }
      end

      # Exactly `effort-interim-v1:<check_definition_id>:<outcome_code>:<matched-rule>`.
      def basis(definition, outcome_code, matched)
        "#{EFFORT_POLICY_VERSION}:#{definition['check_definition_id']}:#{outcome_code}:#{matched}"
      end

      def matched_rule(rule, band)
        return "constant_#{band}" if rule.key?("band")

        "#{rule['metric']}_#{band}"
      end

      # ---- shared band resolution --------------------------------------------------------

      # Three rule shapes, and no fourth. A constant band; a threshold ladder keyed on an
      # integer metric; and the rate rule the two measurement Definitions use, where exactly
      # `0.0000` is one band and anything strictly between zero and one is another.
      def band_from(rule, observation, outcome_code)
        return rule["band"] if rule.key?("band")

        if rule.key?("thresholds")
          value = observation.fetch(rule["metric"]).to_i
          matched = rule["thresholds"].select { |floor, _| value >= floor }.last
          raise CatalogIntegrityFailure, "unmapped_metric:#{outcome_code}:#{value}" if matched.nil?

          return matched.last
        end

        rate = BigDecimal(observation.fetch(rule["metric"]).to_s)
        rate.zero? ? rule["zero_band"] : rule["partial_band"]
      end

      # ---- decimal helpers ----------------------------------------------------------------

      # A rate as an exact four-place decimal string, rounded HALF UP. Integer division is
      # done in BigDecimal so `1/3` is `0.3333` rather than a binary approximation, and the
      # string form is what gets hashed and persisted.
      def rate(numerator, denominator)
        return "0.0000" if denominator.to_i.zero?

        format4(BigDecimal(numerator.to_i) / BigDecimal(denominator.to_i))
      end

      def format4(decimal) = round4(decimal).to_s("F").then { |s| pad4(s) }

      def round4(value)
        BigDecimal(value.to_s).round(4, BigDecimal::ROUND_HALF_UP)
      end

      # `BigDecimal#to_s("F")` renders `1.0` rather than `1.0000`, and the persisted and
      # hashed form must be the exact four-place decimal the contract names.
      def pad4(string)
        whole, fraction = string.split(".")
        "#{whole}.#{fraction.to_s.ljust(4, '0')[0, 4]}"
      end

      # Raised where the ratified answer is to fail the Evaluation at the Catalog boundary
      # rather than to produce a Result. It is deliberately NOT a handled Check error: a
      # handled error would leave a Result behind that a scheme demonstrably failed to decide.
      class CatalogIntegrityFailure < StandardError; end
    end
  end
end
