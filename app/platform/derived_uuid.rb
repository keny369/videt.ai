# frozen_string_literal: true

module Platform
  # A UUID derived deterministically from a 32-byte digest, byte-for-byte identical to the
  # database's `f1_bootstrap_principal_uuid` (db/migrate/20260719120001_enable_context_security.rb).
  #
  # WHY THIS EXISTS. Some artifacts that a contract requires to be named by a `uuid` are not rows:
  # the frozen global Crawl Policy ceiling is a constant (ADR-068 deferred `release_artifacts`), yet
  # `EventGoverningVersion` requires `artifact_id: uuid` for every governing artifact an event names.
  # A random ID would differ per process and per run, which is exactly what a governing-version
  # reference must not do; omitting the artifact would leave an event unable to explain the
  # configured value it reports.
  #
  # A derivation from the artifact's own canonical content is stable, reproducible, and carries the
  # same guarantee the digest does: two references are equal precisely when the content is. When the
  # deferred artifact becomes a real row it can adopt this identity with no event-stream break.
  #
  # The derivation is the OD-013 one, unchanged: the first 128 bits of the digest, stamped version 8
  # and RFC 4122 variant. It is duplicated here rather than called through SQL because callers need
  # it outside a transaction, and the two implementations are pinned to each other by spec.
  module DerivedUuid
    module_function

    DIGEST_BYTES = 32

    def v8(digest)
      raise ArgumentError, "derived uuid needs a #{DIGEST_BYTES}-byte digest" unless digest.is_a?(::String) &&
                                                                                    digest.bytesize == DIGEST_BYTES

      bytes = digest.byteslice(0, 16).unpack("C16")
      bytes[6] = (bytes[6] & 0x0f) | 0x80   # version 8
      bytes[8] = (bytes[8] & 0x3f) | 0x80   # variant 10xx
      hex = bytes.pack("C16").unpack1("H*")
      [hex[0, 8], hex[8, 4], hex[12, 4], hex[16, 4], hex[20, 12]].join("-")
    end
  end
end
