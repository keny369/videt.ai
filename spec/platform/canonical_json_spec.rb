# frozen_string_literal: true

require "rails_helper"

# RFC 8785 (JCS) behaviour that the Logical Command Envelope request hash and the
# immutable event_bytes both depend on. If canonicalization drifts, every stored
# request hash and event digest silently diverges, so these are load-bearing.
RSpec.describe Platform::CanonicalJson do
  describe ".encode" do
    it "sorts object keys and emits no insignificant whitespace" do
      expect(described_class.encode({ "b" => 1, "a" => 2 })).to eq('{"a":2,"b":1}')
    end

    it "sorts keys by UTF-16 code unit, not by ASCII-caseless order" do
      expect(described_class.encode({ "a" => 1, "B" => 2 })).to eq('{"B":2,"a":1}')
    end

    it "preserves array order" do
      expect(described_class.encode({ "b" => [3, 2, 1], "a" => 1 })).to eq('{"a":1,"b":[3,2,1]}')
    end

    it "accepts symbol keys as their string form" do
      expect(described_class.encode({ a: 1, b: 2 })).to eq('{"a":1,"b":2}')
    end

    it "emits integers in plain base-10 with no exponent or sign" do
      expect(described_class.encode({ "n" => 0, "big" => 10_000_000_000 }))
        .to eq('{"big":10000000000,"n":0}')
    end

    it "emits booleans and null literally" do
      expect(described_class.encode({ "t" => true, "f" => false, "z" => nil }))
        .to eq('{"f":false,"t":true,"z":null}')
    end

    it "minimally escapes control characters and the two mandatory escapes" do
      expect(described_class.encode("a\"b\\c\n\t")).to eq('"a\\"b\\\\c\\n\\t"')
      expect(described_class.encode("")).to eq('"\\u0001"')
    end

    it "does not escape solidus or non-ASCII, emitting raw UTF-8" do
      expect(described_class.encode("/ é 日")).to eq('"/ é 日"')
    end

    it "normalizes strings to Unicode NFC so decomposed and precomposed agree" do
      precomposed = "é"            # U+00E9
      decomposed  = "é"      # e + combining acute
      expect(described_class.encode(decomposed)).to eq(described_class.encode(precomposed))
    end

    it "rejects Float, because the canonical schema forbids floating point" do
      expect { described_class.encode({ "x" => 1.5 }) }.to raise_error(ArgumentError, /Float/)
    end

    it "rejects symbol values to avoid ambiguous stringification" do
      expect { described_class.encode({ "x" => :y }) }.to raise_error(ArgumentError, /Symbol/)
    end
  end

  describe ".digest" do
    it "is a 32-byte SHA-256 over the canonical encoding" do
      value = { "a" => 1, "b" => "two" }
      expect(described_class.digest(value).bytesize).to eq(32)
      expect(described_class.hexdigest(value)).to eq(Digest::SHA256.hexdigest(described_class.encode(value)))
    end

    it "is stable across key insertion order" do
      expect(described_class.digest({ "a" => 1, "b" => 2 }))
        .to eq(described_class.digest({ "b" => 2, "a" => 1 }))
    end
  end
end
