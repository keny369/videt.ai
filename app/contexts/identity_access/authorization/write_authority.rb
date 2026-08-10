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
    # THE SCOPE AXIS IS BOUND, AND CONTAINMENT IS NOW PARTLY DECIDED (FU-2, sited by FU-49).
    # `scope_hex` is carried and compared, so the write refuses if the grant's scope is not the one
    # the decision evaluated. FU-49 recorded that the CONTAINMENT predicate belongs in the capability
    # CTE beside the bindings D7 added rather than in a fourth Ruby guard, and `required_scope_hex`
    # is the operand that puts it there. What it can and cannot decide is stated at that member.
    #
    # EVERY VALUE COMES FROM THE AUTHENTICATED ACTOR AND ITS OWN DECISION, never from caller input.
    WriteAuthority = Data.define(:organization_id, :account_id, :capability, :epoch,
                                 :grant_ids, :grant_versions, :grant_scopes, :required_role,
                                 :allowed_roles, :read_only_permitted, :protected_capability,
                                 :required_scope_hex) do
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
      # `allowed_roles` IS THE CAPABILITY, CARRIED (round-17 security finding R17-SEC-1).
      #
      # WHAT WAS OPEN, AND WHY IT LOOKED CLOSED. FU-48's whole purpose was that the capability axis
      # "was enforced ONLY in Ruby, one deletion away from nothing", and the stores said so: "the
      # write now re-reads the granting Role Assignments the decision relied on, so deleting the Ruby
      # check no longer produces an unauthorised Crawl." But `capability` was never SENT to
      # PostgreSQL. The statement asked only whether one of the carried grants is still live — grant
      # LIVENESS, not capability — so a grant conferring nothing satisfied it. Measured: an account
      # whose only grant is `TechnicalImplementer`, a role the ratified baseline denies
      # `crawl.trigger` and `crawl.cancel` outright, was authorised by the write, and so was a
      # capability string that does not exist in the baseline at all. Only `ActivateCrawlPolicy` was
      # safe, and only by the accident that `SCOPE_ROLE`'s roles happen to be inside its capability's
      # cell.
      #
      # AND THE SIXTH COLUMN TOO (round-18 finding CB-1). `CAPABILITIES` is keyed by
      # `canonical_role` ALONE — `permission_baseline.rb` says so in as many words: "THE SIXTH COLUMN
      # OF THE SAME ROW, WHICH `CAPABILITIES` CANNOT EXPRESS". `confers?` is three conjuncts and the
      # first repair bound one. Measured: a Read-Only Executive Buyer — `MarketingOperator` +
      # `read_only` + `executive_buyer`, the tuple whose cell at `:147` reads `deny` — carries a
      # `canonical_role` that IS in the cell, so it satisfied the role predicate and IRREVERSIBLY
      # CANCELLED A RUNNING CRAWL. R17-SEC-1's shape, one column over, inside the repair for it.
      #
      # `read_only_permitted` is the sixth column carried the same way: `READ_ONLY_CAPABILITIES` is
      # the ratified list of capabilities a read-only Assignment may still spend, and it is EMPTY BY
      # TRANSCRIPTION for everything this build materializes. The statement binds
      # `($n::boolean OR ra.permission_mode <> 'read_only')`, so a read-only grant confers nothing
      # unless the baseline says that capability survives read-only.
      #
      # WHY THIS IS THE BASELINE CELL AND NOT A SECOND COPY OF THE ALGORITHM. ADR-132 ruled out
      # re-deriving the six-step algorithm in SQL, and this does not: `CAPABILITIES` is IMMUTABLE FOR
      # THE LIFE OF A DEPLOY, read ONCE in Ruby, and handed to the statement as a value — exactly the
      # shape `required_role` already had for the ratified scope rule. What the statement re-reads is
      # still only row state another transaction can move: which role the granting Assignment holds.
      # THE PROTECTED LIMB, WHICH THE STATEMENT DID NOT CARRY (FU-58).
      #
      # WHAT WAS OPEN, AND WHY THE STORES' OWN COMMENT WAS INACCURATE. `CommandAuthorizer#confers?`
      # is FOUR limbs, not two: the baseline cell, the mode cell, and then — for a capability in
      # `PROTECTED` — the bootstrap-admin exception or the Assignment's approved
      # `protected_permission_allowlist`. `return true unless PROTECTED.key?(capability)` is a
      # property of the RUBY evaluator with no analogue in the CTE, so what the write carried was the
      # baseline MINUS its protected limb while three stores said "this is the baseline CARRIED".
      #
      # MEASURED, AND THE EXPOSED SURFACE IS EXACTLY TWO CAPABILITIES. `CAPABILITIES` materializes 20
      # keys and `PROTECTED` names 18; their intersection is `role.manage` and `invitation.approve`,
      # because `CAPABILITIES.fetch` raises for the other 16 and the authority cannot be built at all.
      # At `CrawlStartStore#cancel`, an ordinary OrganizationAdmin grant and capability `role.manage`
      # is DENIED by Ruby (`missing_authority`) and was AUTHORIZED by the write, which irreversibly
      # cancelled a running Crawl.
      #
      # IT IS CARRIED AS A DERIVED BOOLEAN, NOT RE-DERIVED IN SQL. `PROTECTED` is immutable for the
      # life of a deploy and is read once, here — the same shape `read_only_permitted` already has for
      # the sixth column and `allowed_roles` for the cell. What the statement re-reads is still only
      # row state another transaction can move: this Assignment's allowlist and its exception flag.
      #
      # THE ALTERNATIVE WAS REFUSING AT THE BUILDER, and it was not taken. Raising for a `PROTECTED`
      # capability would turn the caller census into an enforced invariant, which is smaller — but it
      # leaves the SQL still unable to answer the question, so the next protected write inherits the
      # gap, and it makes the defect unprovable by execution: nothing could then drive the statement
      # with a protected capability to show it refuses.
      # THE CONTAINMENT OPERAND, AND EXACTLY WHAT IT CAN DECIDE (FU-2, sited by FU-49).
      #
      # WHAT WAS OPEN. `GrantAuthority#contains_scope?` is the only containment predicate in the
      # platform and is reached only through `evaluate`, whose `CAPABILITY` is the literal
      # `"role.manage"`, plus the revoke path. For every OTHER capability an Assignment's scope was
      # carried, compared for EQUALITY with the scope the decision evaluated, and never checked for
      # containment against the TARGET. Measured on this branch: an OrganizationAdmin whose
      # Assignment carries a PROJECT scope digest activated an immutable ORGANIZATION-scope crawl
      # policy — the grant is live, the role is the one `SCOPE_ROLE["organization"]` demands, and
      # nothing asked whether a Project scope contains an Organization-wide target.
      #
      # WHAT `required_scope_hex` IS. Not "the target's scope" but THE SCOPE AN ASSIGNMENT MUST HOLD
      # TO CONTAIN THIS TARGET, when that is a single nameable scope — and NULL when it is not. For
      # an Organization-scope target it is exactly Organization scope, and `GrantAuthority`'s digest
      # of it is reused rather than transcribed a fourth time.
      #
      # WHY THE OTHER HALF OF FU-2 IS NOT DECIDED HERE, STATED SO NOBODY READS MORE INTO IT.
      # `role_assignments` stores the grant's scope ONLY as `scope_sha256`, a one-way digest of a
      # `GrantScope` (`API_CONTRACTS.md:373`: `scope_kind`, `project_ids`, `resources`). The
      # STRUCTURE is stored nowhere — measured against `db/structure.sql`, no column on that table or
      # any other holds it for an Assignment. A digest answers exactly two containment questions:
      # "is this Organization scope, which contains everything" and "is this scope THE SAME scope".
      # It cannot answer "does this scope, covering projects P and Q, contain project P", because a
      # scope covering `[P, Q]` legitimately contains P and hashes differently from one covering
      # `[P]`. So a RESOURCE-scope target has no single scope an Assignment must hold, the write
      # cannot name one, and this carries NULL rather than an approximation. FU-2's resource limb
      # therefore remains open and is NOT claimed closed; what it needs first is a stored or
      # reconstructible normalized scope, which is a schema question and not a repair.
      #
      # NULL MEANS "NO CONTAINMENT CLAIM", spelled so it cannot silently mean "contained". The
      # statement's limb is `$n IS NULL OR ...`, the same shape `required_role` already has for the
      # ratified scope rule: a NULL that means "no rule", never "no check".
      def self.for(actor:, decision:, capability:, required_role: nil, required_scope_hex: nil)
        grants = decision.granting
        new(organization_id: actor.organization_id, account_id: actor.account_id, capability:,
            epoch: actor.authorization_epoch, required_role:, required_scope_hex:,
            allowed_roles: Platform::PermissionBaseline::CAPABILITIES.fetch(capability),
            read_only_permitted: Platform::PermissionBaseline::READ_ONLY_CAPABILITIES.include?(capability),
            protected_capability: Platform::PermissionBaseline::PROTECTED.key?(capability),
            grant_ids: grants.map { |g| g["id"] },
            grant_versions: grants.map { |g| g["state_version"].to_i },
            grant_scopes: grants.map { |g| g["scope_hex"] || NO_SCOPE })
      end

      # THE ORGANIZATION THE AUTHORITY IS FOR, AND THE REFUSAL THAT KEEPS IT THE ONLY ONE (FU-50).
      #
      # WHAT WAS OPEN, STATED NARROWLY. Two of the three protected writes bound the ROW's
      # `organization_id` into the capability CTE's organization slot and one bound the AUTHORITY's.
      # Traced at every call site, the two values are the same today — `QueueCrawl` and
      # `ActivateCrawlPolicy` both set `org = actor.organization_id` and build their authority from the
      # same actor — so the divergence was textual rather than semantic. What was unproved was not that
      # the writes disagreed but that NOTHING ENFORCED their agreement: a future caller passing a row
      # organization other than the authenticated one would have had the capability CTE look for grants
      # in the CALLER-SUPPLIED organization, and no spec, guard or gate would have noticed.
      #
      # THE OWNER'S DECISION IS THAT ALL THREE BIND THE AUTHORITY'S, because that value is derived from
      # the authenticated Session and never from caller input. Binding alone, though, only decides
      # WHICH value wins — it does not stop the two from differing, and after it the authority limbs
      # would answer about the authenticated Organization while the row still carried another one.
      # `crawls_context` and `crawl_policies_context` would then refuse the INSERT, so the divergence
      # would surface as an RLS error from the database rather than as a broken contract at the store.
      # This makes the agreement the store's own rule: the write refuses BEFORE the statement, naming
      # both values.
      #
      # IT RAISES RATHER THAN DENYING. A denial is a domain outcome a caller may legitimately provoke;
      # this is reachable only from an implementation defect, which is precisely what
      # `Platform::InvariantViolation` is for.
      def governs!(candidate, at:)
        return if candidate.to_s == organization_id.to_s

        raise Platform::InvariantViolation,
              "#{at}: the row names organization #{candidate.inspect} and the authenticated authority " \
              "is for #{organization_id.inspect}. A protected write derives its organization from the " \
              "authenticated Session, never from caller input (FU-50)."
      end

      # The three arrays are positional: entry N of each describes one granting Assignment, and the
      # statement joins them with `unnest(...)` so a mismatched length cannot silently pair the wrong
      # version with the wrong Assignment.
      def grants? = !grant_ids.empty?

      def uuid_array = pg_array(grant_ids)
      def bigint_array = pg_array(grant_versions)
      def text_array = pg_array(grant_scopes)
      def allowed_roles_array = pg_array(allowed_roles)

      # Bound to the same actor and epoch the attestation names, so a write cannot be handed one
      # command's authority while another command's attestation is presented.
      def same_principal?(other)
        other.is_a?(self.class) && other.account_id == account_id &&
          other.organization_id == organization_id && other.epoch == epoch &&
          other.capability == capability && other.grant_ids == grant_ids &&
          other.required_role == required_role && other.allowed_roles == allowed_roles &&
          other.required_scope_hex == required_scope_hex &&
          other.read_only_permitted == read_only_permitted &&
          other.protected_capability == protected_capability &&
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
