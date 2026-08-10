# frozen_string_literal: true

module Workflows
  module Wf005
    # PROOF THAT CURRENT AUTHORITY WAS RE-READ IN THIS TRANSACTION, WHICH THE PROTECTED WRITE DEMANDS
    # (round 9, R9-3; extended to the capability axis by FU-48 in D7).
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
    # names the actor and the epoch it saw, so it cannot be reused for a different actor. Since FU-48
    # it also names the CAPABILITY and the GRANTS the decision relied on, so it cannot be reused for
    # a different capability or handed to a write carrying different authority — the write's
    # parameters and the attestation must be the same `WriteAuthority`.
    #
    # IT IS NOT A SECOND RECHECK. `CommandAuthorizer.authority_current?` remains the ratified durable
    # checkpoint and the only implementation; this carries its RESULT to the write that depends on it.
    class AuthorityAttestation
      # Raised when a protected write is attempted without proof of a post-wait recheck. It is an
      # invariant violation rather than a domain denial because a handler reaching its commit without
      # one is a defect in the handler, not a decision about the caller.
      class Missing < Platform::InvariantViolation; end

      def initialize(authority:, transaction_id:, connection_id:)
        @authority = authority
        @transaction_id = transaction_id
        @connection_id = connection_id
        freeze
      end

      # NO PUBLIC READERS. `attr_reader :authority, :transaction_id` and the three delegating readers
      # `actor_account_id`, `epoch` and `capability` were added with FU-48 and asked by nothing —
      # measured over the whole tree, including the specs (round-15 architecture finding A15-3). D1's
      # rule governs: "a method nothing asks cannot be defended by any behavioural proof, because no
      # behaviour depends on it — its body could be replaced by a constant and every example would
      # still pass." Everything this object is for happens in `verify!`, against its own ivars: an
      # attestation is a capability to commit, not a data structure to read fields off.
      # THE ONLY MINT. Re-reads current authority through the ratified checkpoint and returns an
      # attestation when it holds, or nil when it does not — so a handler branches on the nil exactly
      # as it branched on the old boolean, and the commit is what enforces the rest.
      #
      # IT ALSO REFUSES TO MINT WITHOUT A POSITIVE CAPABILITY DECISION (FU-48). An actor who never
      # held the capability has no granting Assignment, and an attestation naming no grant would
      # carry an empty array to a write whose predicate then cannot be satisfied. Refusing here means
      # the handler denies at the same place it always did rather than reaching a write that would
      # refuse it anyway.
      def self.attest(connection, auth_store:, actor:, decision:, capability:, required_role: nil,
                      required_scope_hex: nil)
        return nil unless decision.allowed?
        return nil unless IdentityAccess::Authorization::CommandAuthorizer.authority_current?(
          store: auth_store, actor:
        )

        authority = IdentityAccess::Authorization::WriteAuthority.for(actor:, decision:, capability:,
                                                                      required_role:,
                                                                      required_scope_hex:)
        return nil unless authority.grants?

        new(authority:, transaction_id: transaction_id_of(connection), connection_id: connection.object_id)
      end

      # THE FIRST STATEMENT OF EVERY PROTECTED COMMIT. Raises unless the attestation was minted by a
      # passing recheck, for this actor, on this connection, inside this transaction, and for exactly
      # the authority the write is about to carry.
      def self.require!(attestation, connection:, authority:)
        raise Missing, "protected write attempted with no post-wait authority attestation" if attestation.nil?
        unless attestation.is_a?(self)
          raise Missing, "protected write attempted with #{attestation.class} in place of an attestation"
        end

        attestation.verify!(connection:, authority:)
      end

      def verify!(connection:, authority:)
        unless @connection_id == connection.object_id
          raise Missing, "authority attestation was read on a different connection"
        end
        unless @authority.same_principal?(authority)
          raise Missing, "authority attestation names a different actor, epoch, capability or grant set"
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
