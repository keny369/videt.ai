# frozen_string_literal: true

require "rails_helper"

# F-02 Envelope Encryption — the single-surface architecture fitness check (FOUNDATION-002;
# acceptance "direct use of OpenSSL encryption primitives outside the F-02 adapter fails
# architecture fitness checks"). Cryptographic protection is a property of the platform only
# because there is one adapter. This fails CI the moment production code reaches for a raw
# OpenSSL::Cipher, or names an internal encryption class, outside the adapter — which would
# be an unaudited crypto path. Consumers use Platform::Encryption.protect / .reveal / .erase
# with an Aad and typed Errors; test support (spec/) is not scanned.
RSpec.describe "Encryption single-surface fitness", type: :model do
  # The adapter is the encryption/ directory PLUS its explicit-namespace façade file.
  def in_adapter?(rel) = rel.start_with?("app/platform/encryption/") || rel == "app/platform/encryption.rb"

  def forbidden_primitives
    { "OpenSSL::Cipher" => /\bOpenSSL::Cipher\b/ }
  end

  # The internal classes a consumer must NOT reach. Aad, Error and Protected are public.
  # `Envelope` is fenced by its QUALIFIED name: the bare short name also names the unrelated
  # F-04 transport class (Platform::ScheduledActions::Envelope), and any real external reach
  # for the F-02 envelope would be qualified anyway — so this stays precise without weakening
  # the boundary (F-04 defect-fix, 2026-07-25).
  def internal_classes
    %w[
      EnvelopeCipher Aes256Gcm KeyProvider PlatformKeyProvider
      DatabaseMetadataStore DeploymentKeySource EncryptedRecordStore Encryption::Envelope
    ].to_h { |name| [name, /\b#{name}\b/] }
  end

  def production_files
    (Dir[Rails.root.join("app/**/*.rb")] + Dir[Rails.root.join("lib/**/*.rb")]).sort
  end

  def relative(path) = Pathname.new(path).relative_path_from(Rails.root).to_s

  def scan_outside_adapter(patterns)
    violations = []
    production_files.each do |path|
      rel = relative(path)
      next if in_adapter?(rel)

      File.read(path).each_line.with_index(1) do |line, number|
        next if line.lstrip.start_with?("#")

        patterns.each { |label, pattern| violations << "#{rel}:#{number} references #{label}" if line.match?(pattern) }
      end
    end
    violations
  end

  it "confines the OpenSSL encryption primitive to the adapter" do
    violations = scan_outside_adapter(forbidden_primitives)
    expect(violations).to be_empty, <<~MESSAGE
      All symmetric encryption must go through the F-02 adapter (FOUNDATION-002). These
      files open an unaudited crypto path:
      #{violations.join("\n")}
    MESSAGE
  end

  it "confines the internal encryption classes to the adapter — consumers use the façade" do
    violations = scan_outside_adapter(internal_classes)
    expect(violations).to be_empty, <<~MESSAGE
      Reach envelope encryption only through Platform::Encryption.protect / .reveal / .erase
      (FOUNDATION-002 FROZEN contract). These files reach around the abstraction:
      #{violations.join("\n")}
    MESSAGE
  end

  it "actually scans the tree it claims to" do
    expect(production_files.length).to be > 60
    expect(production_files).to include(a_string_ending_with("app/platform/encryption/aes256_gcm.rb"))
  end
end
