# frozen_string_literal: true

module Workflows
  module Wf005
    # PROOF THAT CURRENT AUTHORITY WAS RE-READ IN THIS TRANSACTION, WHICH THE PROTECTED WRITE DEMANDS
    # (round 9, R9-3).
    #
    # WHY THIS EXISTS RATHER THAN A LONGER TEST MATRIX. Round 7 added the post-wait recheck. Round 8
    # found the proofs were branch-depth-one and named two bypasses; round 9's repair drove both of
    # those axes and round 9's review then found a THIRD — `unless current || ...` — which survived
    # the entire suite and committed a policy activation on revoked authority. Two rounds of adding
    # the branch someone had just thought of is the evidence that no branch matrix closes this: a
    # guard written as a Boolean expression can always grow another operand.
    #
    # SO THE WRITE, NOT THE TEST, IS WHAT REFUSES. `authority_current!` is the only thing that mints
    # an attestation, and `require!` is the first statement of every protected commit. A guard that
    # short-circuits past the recheck mints nothing, so the commit raises instead of committing —
    # whatever the Boolean arrangement, whichever operand is added, however the condition is spelled,
    # extracted into a helper or reordered. The invalid state is unreachable rather than untested.
    #
    # WHAT IT IS BOUND TO, AND WHY EACH PART. An attestation is only good for the connection it was
    # read on and the transaction that read it (`txid_current()`), so one cannot be carried from an
    # earlier transaction, from another command, or from a different backend in the same process. It
    # names the actor and the epoch it saw, so it cannot be reused for a different actor.
    #
    # IT IS NOT A SECOND RECHECK. `CommandAuthorizer.authority_current?` remains the ratified durable
    # checkpoint and the only implementation; this carries its RESULT to the write that depends on it.
    class AuthorityAttestation
      # Raised when a protected write is attempted without proof of a post-wait recheck. It is an
      # invariant violation rather than a domain denial because a handler reaching its commit without
      # one is a defect in the handler, not a decision about the caller.
      class Missing < Platform::InvariantViolation; end

      attr_reader :actor_account_id, :epoch, :transaction_id

      def initialize(actor_account_id:, epoch:, transaction_id:, connection_id:)
        @actor_account_id = actor_account_id
        @epoch = epoch
        @transaction_id = transaction_id
        @connection_id = connection_id
        freeze
      end

      # THE ONLY MINT. Re-reads current authority through the ratified checkpoint and returns an
      # attestation when it holds, or nil when it does not — so a handler branches on the nil exactly
      # as it branched on the old boolean, and the commit is what enforces the rest.
      def self.attest(connection, auth_store:, actor:)
        return nil unless IdentityAccess::Authorization::CommandAuthorizer.authority_current?(
          store: auth_store, actor:
        )

        new(actor_account_id: actor.account_id, epoch: actor.authorization_epoch,
            transaction_id: transaction_id_of(connection), connection_id: connection.object_id)
      end

      # THE FIRST STATEMENT OF EVERY PROTECTED COMMIT. Raises unless the attestation was minted by a
      # passing recheck, for this actor, on this connection, inside this transaction.
      def self.require!(attestation, connection:, actor:)
        raise Missing, "protected write attempted with no post-wait authority attestation" if attestation.nil?
        unless attestation.is_a?(self)
          raise Missing, "protected write attempted with #{attestation.class} in place of an attestation"
        end

        attestation.verify!(connection:, actor:)
      end

      def verify!(connection:, actor:)
        unless @connection_id == connection.object_id
          raise Missing, "authority attestation was read on a different connection"
        end
        unless @actor_account_id == actor.account_id && @epoch == actor.authorization_epoch
          raise Missing, "authority attestation names a different actor or epoch"
        end

        current = self.class.transaction_id_of(connection)
        unless @transaction_id == current
          raise Missing, "authority attestation was read in transaction #{@transaction_id}, " \
                         "and the protected write is in #{current}"
        end

        true
      end

      # `txid_current()` assigns a real transaction id on first call and returns the same value for
      # the rest of the transaction, so two calls agreeing IS the statement that both ran inside one.
      def self.transaction_id_of(connection)
        connection.exec("SELECT txid_current() AS id").getvalue(0, 0).to_s
      end
    end
  end
end
