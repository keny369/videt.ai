# frozen_string_literal: true

# The Session bearer token (schemas/POSTGRESQL_SCHEMA.md :263 "token_sha256 UNIQUE,
# nullable token_replay_ciphertext bytea, token_replay_nonce bytea,
# token_replay_key_version text present together only while active").
#
# Until now `sessions` carried no token at all, so a Session was addressable only by
# its primary key. That is not a credential: a Session id is returned in command
# payloads, appears in audit and event rows, and is not secret. The browser contract
# in SECURITY_PERFORMANCE.md :38 requires the cookie `__Host-f1_session` to carry an
# opaque high-entropy token whose SHA-256 digest alone is stored, so a database
# disclosure cannot be replayed as a live Session. This migration adds that column
# and the pre-context authenticator that resolves it.
#
# Three rules are enforced in the database rather than in Ruby, because a Session is
# the authentication boundary and a defect here is a silent authentication bypass:
#
#   1. `token_sha256` is UNIQUE and exactly 32 bytes. Uniqueness makes a digest
#      collision a write failure rather than an ambiguous authentication, and the
#      length check refuses anything that is not a SHA-256 digest.
#   2. The three replay-capsule fields are all present or all absent. A half-written
#      capsule would decrypt to nothing and turn an exact replay into a new Session.
#   3. A terminal Session (revoked/expired) carries no capsule. Terminalization
#      clearing the capsule is what stops a revoked Session's token from being handed
#      back by a replayed creation response.
#
# `token_sha256` is added NOT NULL. Existing rows are backfilled with random digests
# rather than a constant: a shared digest would violate uniqueness, and a predictable
# one would be a usable credential. Those rows keep no recoverable token, which is
# correct — a Session created before tokens existed was never authenticable by token.
class SessionsBearerToken < ActiveRecord::Migration[8.1]
  def up
    add_token_columns
    create_token_authenticator
  end

  def down
    execute "DROP FUNCTION IF EXISTS f1_authenticate_session_by_token(bytea);"
    execute <<~SQL
      ALTER TABLE sessions
        DROP CONSTRAINT IF EXISTS sessions_token_sha256_length,
        DROP CONSTRAINT IF EXISTS sessions_replay_capsule_whole,
        DROP CONSTRAINT IF EXISTS sessions_replay_capsule_active_only;
      DROP INDEX IF EXISTS sessions_token_sha256_key;
      ALTER TABLE sessions
        DROP COLUMN IF EXISTS token_sha256,
        DROP COLUMN IF EXISTS token_replay_ciphertext,
        DROP COLUMN IF EXISTS token_replay_nonce,
        DROP COLUMN IF EXISTS token_replay_key_version;
    SQL
  end

  private

  def add_token_columns
    execute <<~SQL
      ALTER TABLE sessions
        ADD COLUMN token_sha256            bytea,
        ADD COLUMN token_replay_ciphertext bytea,
        ADD COLUMN token_replay_nonce      bytea,
        ADD COLUMN token_replay_key_version text;

      -- Backfill before NOT NULL. gen_random_bytes gives each pre-existing row its own
      -- unpredictable digest, so none of them collides and none of them is guessable.
      UPDATE sessions SET token_sha256 = gen_random_bytes(32) WHERE token_sha256 IS NULL;

      ALTER TABLE sessions ALTER COLUMN token_sha256 SET NOT NULL;

      CREATE UNIQUE INDEX sessions_token_sha256_key ON sessions (token_sha256);

      ALTER TABLE sessions
        ADD CONSTRAINT sessions_token_sha256_length
          CHECK (octet_length(token_sha256) = 32),

        -- All three capsule fields or none: a partial capsule is unusable and would
        -- make an exact replay silently mint a second Session.
        ADD CONSTRAINT sessions_replay_capsule_whole
          CHECK (
            (token_replay_ciphertext IS NULL AND token_replay_nonce IS NULL
               AND token_replay_key_version IS NULL)
            OR
            (token_replay_ciphertext IS NOT NULL AND token_replay_nonce IS NOT NULL
               AND token_replay_key_version IS NOT NULL)
          ),

        -- ":263 terminalization clears all three capsule fields." A revoked or expired
        -- Session must not be able to hand its raw token back through a replay.
        ADD CONSTRAINT sessions_replay_capsule_active_only
          CHECK (status = 'active' OR token_replay_ciphertext IS NULL);
    SQL
  end

  # The token twin of f1_authenticate_session (20260722120006). Same posture and same
  # reason: `sessions` is ENABLE-but-not-FORCE RLS so the owner-side SECURITY DEFINER
  # authenticator can resolve a Session *before* its Organization context exists,
  # while the non-owner runtime stays fully RLS-scoped and still sees no Session
  # outside its proved context.
  #
  # It takes the digest, never the raw token: the caller hashes the cookie value and
  # the plaintext token never reaches the database, so it cannot land in a statement
  # log, an error payload or pg_stat_statements. Lookup is by the unique digest index,
  # and the function returns the same minimal non-secret fields as its sibling plus
  # the Session id the caller needs to lock the row.
  def create_token_authenticator
    execute <<~SQL
      CREATE FUNCTION f1_authenticate_session_by_token(p_token_sha256 bytea)
      RETURNS TABLE (
        id                  uuid,
        account_id          uuid,
        organization_id     uuid,
        status              text,
        idle_expires_at     timestamptz(6),
        absolute_expires_at timestamptz(6),
        authorization_context_version bigint
      )
      LANGUAGE sql STABLE SECURITY DEFINER SET search_path = pg_catalog, public
      AS $$
        SELECT s.id, s.account_id, s.organization_id, s.status, s.idle_expires_at,
               s.absolute_expires_at, s.authorization_context_version
        FROM sessions s
        WHERE s.token_sha256 = p_token_sha256;
      $$;
      REVOKE ALL ON FUNCTION f1_authenticate_session_by_token(bytea) FROM PUBLIC;
    SQL
  end
end
