# frozen_string_literal: true

module Workflows
  module Wf004
    # The bounded, reusable `source-registration-v1` URI and `ascii-host-v1` host
    # contract for WF-004 (WORKFLOW_SPECIFICATIONS.md :400, :406; APPLICATION_LAYER.md
    # :614-627; contracts/S-04.json). It parses the submitted root URI and applies
    # the exact first-match rejection order, deriving the canonical host and root
    # URI, from the caller's input alone. It performs NO authorization, NO tenant
    # read and NO persistence; the handler runs it before it opens its transaction.
    #
    # The grammar is deliberately strict: `https://<host>` or `https://<host>/`, an
    # explicit `:443` accepted and removed, and every other URI component rejected.
    # Host input is ASCII only — raw Unicode is `source_host_non_ascii` and is never
    # normalized to punycode by the implementation, because Volume I fixes that
    # reason so implementations cannot diverge on IDNA handling.
    module SourceRegistration
      module_function

      SCHEMA_MAJOR = "1"
      REGISTRATION_SCHEMA_VERSION = "source-registration-v1"
      HOST_NORMALIZATION_VERSION = "ascii-host-v1"
      HOST_MAX_BYTES = 253
      LABEL = /\A[A-Za-z0-9]([A-Za-z0-9\-]{0,61}[A-Za-z0-9])?\z/
      IPV4 = /\A\d{1,3}(\.\d{1,3}){3}\z/
      ASCII_CONTROL_OR_SPACE = /[\u0000-\u0020\u007f]/
      SCHEME = %r{\A([A-Za-z][A-Za-z0-9+.\-]*)://}

      Outcome = Data.define(:reason, :canonical_host, :canonical_root_uri) do
        def ok? = reason.nil?
      end

      def ok(host) = Outcome.new(reason: nil, canonical_host: host, canonical_root_uri: "https://#{host}/")
      def bad(reason) = Outcome.new(reason:, canonical_host: nil, canonical_root_uri: nil)

      def supported_schema?(version) = version.to_s.split(".").first == SCHEMA_MAJOR

      # First-match validation of the submitted root URI, in the exact ratified
      # order: malformed, scheme, userinfo, port, path, query, fragment, host
      # non-ASCII, host invalid. Returns an Outcome carrying either the first-match
      # reason or the canonical host and root URI.
      def validate(submitted)
        return bad("source_uri_malformed") unless submitted.is_a?(::String) && !submitted.empty?
        return bad("source_uri_malformed") if submitted.match?(ASCII_CONTROL_OR_SPACE)

        scheme_match = submitted.match(SCHEME)
        return bad("source_uri_malformed") if scheme_match.nil?
        return bad("unsupported_source_scheme") unless scheme_match[1].downcase == "https"

        rest = submitted[scheme_match.end(0)..]
        delimiter = (rest =~ %r{[/?#]})
        authority = delimiter ? rest[0...delimiter] : rest
        tail = delimiter ? rest[delimiter..] : ""
        return bad("source_uri_malformed") if authority.empty?
        return bad("source_userinfo_prohibited") if authority.include?("@")

        host, port, reason = split_host_port(authority)
        return bad(reason) if reason
        return bad("source_port_unsupported") unless port.nil? || port == "443"

        path, query, fragment = split_tail(tail)
        return bad("source_path_not_root") unless path.empty? || path == "/"
        return bad("source_query_prohibited") unless query.nil?
        return bad("source_fragment_prohibited") unless fragment.nil?

        return bad("source_host_non_ascii") unless host.ascii_only?
        canonical = host.downcase.sub(/\.\z/, "")
        return bad("source_host_invalid") unless valid_ascii_host?(canonical)

        ok(canonical)
      end

      # Split the authority into host and optional port. A bracketed IPv6 literal
      # is never a valid ascii-host-v1 host, so it is carried through as the host
      # and rejected as `source_host_invalid`; the port only splits on a colon
      # outside the brackets.
      def split_host_port(authority)
        if authority.start_with?("[")
          close = authority.index("]")
          return [nil, nil, "source_host_invalid"] if close.nil?

          after = authority[(close + 1)..]
          return [authority, nil, nil] if after.empty?
          return [authority[0..close], after[1..], nil] if after.start_with?(":")

          [nil, nil, "source_uri_malformed"]
        elsif authority.include?(":")
          host, _, port = authority.rpartition(":")
          return [nil, nil, "source_uri_malformed"] if host.empty?

          [host, port, nil]
        else
          [authority, nil, nil]
        end
      end

      # The tail after the authority begins with '/', '?', '#' or is empty. Returns
      # [path, query-or-nil, fragment-or-nil].
      def split_tail(tail)
        return ["", nil, nil] if tail.empty?

        fragment = nil
        if (hash = tail.index("#"))
          fragment = tail[(hash + 1)..]
          tail = tail[0...hash]
        end
        query = nil
        if (mark = tail.index("?"))
          query = tail[(mark + 1)..]
          tail = tail[0...mark]
        end
        [tail, query, fragment]
      end

      # ascii-host-v1: 1-253 bytes, at least two dot-separated labels, each label
      # 1-63 ASCII letters/digits/hyphens without a leading or trailing hyphen. A
      # pre-encoded xn-- label is allowed; an IPv4 literal is not a host.
      def valid_ascii_host?(host)
        return false unless host.bytesize.between?(1, HOST_MAX_BYTES)
        return false if host.match?(IPV4)

        labels = host.split(".", -1)
        return false if labels.length < 2

        labels.all? { |label| label.match?(LABEL) }
      end
    end
  end
end
