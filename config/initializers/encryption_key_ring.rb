# frozen_string_literal: true

# Default the F-02 wrapping-key ring for LOCAL environments only.
#
# Platform::Encryption::DeploymentKeySource reads the wrapping-key material from
# F1_ENCRYPTION_KEY_RING. Staging and production supply it out of band and this
# default never applies there; in development and test we fall back to the fixed,
# non-secret local ring so the platform's first encryption consumer works from a
# clean checkout. f1:db:ensure_encryption_key registers the matching active version.
require Rails.root.join("lib/f1/dev_encryption_key_ring").to_s

if Rails.env.local? && ENV["F1_ENCRYPTION_KEY_RING"].to_s.empty?
  ENV["F1_ENCRYPTION_KEY_RING"] = F1::DevEncryptionKeyRing::RING_JSON
end
