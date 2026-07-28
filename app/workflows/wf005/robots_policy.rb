# frozen_string_literal: true

module Workflows
  module Wf005
    # The `robots.txt` policy for `F1DiscoverabilityBot` (WORKFLOW_SPECIFICATIONS.md :448;
    # SEARCH_CRAWL_RETRIEVAL.md § Robots And Sitemap Processing — "The parser implements the exact
    # `F1DiscoverabilityBot` longest-rule algorithm from Volume I and is covered by a golden corpus").
    #
    # PURE. No persistence, no network, no clock. Given bytes it returns a normalized rule set; given
    # a rule set and a path it returns allow/deny. That is what makes the same robots body decide the
    # same way on every retry and every replay, which :448's determinism requirement needs.
    #
    # The Volume I algorithm, exactly:
    #   * the body is decoded as UTF-8 with invalid byte sequences REPLACED (never rejected);
    #   * unrecognized or malformed lines are IGNORED, not treated as errors;
    #   * user-agent tokens are compared ASCII-case-insensitively against the exact token
    #     `F1DiscoverabilityBot`, falling back to `*` only when the exact token names no group;
    #   * the LONGEST matching allow/disallow normalized path rule wins;
    #   * ALLOW WINS an equal-length tie;
    #   * a positive crawl-delay makes the request rate MORE restrictive and never increases it;
    #   * `Sitemap:` locations are collected in file order for S-07-006.
    #
    # Fail-closed lives in the CALLER (`EnsureRobots`), which decides from the HTTP outcome whether a
    # rule set exists at all. This module never invents permission: with no applicable group it
    # returns an empty rule set, and an empty rule set allows — which is only ever reached after the
    # caller has established that a valid `2xx` body was actually retrieved.
    module RobotsPolicy
      module_function

      # The ratified crawler token (:448 "The baseline crawler user-agent token is
      # `F1DiscoverabilityBot`").
      AGENT_TOKEN = "F1DiscoverabilityBot"
      WILDCARD = "*"
      RULES_SCHEMA = "robots-rules-v1"

      # :448 "content over 1 MiB ... denies all content fetching for that host for the run".
      MAX_BODY_BYTES = 1024 * 1024

      # The normalized rule set: the agent group actually selected, its ordered rules, the optional
      # crawl delay in milliseconds, and the sitemap locations in file order.
      Rules = Data.define(:agent_group, :rules, :crawl_delay_ms, :sitemaps) do
        def to_json_h
          { "schema" => RULES_SCHEMA, "agent_group" => agent_group,
            "rules" => rules.map { |r| { "allow" => r[:allow], "path" => r[:path] } } }
        end
      end

      # Parse a robots body into a normalized rule set. `body` is raw bytes.
      def parse(body)
        groups, sitemaps = scan(decode(body))
        group_name = select_group(groups)
        selected = group_name ? groups.fetch(group_name) : { rules: [], crawl_delay_ms: nil }
        Rules.new(agent_group: group_name, rules: selected[:rules],
                  crawl_delay_ms: selected[:crawl_delay_ms], sitemaps:)
      end

      # Does the rule set permit fetching `path`? The longest matching rule wins and ALLOW wins an
      # equal-length tie. No matching rule means allowed — a robots file that says nothing about a
      # path does not forbid it.
      def allowed?(rules, path)
        candidate = normalize_path(path)
        best = nil
        Array(rules).each do |rule|
          pattern = rule[:path].to_s
          next unless candidate.start_with?(pattern)
          # Longest wins; on an exact length tie, allow beats disallow.
          next if best && (pattern.length < best[:path].to_s.length ||
                           (pattern.length == best[:path].to_s.length && !rule[:allow]))

          best = rule
        end
        best.nil? || best[:allow]
      end

      # The effective per-host minimum interval between request starts, in milliseconds: the policy
      # interval, made MORE restrictive by a positive robots crawl-delay and never less
      # (:448 "A positive robots crawl-delay makes the request rate more restrictive than policy; it
      # never increases rate").
      def effective_interval_ms(policy_interval_ms, crawl_delay_ms)
        [policy_interval_ms.to_i, crawl_delay_ms.to_i].max
      end

      # ---- parsing -------------------------------------------------------------

      # :448 "decoded as UTF-8 with invalid byte sequences replaced".
      def decode(body)
        body.to_s.dup.force_encoding(Encoding::UTF_8)
            .encode(Encoding::UTF_8, invalid: :replace, undef: :replace, replace: "�")
      end

      # Scan into { agent_token_downcased => {rules:, crawl_delay_ms:} } plus ordered sitemaps.
      # Consecutive `User-agent` lines share one group, which is what lets a file address several
      # agents with a single rule block.
      def scan(text)
        groups = {}
        sitemaps = []
        current = []
        expecting_agent = false

        text.each_line do |raw|
          field, value = split_line(raw)
          next if field.nil?

          case field
          when "user-agent"
            token = value.downcase
            # A rule line closes the previous group, so a new agent line starts a fresh one.
            current = [] unless expecting_agent
            expecting_agent = true
            current << token
            groups[token] ||= { rules: [], crawl_delay_ms: nil }
          when "allow", "disallow"
            expecting_agent = false
            next if current.empty?

            rule = build_rule(field, value)
            current.each { |token| groups[token][:rules] << rule } if rule
          when "crawl-delay"
            expecting_agent = false
            delay = parse_delay(value)
            current.each { |token| groups[token][:crawl_delay_ms] = delay } if delay
          when "sitemap"
            # Sitemap is a file-level directive, not part of any agent group.
            sitemaps << value unless value.empty?
          end
        end
        [groups, sitemaps]
      end

      # `field: value`, comments stripped, both sides trimmed. Anything else is ignored (:448
      # "unrecognized or malformed lines ignored").
      def split_line(raw)
        line = raw.split("#", 2).first.to_s.strip
        return [nil, nil] if line.empty?

        field, separator, value = line.partition(":")
        return [nil, nil] if separator.empty?

        [field.strip.downcase, value.strip]
      end

      # An empty `Disallow:` is the canonical "allow everything" and carries no rule. An empty
      # `Allow:` is meaningless and is likewise dropped.
      def build_rule(field, value)
        return nil if value.empty?

        { allow: field == "allow", path: normalize_path(value) }
      end

      # A non-negative number of seconds; anything else is ignored rather than guessed at.
      def parse_delay(value)
        return nil unless /\A\d+(\.\d+)?\z/.match?(value)

        (value.to_f * 1000).round
      end

      # Rule and candidate paths are compared in the same normalized form: rooted, with the query
      # retained (robots patterns may address it) and the fragment dropped.
      def normalize_path(path)
        candidate = path.to_s.split("#", 2).first.to_s
        candidate = "/#{candidate}" unless candidate.start_with?("/")
        candidate
      end

      # The group Volume I selects: the exact token, ASCII-case-insensitively; `*` ONLY as a fallback
      # when the exact token names no group.
      def select_group(groups)
        exact = AGENT_TOKEN.downcase
        return exact if groups.key?(exact)
        return WILDCARD if groups.key?(WILDCARD)

        nil
      end
    end
  end
end
