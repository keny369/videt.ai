# frozen_string_literal: true

require "rails_helper"

# F-01 Shared Outbound Transport — the single-surface architecture fitness check
# (FOUNDATION-001 property 10; acceptance "no outbound socket/DNS/HTTP primitive exists
# outside this adapter").
#
# SSRF prevention, pinning and auditability are properties of the PLATFORM only because
# there is exactly one egress surface. This test fails CI the moment production code
# reaches for a raw DNS/socket/TLS/HTTP primitive anywhere but the outbound adapter,
# which would be a second, unguarded egress path. Test support (spec/) legitimately
# stands up loopback servers and is not scanned.
RSpec.describe "Outbound single-surface fitness", type: :model do
  def adapter_prefix = "app/platform/outbound/"

  # The raw primitives that may exist ONLY inside the adapter. Word-boundaried so
  # `Resolv` never matches `Resolver`/`resolve`, and `Socket` never matches `TCPSocket`
  # or `SSLSocket` (each of those is caught by its own pattern).
  def forbidden_primitives
    {
      "Net::HTTP" => /\bNet::HTTP\b/,
      "Resolv" => /\bResolv\b/,
      "TCPSocket" => /\bTCPSocket\b/,
      "Socket" => /\bSocket\b/,
      "SSLSocket" => /\bSSLSocket\b/
    }
  end

  def production_files
    (Dir[Rails.root.join("app/**/*.rb")] + Dir[Rails.root.join("lib/**/*.rb")]).sort
  end

  def relative(path) = Pathname.new(path).relative_path_from(Rails.root).to_s

  it "confines raw DNS/socket/TLS/HTTP primitives to the outbound adapter" do
    violations = []

    production_files.each do |path|
      rel = relative(path)
      next if rel.start_with?(adapter_prefix)

      File.read(path).each_line.with_index(1) do |line, number|
        next if line.lstrip.start_with?("#") # a full-line comment is not code

        forbidden_primitives.each do |label, pattern|
          violations << "#{rel}:#{number} references #{label}" if line.match?(pattern)
        end
      end
    end

    expect(violations).to be_empty, <<~MESSAGE
      All platform-originated DNS/HTTP(S) access must go through #{adapter_prefix}
      (FOUNDATION-001). These files open a second, unguarded egress path:
      #{violations.join("\n")}
    MESSAGE
  end

  it "actually scans the tree it claims to (guards against a silently-empty glob)" do
    expect(production_files.length).to be > 50
    expect(production_files).to include(a_string_ending_with("app/platform/outbound/tls_connector.rb"))
  end
end
