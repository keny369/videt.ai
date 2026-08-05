# frozen_string_literal: true

module IdentityAccess
  module Authorization
    # THE AUTHORITY A PROTECTED WRITE CARRIES INTO POSTGRESQL (FU-48).
    #
    # WHAT FU-48 IS. Until now the only authority a protected write evaluated for itself was the
    # Organization's `authorization_epoch`, and `QueueCrawl` said so in as many words: the conjunct
    # "detects a CHANGE in authority since authentication. It does not detect the ABSENCE of a
    # capability: `decision.allowed?` above is the only thing that refuses an actor who never held
    # `crawl.trigger`, and deleting it lets such an actor queue a Crawl that this write will happily
    # insert." The capability axis was enforced ONLY in Ruby, one deletion away from nothing, and the
    # owner has now decided it must have a write-level counterpart.
    #
    # WHAT THE COUNTERPART IS, AND WHY IT IS THIS AND NOT A SECOND IMPLEMENTATION OF THE ALGORITHM.
    # The six-step effective-permission algorithm (`:322-329`) reads two kinds of input. One kind is
    # IMMUTABLE FOR THE LIFE OF A DEPLOY — the `permission-baseline-v1` cells, the protected-grant
    # enumeration — and cannot change under a running command. The other kind is ORDINARY ROW STATE
    # that another transaction can move while this one waits: whether the Assignment that conferred
    # the capability is still active, still effective, not yet expired, at the version and scope the
    # decision saw. Only the second kind can go stale, and only the second kind belongs in the
    # statement. Re-deriving the baseline in SQL would put a second copy of the authority in the
    # database, which is the opposite of what this repository is for.
    #
    # So the write carries the GRANTS the decision actually relied on — `Decision#granting_assignments`
    # — and PostgreSQL re-reads them, under `FOR SHARE`, in the same statement as the transition. An
    # actor who never held the capability has no granting Assignment, so the array is empty, so the
    # predicate is false and the write applies nothing. The Ruby check remains the DENIAL path, so
    # such an actor is refused politely rather than reaching a write that would refuse it anyway.
    #
    # THE SCOPE AXIS IS BOUND, AND CONTAINMENT IS NOT INVENTED HERE. `scope_hex` is carried and
    # compared, so the write refuses if the grant's scope is not the one the decision evaluated.
    # Whether an Assignment's scope must CONTAIN the target is FU-2 — a pre-existing, platform-wide
    # deferral recorded in DECISIONS.md for every resource capability, not an S-07-009 question — and
    # this class deliberately does not decide it. What it does is give that axis a place at the write,
    # so the containment predicate has one obvious home when FU-2 is taken.
    #
    # EVERY VALUE COMES FROM THE AUTHENTICATED ACTOR AND ITS OWN DECISION, never from caller input.
    WriteAuthority = Data.define(:organization_id, :account_id, :capability, :epoch,
                                 :grant_ids, :grant_versions, :grant_scopes, :required_role) do
      # `scope_hex` is NULL for an Organization-scope Assignment. It is normalised to the empty
      # string on both sides rather than carried as a NULL, because a NULL never equals a NULL and a
      # scope comparison that is silently never true is a conjunct that does nothing — the same shape
      # as every defect this tranche has produced. `invitation_store.rb` already uses this idiom.
      NO_SCOPE = ""

      # `required_role` is the ratified SCOPE RULE, carried to the write (FU-48's scope limb).
      #
      # WHY IT IS A PARAMETER AND NOT A SECOND COPY OF THE RULE. `:732`/`:738` bind a crawl-policy
      # scope to a canonical role — Organization scope to OrganizationAdmin, Project scope to
      # MarketingOperator — and `ActivateCrawlPolicy` already transcribes that once. What was missing
      # is that the transcription lived ONLY in a Ruby predicate: the round-two security lens removed
      # its single operand and a MarketingOperator committed an ORGANIZATION-scope policy, surviving
      # 2364 examples. The role the SCOPE demands is now derived from the scope and handed to the
      # statement, so the write refuses a grant that does not hold it whatever the Ruby predicate does.
      #
      # It is nil for a command whose capability carries no scope rule, and the statement then binds
      # only the grant itself — a NULL that means "no rule", spelled so it cannot silently mean
      # "no check".
      def self.for(actor:, decision:, capability:, required_role: nil)
        grants = decision.granting
        new(organization_id: actor.organization_id, account_id: actor.account_id, capability:,
            epoch: actor.authorization_epoch, required_role:,
            grant_ids: grants.map { |g| g["id"] },
            grant_versions: grants.map { |g| g["state_version"].to_i },
            grant_scopes: grants.map { |g| g["scope_hex"] || NO_SCOPE })
      end

      # The three arrays are positional: entry N of each describes one granting Assignment, and the
      # statement joins them with `unnest(...)` so a mismatched length cannot silently pair the wrong
      # version with the wrong Assignment.
      def grants? = !grant_ids.empty?

      def uuid_array = pg_array(grant_ids)
      def bigint_array = pg_array(grant_versions)
      def text_array = pg_array(grant_scopes)

      # Bound to the same actor and epoch the attestation names, so a write cannot be handed one
      # command's authority while another command's attestation is presented.
      def same_principal?(other)
        other.is_a?(self.class) && other.account_id == account_id &&
          other.organization_id == organization_id && other.epoch == epoch &&
          other.capability == capability && other.grant_ids == grant_ids &&
          other.required_role == required_role &&
          other.grant_versions == grant_versions && other.grant_scopes == grant_scopes
      end

      private

      def pg_array(values)
        "{#{values.map { |v| quote(v) }.join(',')}}"
      end

      def quote(value)
        %("#{value.to_s.gsub('\\', '\\\\\\\\').gsub('"', '\\"')}")
      end
    end
  end
end
