# frozen_string_literal: true

require "base64"
require "json"

module F1
  # A FIXED, NON-SECRET wrapping-key ring for LOCAL DEVELOPMENT AND TEST ONLY.
  #
  # F-02 (Platform::Encryption) resolves wrapping-key MATERIAL out of band from
  # `F1_ENCRYPTION_KEY_RING` (Platform::Encryption::DeploymentKeySource) — the
  # database holds only the non-secret fingerprint. Staging and production MUST
  # supply that environment variable through deployment configuration and NEVER use
  # the value here. For a clean local checkout (and the test suite) there is no such
  # deployment, so the platform's first encryption consumer — S-05 ownership-
  # verification challenge tokens — would fail `key_unavailable`. This module is the
  # single source of the local default; the initializer sets the environment
  # variable from it when it is absent in a local environment, and
  # `f1:db:ensure_encryption_key` registers the matching active key version so the
  # provider's fingerprint check passes.
  module DevEncryptionKeyRing
    PROVIDER = "platform-keyring"
    VERSION = "dev-1"

    # Exactly 32 bytes. Not a secret: it protects only local/test data and is
    # published in the repository. Real environments override it via the env var.
    KEY = "f1-dev-encryption-key-ring-00001".b

    RING_JSON = JSON.generate(PROVIDER => { VERSION => Base64.strict_encode64(KEY) }).freeze
  end
end
