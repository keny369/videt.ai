# frozen_string_literal: true

module Platform
  module Encryption
    # The vendor-neutral KeyProvider contract (FOUNDATION-002 §KeyProvider). It is
    # deliberately narrow: it exposes only the operations the envelope system needs, and
    # it NEVER hands the platform wrapping key to a consumer — a DEK goes in, wrapped
    # bytes come out; wrapped bytes go in, a DEK comes out. The wrapping-key material
    # itself stays inside the provider (resolved from a deployment-controlled source).
    #
    # A conforming provider responds to:
    #   #id                              -> String, stable provider identifier recorded in
    #                                       the envelope's key_provider field.
    #   #active_version                  -> String, the wrapping-key version new wraps use;
    #                                       raises Error(:key_unavailable) when none is usable.
    #   #wrap(dek:, aad:)                -> Wrapped(bytes:, version:); wraps the DEK under the
    #                                       active version with authenticated encryption.
    #   #unwrap(wrapped:, version:, aad:) -> the DEK bytes; raises Error(:key_version_unknown|
    #                                       :key_destroyed|:authentication_failed).
    #   #status(version)                 -> one of STATUSES.
    #
    # STATUSES: :usable (active — encrypt and decrypt), :retired (decrypt only),
    # :destroyed (neither; key material is gone), :unknown (no such version).
    #
    # This module is the contract, not an implementation. The production provider
    # (platform key ring) and the in-memory test provider both conform; the shared RSpec
    # examples in spec/support prove any provider satisfies it, so EnvelopeCipher depends
    # on the contract and never on a concrete provider.
    module KeyProvider
      STATUSES = %i[usable retired destroyed unknown].freeze

      # A wrapped data-encryption key and the wrapping-key version that produced it. The
      # bytes are opaque to the consumer — only the producing provider can unwrap them.
      Wrapped = Data.define(:bytes, :version)
    end
  end
end
