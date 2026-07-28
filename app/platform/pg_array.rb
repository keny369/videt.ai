# frozen_string_literal: true

module Platform
  # Parse a PostgreSQL array literal (`text[]`, `integer[]`, ...) into a Ruby Array.
  #
  # This exists because splitting on every comma is WRONG and fails OPEN. PostgreSQL quotes any
  # element containing a comma, a double quote or a backslash, so `{"/a,b"}` is ONE element — a naive
  # `split(",")` yields `["/a", "b"]`, and when the array is a Source Scope Policy's include or
  # exclude prefix list that silently widens or narrows the policy. The S-07-005 review demonstrated
  # exactly that: a hand-rolled split admitted a URL the true policy denied, at the last
  # authorization gate before bytes leave the platform.
  #
  # The implementation is the one already proven in the accepted WF-004 scope-change handlers,
  # extracted here so there is ONE parser rather than a fourth copy: scan quoted elements whole,
  # honouring backslash escapes, and take unquoted runs up to the next comma.
  module PgArray
    module_function

    ELEMENT = /"(?:[^"\\]|\\.)*"|[^,]+/

    # `nil` and an already-decoded Array pass through, so callers can accept either a raw literal
    # from a plain read or a decoded value from a typed one.
    def parse(literal)
      return [] if literal.nil?
      return literal if literal.is_a?(::Array)

      literal.to_s.gsub(/\A\{|\}\z/, "").scan(ELEMENT).map do |element|
        element.start_with?('"') ? element[1..-2].to_s.gsub(/\\(.)/, '\1') : element
      end
    end

    def parse_integers(literal) = parse(literal).map(&:to_i)
  end
end
