# frozen_string_literal: true

module Workflows
  module Wf004
    # The pure Source Scope Predicate (PRULE-021; contracts/S-06.json MTX-072;
    # SECURITY_PERFORMANCE.md § PRULE-021). Given a candidate canonical URL and the
    # active Source Scope Policy intersection it decides admission: a URL is allowed
    # only when it matches EVERY active policy intersection, at least one include
    # prefix, no exclude prefix (exclusion wins over inclusion), and the query rule.
    # Normalization precedes comparison.
    #
    # It is DEFINED here (S-06 / WF-004) and APPLIED by S-07 at crawl time against the
    # pinned policy version (contracts/S-06.json MTX-072 rollout); S-07 does not
    # redefine it. It is PURE — no persistence, no outbound call, no event, and no
    # Source or Request transition; the change-request table, the commands, the expiry
    # job and the Source lifecycle are later S-06 sub-tranches. The same URL under the
    # same policy version always yields the same decision, so a policy activation never
    # retroactively admits or rejects an already-decided URL.
    #
    # Host handling follows the ratified `ascii-host-v1` contract (WF-004): ASCII only,
    # lowercased, trailing dot removed, and NEVER normalized to punycode by the
    # implementation (Volume I fixes IDNA handling so implementations cannot diverge);
    # a non-ASCII candidate host is therefore out of scope.
    module SourceScopePredicate
      module_function

      # The default port removed during normalization, by scheme.
      DEFAULT_PORTS = { "https" => 443, "http" => 80 }.freeze

      # Query handling: the whole query is kept, or only an explicit key allowlist is.
      RETAIN_ALL = "retain_all"

      # A single RFC 3986 unreserved character; a percent-escape of one is decoded and
      # every other escape keeps its byte with the hex normalized to uppercase.
      UNRESERVED = /\A[A-Za-z0-9\-._~]\z/
      PERCENT = /%([0-9A-Fa-f]{2})/
      # ASCII control characters and space are never part of a canonical URL.
      CONTROL_OR_SPACE = /[\u0000-\u0020\u007f]/
      SCHEME = %r{\A([A-Za-z][A-Za-z0-9+.\-]*)://}

      # The value-object view of ONE active Source Scope Policy version the predicate
      # reads — exactly the `source-scope-policy-v1` fields it needs (contracts/S-06.json
      # MTX-029 value_objects). `query_handling` is either the string "retain_all" or an
      # Array of retained key strings; the persistence encoding is a later sub-tranche's
      # concern, so the predicate stays decoupled from it.
      Policy = Data.define(:canonical_host, :allowed_schemes, :allowed_ports,
                           :include_prefixes, :exclude_prefixes, :query_handling)

      # `allowed?` plus, when denied, exactly one reason. `canonical_url` is the
      # normalized form the caller admits (scheme://host[:port]/path[?query]) when
      # allowed, and nil on denial.
      Decision = Data.define(:allowed, :reason_code, :canonical_url) do
        def allowed? = allowed
      end

      # The deterministic denial-reason vocabulary. `allowed` is the pass sentinel;
      # every other code names one out-of-scope condition. Precedence is fixed and
      # checked in this order: malformed/userinfo, then per policy host, scheme, port,
      # exclusion (which wins over inclusion), inclusion.
      REASON_CODES = %w[
        allowed
        url_malformed url_userinfo_prohibited
        host_out_of_scope scheme_out_of_scope port_out_of_scope
        path_excluded path_not_included
      ].freeze

      # Evaluate a candidate URL against the active policy intersection. `policies` is a
      # non-empty Array of Policy; an empty set is a caller error (no scope has been
      # resolved), never a silent admission.
      def evaluate(url:, policies:)
        raise ArgumentError, "no active policy" if policies.nil? || Array(policies).empty?

        parsed = parse(url)
        return deny(parsed[:reason]) unless parsed[:ok]

        policies.each do |policy|
          reason = fails(parsed, policy)
          return deny(reason) if reason
        end
        allow(canonical_url(parsed, policies))
      end

      def allow(canonical_url) = Decision.new(allowed: true, reason_code: "allowed", canonical_url:)
      def deny(reason) = Decision.new(allowed: false, reason_code: reason, canonical_url: nil)

      # ---- per-policy intersection --------------------------------------------

      # nil when the URL passes this policy, else the first-failing reason. The
      # host/scheme/port triple is the "active policy intersection"; exclusion is
      # tested before inclusion so it wins.
      def fails(parsed, policy)
        return "host_out_of_scope" unless parsed[:host] == policy.canonical_host.to_s.downcase
        return "scheme_out_of_scope" unless downcased(policy.allowed_schemes).include?(parsed[:scheme])
        return "port_out_of_scope" unless policy.allowed_ports.map(&:to_i).include?(parsed[:port])
        return "path_excluded" if policy.exclude_prefixes.any? { |prefix| prefix_match?(parsed[:path], prefix) }
        return "path_not_included" unless policy.include_prefixes.any? { |prefix| prefix_match?(parsed[:path], prefix) }

        nil
      end

      # A prefix matches the normalized path exactly or at a `/` segment boundary:
      # `/shop` matches `/shop` and `/shop/item` but NOT `/shopping`. A prefix that
      # already ends in `/` carries its own boundary, so `/` (root) matches every
      # absolute path.
      def prefix_match?(path, prefix)
        return true if path == prefix
        return path.start_with?(prefix) if prefix.end_with?("/")

        path.start_with?(prefix) && path[prefix.length] == "/"
      end

      # ---- normalization ------------------------------------------------------

      # First-match parse of a candidate URL into its normalized parts, or a reason.
      # Order: malformed (empty, control/space, no scheme, empty authority), userinfo,
      # host (ASCII + non-empty), port, then path and query. The fragment is dropped.
      def parse(url)
        return malformed unless url.is_a?(::String) && !url.empty?
        return malformed if url.match?(CONTROL_OR_SPACE)

        scheme_match = url.match(SCHEME)
        return malformed if scheme_match.nil?

        scheme = scheme_match[1].downcase
        rest = url[scheme_match.end(0)..]
        delimiter = (rest =~ %r{[/?#]})
        authority = delimiter ? rest[0...delimiter] : rest
        tail = delimiter ? rest[delimiter..] : ""
        return malformed if authority.empty?
        return { ok: false, reason: "url_userinfo_prohibited" } if authority.include?("@")

        host, port, bad = split_host_port(authority)
        return malformed if bad
        return { ok: false, reason: "host_out_of_scope" } unless host&.ascii_only?

        normalized_host = host.downcase.sub(/\.\z/, "")
        return { ok: false, reason: "host_out_of_scope" } if normalized_host.empty?

        effective_port = resolve_port(scheme, port)
        return malformed if effective_port.nil?

        path, query = split_tail(tail)
        { ok: true, scheme:, host: normalized_host, port: effective_port,
          path: normalize_path(path), query_pairs: parse_query(query) }
      end

      def malformed = { ok: false, reason: "url_malformed" }

      # Split the authority into host and optional port string. A bracketed IPv6
      # literal is carried through as the host (it can never equal an ascii-host-v1
      # host and so falls out of scope); the port only splits on a colon outside any
      # brackets.
      def split_host_port(authority)
        if authority.start_with?("[")
          close = authority.index("]")
          return [nil, nil, :malformed] if close.nil?

          after = authority[(close + 1)..]
          return [authority[0..close], nil, nil] if after.empty?
          return [authority[0..close], after[1..], nil] if after.start_with?(":")

          [nil, nil, :malformed]
        elsif authority.include?(":")
          host, _, port = authority.rpartition(":")
          return [nil, nil, :malformed] if host.empty?

          [host, port, nil]
        else
          [authority, nil, nil]
        end
      end

      # The effective port: an absent port takes the scheme default; a present port
      # must be all digits. A non-numeric port is malformed. The scheme default is
      # what "default port removed" resolves to for comparison.
      def resolve_port(scheme, port)
        return DEFAULT_PORTS[scheme] if port.nil? || port.empty?
        return nil unless port.match?(/\A\d+\z/)

        port.to_i
      end

      # The tail after the authority begins with '/', '?', '#' or is empty. The
      # fragment is dropped (prohibited in the normalized form). Returns [path, query].
      def split_tail(tail)
        return ["", nil] if tail.empty?

        without_fragment = (hash = tail.index("#")) ? tail[0...hash] : tail
        if (mark = without_fragment.index("?"))
          [without_fragment[0...mark], without_fragment[(mark + 1)..]]
        else
          [without_fragment, nil]
        end
      end

      # Normalize the path: default to root; decode unreserved percent-escapes (and
      # uppercase the hex of those kept); then remove dot segments. Decoding precedes
      # dot-segment removal so a `%2E`-encoded `.`/`..` is resolved as a dot segment.
      def normalize_path(path)
        path = "/" if path.nil? || path.empty?
        path = "/#{path}" unless path.start_with?("/")
        collapsed = remove_dot_segments(decode_unreserved(path))
        collapsed.empty? ? "/" : collapsed
      end

      def decode_unreserved(string)
        string.gsub(PERCENT) do
          hex = ::Regexp.last_match(1)
          char = hex.to_i(16).chr
          char.match?(UNRESERVED) ? char : "%#{hex.upcase}"
        end
      end

      # RFC 3986 §5.2.4 remove_dot_segments over an absolute path.
      def remove_dot_segments(path)
        input = path.dup
        output = +""
        until input.empty?
          if input.start_with?("/./")
            input = "/#{input[3..]}"
          elsif input == "/."
            input = "/"
          elsif input.start_with?("/../")
            input = "/#{input[4..]}"
            output = output.sub(%r{/[^/]*\z}, "")
          elsif input == "/.."
            input = "/"
            output = output.sub(%r{/[^/]*\z}, "")
          elsif input == "." || input == ".."
            input = ""
          else
            segment = input.match(%r{\A/?[^/]*})[0]
            output << segment
            input = input[segment.length..]
          end
        end
        output
      end

      # ---- query --------------------------------------------------------------

      # Parse the query into decoded [key, value] pairs, preserving order and
      # duplicates; a pair with no '=' has a nil value. Empty pairs are dropped.
      def parse_query(query)
        return [] if query.nil? || query.empty?

        query.split("&", -1).reject(&:empty?).map do |pair|
          key, separator, value = pair.partition("=")
          [decode_unreserved(key), separator.empty? ? nil : decode_unreserved(value)]
        end
      end

      # The canonical query: retain a pair only when EVERY policy retains its key
      # (retain_all retains all; an allowlist retains only its keys), then sort by
      # decoded key then value while preserving duplicates. Query never denies
      # admission — it only shapes the canonical identity.
      def canonical_query(pairs, policies)
        retained = pairs.select { |key, _value| retained_key?(key, policies) }
        retained.each_with_index
                .sort_by { |(key, value), index| [key, value.to_s, index] }
                .map { |(key, value), _index| value.nil? ? key : "#{key}=#{value}" }
                .join("&")
      end

      def retained_key?(key, policies)
        policies.all? do |policy|
          handling = policy.query_handling
          handling == RETAIN_ALL || Array(handling).include?(key)
        end
      end

      def canonical_url(parsed, policies)
        query = canonical_query(parsed[:query_pairs], policies)
        url = +"#{parsed[:scheme]}://#{parsed[:host]}"
        url << ":#{parsed[:port]}" unless parsed[:port] == DEFAULT_PORTS[parsed[:scheme]]
        url << parsed[:path]
        url << "?#{query}" unless query.empty?
        url
      end

      def downcased(values) = values.map { |value| value.to_s.downcase }
    end
  end
end
