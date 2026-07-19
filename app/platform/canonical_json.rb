# frozen_string_literal: true

require "digest"

module Platform
  # Deterministic canonical JSON per RFC 8785 (JSON Canonicalization Scheme).
  #
  # This is the single canonicalizer behind the Logical Command Envelope request
  # hash (WORKFLOW_SPECIFICATIONS.md § Logical Command Envelope And Replay) and
  # the immutable event_bytes (schemas/POSTGRESQL_SCHEMA.md § event_registry):
  # object keys are sorted by UTF-16 code unit, strings are Unicode-NFC and
  # minimally escaped, integers are plain base-10 with no exponent, arrays keep
  # their declared order, and there is no insignificant whitespace.
  #
  # Floating point is rejected: the canonical schema forbids float columns, and
  # every envelope value is a string, integer, boolean, null, array or object.
  # A caller that needs a decimal passes its exact canonical string form.
  module CanonicalJson
    module_function

    # Canonical UTF-8 bytes (a mutable String in UTF-8 encoding).
    def encode(value)
      out = String.new(encoding: Encoding::UTF_8)
      write(value, out)
      out
    end

    # 32 raw bytes of SHA-256 over the canonical encoding.
    def digest(value)
      Digest::SHA256.digest(encode(value))
    end

    # Lowercase hex of the digest, for log/audit identity fields.
    def hexdigest(value)
      Digest::SHA256.hexdigest(encode(value))
    end

    def write(value, out)
      case value
      when ::String then write_string(value, out)
      when ::Integer then out << value.to_s
      when true then out << "true"
      when false then out << "false"
      when nil then out << "null"
      when ::Array then write_array(value, out)
      when ::Hash then write_object(value, out)
      when ::Symbol
        raise ArgumentError, "canonical JSON value may not be a Symbol (#{value.inspect}); pass a String"
      when ::Float
        raise ArgumentError, "canonical JSON forbids Float (#{value.inspect}); pass an Integer or exact decimal String"
      else
        raise ArgumentError, "canonical JSON cannot encode #{value.class}"
      end
    end
    private_class_method :write

    def write_array(array, out)
      out << "["
      array.each_with_index do |element, index|
        out << "," unless index.zero?
        write(element, out)
      end
      out << "]"
    end
    private_class_method :write_array

    def write_object(hash, out)
      members = hash.map do |key, value|
        [key.is_a?(::Symbol) ? key.to_s : key, value]
      end
      members.each do |key, _|
        raise ArgumentError, "canonical JSON object keys must be strings" unless key.is_a?(::String)
      end
      members.sort_by! { |(key, _)| key.encode(Encoding::UTF_16BE).unpack("n*") }
      out << "{"
      members.each_with_index do |(key, value), index|
        out << "," unless index.zero?
        write_string(key, out)
        out << ":"
        write(value, out)
      end
      out << "}"
    end
    private_class_method :write_object

    ESCAPES = {
      "\"" => "\\\"", "\\" => "\\\\", "\b" => "\\b", "\t" => "\\t",
      "\n" => "\\n", "\f" => "\\f", "\r" => "\\r"
    }.freeze
    private_constant :ESCAPES

    def write_string(string, out)
      out << "\""
      string.unicode_normalize(:nfc).each_char do |char|
        if (escape = ESCAPES[char])
          out << escape
        elsif char.ord < 0x20
          out << format("\\u%04x", char.ord)
        else
          out << char
        end
      end
      out << "\""
    end
    private_class_method :write_string
  end
end
