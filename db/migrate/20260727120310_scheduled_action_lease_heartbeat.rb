# frozen_string_literal: true

# F-04 (FU-24, DECISIONS ADR-091): the FENCED scheduled-action lease heartbeat.
#
# WHY A HEARTBEAT AND NOT A LONGER LEASE. `WORKER_LEASE_SECONDS` is 30 and legitimate work can exceed it
# — one content attempt is bounded PER HOP, so the initial request plus the ratified 10-redirect budget is
# 11 connections at the 15-second hard timeout, and sitemap discovery paces :444's 30 and 120 seconds
# between candidates. The lease therefore expired under a LIVE worker, the sweep returned the action to
# `pending`, and the ordinary path executed twice. A permanently longer lease removes that by making
# recovery of genuinely dead workers slower by exactly the same amount: it has to be sized for the worst
# legitimate case, and every real process loss then waits that long. A heartbeat keeps both ends short.
#
# THE FENCE IS THE POINT, and an unconditional `UPDATE ... WHERE id = ?` would be a worse race than the one
# it fixes: a worker whose claim had already transferred would silently extend the NEW owner's lease and
# resurrect its own. Renewal therefore matches, all at once:
#
#   * the action identity;
#   * the claim owner — the worker's fencing token, minted per worker and never reused;
#   * the claim generation, which `f1_claim_due_scheduled_actions` increments on every reclaim;
#   * the expected executable state, `dispatched`;
#   * a lease that has NOT ALREADY LAPSED. This is the supersession check: once `lease_expires_at` is in
#     the past the sweep may take the row at any moment, so a worker that has already lost its window may
#     not extend it. Without this predicate a stale worker could renew in the gap before the sweep ran and
#     keep an action alive that the transport had given up on.
#
# ON AN ORGANIZATION IDENTIFIER, which the owner asked to be assessed rather than assumed: it is NOT
# added, and the reason is that it would fence nothing. `scheduled_actions` is a transport table served by
# one scheduler across every tenant; the ratified transport functions are `SECURITY DEFINER` and take no
# organization, and the row's own `organization_id` is immutable under the guard. Ownership here is
# established by `(claim_owner, claim_generation)`, which is a genuine fencing token pair; an organization
# argument would be a scoping assertion about a value the caller already read from the row it is renewing,
# and a caller able to pass the wrong one is equally able to pass the wrong organization. Tenant isolation
# on this path is the transport connection's, exactly as it is for claim, dispatch, settle and release.
#
# NO TIME ARGUMENT, matching every current transport function: BACKGROUND_PROCESSING.md :114 makes
# PostgreSQL transaction time the sole due-time and lease authority, and a renewal that accepted an instant
# would be a way for a caller to lie about when its lease should end.
#
# `dispatched -> dispatched` is already a permitted transition, and `last_heartbeat_at` already exists with
# its `last_heartbeat_at IS NULL OR claim_owner IS NOT NULL` CHECK: F-04 anticipated this and left the
# renewal unbuilt. Nothing else changes.
class ScheduledActionLeaseHeartbeat < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL
      CREATE FUNCTION f1_heartbeat_scheduled_action(
        p_action_id uuid, p_owner uuid, p_generation bigint, p_lease_seconds integer
      )
      RETURNS boolean
      LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = pg_catalog, public
      AS $$
      DECLARE v_now timestamptz(6) := transaction_timestamp(); v_changed integer;
      BEGIN
        UPDATE scheduled_actions a
        SET lease_expires_at = v_now + make_interval(secs => greatest(p_lease_seconds, 1)),
            last_heartbeat_at = v_now,
            updated_at = v_now, state_version = a.state_version + 1
        WHERE a.id = p_action_id
          AND a.claim_owner = p_owner
          AND a.claim_generation = p_generation
          AND a.status = 'dispatched'
          -- Supersession: an already-lapsed lease is the sweep's to take, never this worker's to extend.
          AND a.lease_expires_at > v_now;
        GET DIAGNOSTICS v_changed = ROW_COUNT;
        RETURN v_changed > 0;
      END;
      $$;
      REVOKE ALL ON FUNCTION f1_heartbeat_scheduled_action(uuid, uuid, bigint, integer) FROM PUBLIC;
    SQL
    F1::RuntimeGrants.apply_all(connection)
  end

  def down
    execute <<~SQL
      DROP FUNCTION IF EXISTS f1_heartbeat_scheduled_action(uuid, uuid, bigint, integer);
    SQL
  end
end
