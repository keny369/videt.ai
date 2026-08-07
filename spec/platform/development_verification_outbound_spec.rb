# frozen_string_literal: true

require "rails_helper"

# The development-only observation surface (WEB-015 local usability).
#
# The value of this file is entirely in what it REFUSES. A development affordance that
# can reach a deployed process is not an affordance, it is a hole in ownership
# verification: anyone able to set an environment variable could verify a domain they
# do not control. So the first three examples are about production, and the rest prove
# that when it IS active it still runs the real predicate rather than asserting success.
RSpec.describe Platform::DevelopmentVerificationOutbound, type: :model do
  let(:directory) { Rails.root.join("tmp/spec_dev_verification-#{SecureRandom.hex(4)}") }

  after { FileUtils.rm_rf(directory) }

  def reader = described_class::Reader.new(directory)

  def write(host, value)
    FileUtils.mkdir_p(directory)
    File.write(directory.join("#{host}.txt"), value)
  end

  describe "reachability" do
    it "is not enabled in the test environment even with the flag set" do
      ENV[described_class::ENV_FLAG] = "1"
      expect(described_class).not_to be_enabled
    ensure
      ENV.delete(described_class::ENV_FLAG)
    end

    it "is not enabled in production even with the flag set" do
      allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new("production"))
      ENV[described_class::ENV_FLAG] = "1"

      expect(described_class).not_to be_enabled
    ensure
      ENV.delete(described_class::ENV_FLAG)
    end

    it "is not enabled in development without the flag" do
      allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new("development"))

      expect(described_class).not_to be_enabled
    end

    it "hands out the real guarded transport whenever it is not enabled" do
      expect(described_class.surface).to be(Platform::Outbound)
    end

    it "hands out the local reader only when development and the flag agree" do
      allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new("development"))
      ENV[described_class::ENV_FLAG] = "1"

      expect(described_class.surface).to be_a(described_class::Reader)
    ensure
      ENV.delete(described_class::ENV_FLAG)
    end

    it "cannot be constructed in production at all" do
      allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new("production"))

      expect { described_class::Reader.new(directory) }.to raise_error(described_class::NotAvailable)
    end

    it "cannot be constructed under an unrecognised environment name" do
      allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new("staging"))

      expect { described_class::Reader.new(directory) }.to raise_error(described_class::NotAvailable)
    end

    it "refuses to place a record when it is not enabled" do
      expect { described_class.place(canonical_host: "shop.example.test", value: "x") }
        .to raise_error(described_class::NotAvailable)
    end
  end

  describe "the DNS answer" do
    it "returns the published value as one TXT record" do
      write("shop.example.test", "f1-verification=abc\n")

      answer = reader.fetch_dns_txt("_f1-verify.shop.example.test", timeout_s: 10)

      expect(answer).not_to be_refused
      expect(answer.records).to eq([["f1-verification=abc"]])
    end

    it "is NXDOMAIN when nothing has been published — the same as an unpublished record live" do
      answer = reader.fetch_dns_txt("_f1-verify.shop.example.test", timeout_s: 10)

      expect(answer).to be_refused
      expect(answer.reason).to eq(:absent)
    end

    it "refuses a name that is not a plain hostname rather than reading a path" do
      answer = reader.fetch_dns_txt("_f1-verify.../../../etc/passwd", timeout_s: 10)

      expect(answer).to be_refused
    end
  end

  describe "the HTTP answer" do
    it "serves 200 with the published value at the well-known URL" do
      write("shop.example.test", "f1-verification=abc")

      outcome = reader.fetch("https://shop.example.test/.well-known/f1-verification.txt",
                             timeout_s: 10, byte_cap: 4096, max_redirects: 0)

      expect(outcome).to be_response
      expect(outcome.status).to eq(200)
      expect(outcome.body).to eq("f1-verification=abc\n".b)
    end

    it "is 404 when nothing has been published" do
      outcome = reader.fetch("https://shop.example.test/.well-known/f1-verification.txt",
                             timeout_s: 10, byte_cap: 4096, max_redirects: 0)

      expect(outcome.status).to eq(404)
    end

    it "is 404 for any URL other than the well-known path" do
      write("shop.example.test", "f1-verification=abc")

      outcome = reader.fetch("https://shop.example.test/somewhere-else",
                             timeout_s: 10, byte_cap: 4096, max_redirects: 0)

      expect(outcome.status).to eq(404)
    end

    it "flags a body past the cap, so http_body_too_large is still reachable locally" do
      write("shop.example.test", "x" * 5000)

      outcome = reader.fetch("https://shop.example.test/.well-known/f1-verification.txt",
                             timeout_s: 10, byte_cap: 4096, max_redirects: 0)

      expect(outcome.truncated).to be(true)
      expect(outcome.byte_count).to be > 4096
    end
  end

  describe "the real predicate still decides" do
    def observe(method, published, token)
      write("shop.example.test", published)
      Workflows::Wf003::VerificationObservation.observe(
        method:, canonical_host: "shop.example.test", token:, outbound: reader
      )
    end

    it "matches DNS only on the exact value" do
      token = "Xy_9-abcDEF0123456789abcdef012345"
      expect(observe("dns_txt", "f1-verification=#{token}", token).reason_code).to eq("matched")
    end

    it "does NOT match when the published value is wrong — no local shortcut to success" do
      token = "Xy_9-abcDEF0123456789abcdef012345"
      result = observe("dns_txt", "f1-verification=WRONG", token)

      expect(result.match_decision).to eq("not_matched")
      expect(result.reason_code).to eq("dns_value_mismatch")
    end

    it "does not match an HTTP file whose contents differ" do
      token = "Xy_9-abcDEF0123456789abcdef012345"
      result = observe("http_file", "f1-verification=WRONG", token)

      expect(result.reason_code).to eq("http_content_mismatch")
    end

    it "matches an HTTP file whose contents are exact" do
      token = "Xy_9-abcDEF0123456789abcdef012345"
      expect(observe("http_file", "f1-verification=#{token}", token).reason_code).to eq("matched")
    end
  end
end
