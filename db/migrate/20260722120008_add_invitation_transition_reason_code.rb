# frozen_string_literal: true

# The retained machine transition reason for a terminal Invitation transition.
#
# The event catalogue gives `InvitationExpired` reason source `transition`
# (API_CONTRACTS.md :773 and the row at :866), and the `state_transition` profile
# defines `transition_reason_code` as a value that "copies only an exact machine
# `transition_reason_code` retained separately from human reason/rationale"
# (:938), with root `reason_code` equal to it. `EventReasonCode` (:717) forbids
# deriving, slugging or defaulting a code from prose, so the machine code cannot
# share the existing `invitations.reason` column, which holds the human 1-2,000
# character decline/revoke text.
#
# This column is that separate retained field, shaped like `bootstrap_grants`'
# `reason_code NULL` (schemas/POSTGRESQL_SCHEMA.md :264) and constrained to the
# `EventReasonCode` token grammar. It stays null for the transitions whose
# catalogue reason source is `none` (`InvitationAccepted`, `InvitationDeclined`,
# `InvitationRevoked`), so AcceptInvitation, DeclineInvitation and
# RevokeInvitation are unchanged in behaviour and in the events they emit.
class AddInvitationTransitionReasonCode < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL
      ALTER TABLE invitations
        ADD COLUMN transition_reason_code text
          CHECK (transition_reason_code IS NULL OR transition_reason_code ~ '^[a-z][a-z0-9_]{0,119}$');
    SQL
  end

  def down
    execute "ALTER TABLE invitations DROP COLUMN IF EXISTS transition_reason_code;"
  end
end
