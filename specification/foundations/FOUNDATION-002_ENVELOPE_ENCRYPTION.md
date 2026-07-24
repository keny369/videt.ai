# FOUNDATION-002 — Envelope Encryption and Key Management

Status: **Ratified contract (ADR-024).** Supporting architecture contract, not a canonical ADR (decision of record: `DECISIONS.md` ADR-024). Implemented by the **F-02** tranche step, after F-01, before S-05.

- Ratified: 2026-07-24 (ADR-024)
- Owner context: Platform kernel (security foundation)
- First consumer: **S-05** challenge tokens (envelope-encrypted at rest, decryptable only through the two authorized redelivery paths, cryptographically deleted within 60 seconds of terminal transition).
- Related: generalises the existing session-replay key pattern (`AES-256-GCM`, versioned key ring); distinct from the RLS HMAC proof key (`f1_context_keys`), which is a MAC and is not reusable for encryption.

## Purpose

Protect sensitive payloads at rest (challenge secrets first; later, any secret the platform must store recoverably) with authenticated envelope encryption behind a **vendor-neutral `KeyProvider`**, so no plaintext secret is persisted, logged, or emitted in events/audit, and so a secret can be made unrecoverable on demand (cryptographic erasure).

## KeyProvider (vendor-neutral, ratified)

Encryption depends on a `KeyProvider` abstraction, **not** a named vendor. The initial Genesis implementation loads a **platform-managed versioned key ring from deployment secrets**, in the same architectural style as the session key ring. The abstraction MUST permit later backing by AWS Secrets Manager, Google Secret Manager, Azure Key Vault or HashiCorp Vault **without changing the encryption contract or any consumer**. No cloud-vendor secret service is hard-coded in Genesis.

## Mandatory properties

1. **Versioned keys + key identifiers.** Every ciphertext records the `key_id`/version that produced it; the ring supports multiple concurrent versions for rotation.
2. **Authenticated encryption** (AEAD, e.g. AES-256-GCM) with additional authenticated data binding the ciphertext to its record identity (so a ciphertext cannot be relocated to another record).
3. **Per-record data encryption keys** wrapped by the key-ring key (envelope encryption): a per-record DEK encrypts the payload; the key-ring key wraps the DEK.
4. **Ciphertext integrity** — tampering is detected on decrypt and surfaced as a typed failure, never a silent plaintext-of-garbage.
5. **Rotation** — re-wrapping to a new key-ring version without re-encrypting payloads is supported; old versions remain decryptable until retired.
6. **Cryptographic erasure semantics** — destroying the wrapping key / DEK renders the payload permanently unrecoverable; a timed deletion path exists (S-05's 60-second challenge destruction), leaving the content digest and access audit intact.
7. **No plaintext persistence** — plaintext exists only transiently in memory during encrypt/decrypt; it is never a column, log line, event field or audit payload.
8. **No secrets in events, logs or audit** — only ciphertext references, key ids and digests may be persisted or emitted; decrypt failure returns a typed reason (S-05: `challenge_redelivery_unavailable`), never the material.

## Abstraction

```
KeyProvider          → resolve/wrap/unwrap a versioned key by key_id; rotate; retire
EnvelopeCipher       → encrypt(plaintext, record_identity) → {ciphertext_ref, key_id, digest}
                       decrypt(ciphertext_ref, key_id, record_identity) → plaintext | typed_failure
                       destroy(ciphertext_ref, key_id) → cryptographic erasure
```

Consumers store only `{ciphertext_reference, key_id, content_digest}`; they never see or store plaintext at rest.

## Acceptance criteria (for the F-02 implementation)

- A round-trip encrypt→decrypt returns the exact plaintext; a tampered ciphertext fails typed.
- AAD binding: a ciphertext moved to another record identity fails to decrypt.
- Rotation: a payload encrypted under version N decrypts after the ring advances to N+1; retiring N makes it undecryptable.
- Cryptographic erasure: after `destroy`, decrypt is impossible; the digest and access audit survive.
- No plaintext or key material appears in any column, log, event, audit or metric — asserted.
- KeyProvider is swappable: a second (test) provider satisfies the same contract with no consumer change.

## Non-goals / boundaries

- **Not** a general KMS, HSM integration, or customer-managed-key product.
- **Not** transport security (that is TLS in F-01) or the RLS proof MAC (`f1_context_keys`).
- **Not** the deletion *scheduling* mechanism (that is F-04/ScheduledAction `verification_material_destroy`); F-02 owns only the erasure operation it invokes.

## Genesis + Videt

Genesis contracts unchanged. Provides the "cryptographic protection" foundation the Videt future architecture names; the vendor-neutral KeyProvider keeps deployment options open for the future platform without leaking any cloud dependency into Genesis.
