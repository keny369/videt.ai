# frozen_string_literal: true

require "rails_helper"

# THE CAPABILITY PREDICATE IS WRITTEN THREE TIMES, AND UNTIL NOW NOTHING COMPARED THE COPIES (FU-50).
#
# WHY THIS IS A GATE AND NOT AN EXTRACTION. FU-50's original note argued the copies were safe because
# "the round-15 battery makes the three copies provably agree". THAT BASIS WAS FALSE, and round 19
# measured it: replacing `ra.account_id = $n::uuid` with a same-arity tautology left all 27 battery
# examples green, and across the whole suite the only thing that reacted was a byte-digest staleness
# check that fires identically for a comment-only edit. Six single-conjunct drifts were tried and
# only `FOR SHARE OF ra` was caught.
#
# The architecture lens's reasoned verdict was that EXTRACTION IS THE WRONG REPAIR: the predicate is
# a conjunct of each statement with nothing to hoist, and a shared fragment interpolated into three
# statements moves back toward the rule-split-across-writers shape ADR-095 records. What it asked for
# instead is this file — one spec asserting the three CTEs are equivalent under placeholder
# normalisation.
#
# WHAT THAT BUYS, STATED EXACTLY. It does NOT prove any conjunct is correct; the battery does that,
# one conjunct at a time, at every write. It proves the three copies say THE SAME THING, which is the
# property no proof held and which the battery structurally cannot hold: a conjunct deleted at ONE
# write and left at the others is invisible to a per-write proof and visible here immediately. That
# covers the two conjuncts round 20's attribution matrix found bound by nothing at all —
# `required_role`, inert at two of the three writes, and `ra.organization_id`, unbound across the
# entire suite.
RSpec.describe "the capability-authority CTE says the same thing at every protected write",
               type: :architecture do
  # The three writes are not listed here. `ProtectedWrites::WRITES` is the registry
  # `protected_write_completeness_spec.rb` proves complete against the repository, so a fourth
  # protected write joins this comparison the moment it is registered — rather than being compared
  # against nothing because this file held its own list of three.
  def writes
    ProtectedWrites.covered.to_h do |identity|
      const_name, method = identity.split("#")
      [identity, source_for(const_name, method)]
    end
  end

  # THE FILE IS ASKED OF RUBY, NOT GUESSED FROM THE NAME. `Object.const_source_location` returns
  # where the class was actually defined, so a store that moves — or one whose file does not follow
  # the naming convention — is still read rather than reported missing.
  def source_for(const_name, method)
    path, = Object.const_source_location(const_name)
    raise "#{const_name} has no source location" if path.nil?

    capability_cte(File.read(path), "#{const_name}##{method}")
  end

  # The CTE body, taken by BALANCED PARENTHESES rather than by a line count: the predicate contains
  # `unnest(...)`, `coalesce(...)` and `ANY (...)`, so a scan that stopped at the first `)` would
  # compare a fragment and agree with itself.
  def capability_cte(source, label)
    open_at = source.index("capability_authority AS (")
    raise "#{label} carries no capability_authority CTE" if open_at.nil?

    depth = 0
    paren = source.index("(", open_at)
    (paren...source.length).each do |i|
      depth += 1 if source[i] == "("
      next unless source[i] == ")"

      depth -= 1
      return source[open_at..i] if depth.zero?
    end
    raise "#{label}'s capability_authority CTE is unbalanced"
  end

  # PLACEHOLDER NORMALISATION, WHICH IS WHAT MAKES THE COMPARISON POSSIBLE AT ALL. The same conjunct
  # is `$5` at one write and `$4` at another purely because the three statements bind different
  # numbers of unrelated columns ahead of the authority. Comments go too: they differ deliberately —
  # each store explains the rule in its own terms — and a comparison that failed on prose would be
  # abandoned within a round.
  def normalise(cte)
    without_comments = cte.split("\n").map { |line| line.sub(/--.*$/, "") }.join("\n")
    without_comments.gsub(/\$\d+/, "$?").gsub(/\s+/, " ").strip
  end

  # The predicate reduced to what it actually asserts: the set of conjuncts, order discarded.
  #
  # ORDER IS DISCARDED DELIBERATELY AND THE MEASUREMENT SAYS WHY. `cancel` and `insert_crawl` are
  # byte-identical after normalisation; `activate_version` differs ONLY in where the `required_role`
  # conjunct sits — last, after the read-only limb, rather than before the cell limb. They are all
  # `AND` conjuncts of one `WHERE`, so position changes nothing a reader or PostgreSQL can observe,
  # and a gate that failed on it would be failing on layout. What it must NOT discard is a conjunct
  # that is present at one write and absent at another, which is exactly what a multiset comparison
  # catches.
  def conjuncts(cte)
    normalised = normalise(cte)
    body = normalised.split(" WHERE ", 2).fetch(1)
    # The lock clause is part of the CTE but not of the WHERE, and it is asserted on its own
    # above; leaving it attached would bury it inside the last conjunct.
    body.rpartition(" FOR SHARE OF ra").first.split(" AND ").map(&:strip).sort
  end

  it "carries the identical JOIN, source and lock at every write" do
    shapes = writes.transform_values do |cte|
      normalise(cte).split(" WHERE ", 2).first
    end

    expect(shapes.values.uniq.length).to eq(1),
                                         "the CTEs disagree before their WHERE clause — a different " \
                                         "source, join or unnest arity at one write:\n" \
                                         "#{shapes.map { |k, v| "#{k}\n  #{v}" }.join("\n")}"
    expect(shapes.values.first).to include("FROM role_assignments ra"),
                                   "the predicate no longer reads `role_assignments`, so this whole " \
                                   "comparison is about something else"
  end

  it "locks the re-read rows at every write, which is the one drift the battery caught" do
    writes.each do |identity, cte|
      expect(normalise(cte)).to end_with("FOR SHARE OF ra )"),
                                         "#{identity}'s capability CTE does not end in `FOR SHARE OF " \
                                         "ra`, so the grants it re-reads are not held against a " \
                                         "concurrent revocation"
    end
  end

  it "asserts exactly the same set of conjuncts at every write" do
    sets = writes.transform_values { |cte| conjuncts(cte) }
    reference_name, reference = sets.first

    sets.each do |identity, set|
      next if identity == reference_name

      expect(set).to eq(reference),
                     "the capability predicate differs between #{reference_name} and #{identity}. " \
                     "A conjunct present at one protected write and absent at another is invisible " \
                     "to a per-write proof — round 20 measured `required_role` and " \
                     "`ra.organization_id` as bound by NOTHING in the whole suite, which is why " \
                     "this comparison exists.\n" \
                     "  only at #{reference_name}: #{(reference - set).inspect}\n" \
                     "  only at #{identity}: #{(set - reference).inspect}"
    end
  end

  # ---- THE OPERAND, WHICH THE COMPARISON ABOVE STRUCTURALLY CANNOT SEE (FU-50) --------------------
  #
  # Everything above normalises `$n` to `$?`, so it proves the three PREDICATES agree and can say
  # nothing about what each BINDS. That was the live half of FU-50: `CrawlStartStore#cancel` bound
  # `authority.organization_id` into `ra.organization_id` while `CrawlPolicyStore#activate_version`
  # and `CrawlStore#insert_crawl` bound `row[:organization_id]` — identical text, different sources,
  # and a textual comparison agreeing with itself across the difference.
  #
  # THE VALUES ARE THE SAME TODAY, WHICH IS WHY THIS IS A GATE AND NOT A BUG REPORT. Traced at every
  # call site: `QueueCrawl#commit` and `ActivateCrawlPolicy` both set `org = actor.organization_id`
  # and build their authority from the same actor. So nothing observable changed when the two writes
  # were switched — and NOTHING ENFORCED the agreement, which is the property this file now holds.
  # A future caller passing a row organization other than the authenticated one would have sent the
  # capability CTE looking for grants in the CALLER-SUPPLIED organization.
  #
  # WHY SOURCE AND NOT BEHAVIOUR. A behavioural proof needs the two values to DIFFER at the write, and
  # `WriteAuthority#governs!` now refuses exactly that before the statement runs — the refusal and a
  # behavioural binding proof cannot both exist. So the refusal is proved by execution
  # (`wf005_write_authority_organization_spec.rb`) and the binding is proved here, by reading which
  # parameter each statement actually puts in its organization slots.
  #
  # `$n` IS 1-INDEXED AND RESOLVED THROUGH THE ARRAY ITSELF rather than by counting lines: the element
  # is taken by splitting the literal at top-level commas, so a call, array or hash inside one element
  # cannot shift every index after it.
  AUTHORITY_ORGANIZATION = "authority.organization_id"

  # The `params = [...]` literal that feeds the statement: the last one before the CTE, which is the
  # one in the same method. Taken by balanced brackets for the same reason the CTE is taken by
  # balanced parentheses.
  def params_literal(source, label)
    cte_at = source.index("capability_authority AS (")
    raise "#{label} carries no capability_authority CTE" if cte_at.nil?

    open_at = source.rindex("params = [", cte_at)
    raise "#{label} has no `params = [` before its capability CTE" if open_at.nil?

    bracket = source.index("[", open_at)
    depth = 0
    (bracket...source.length).each do |i|
      depth += 1 if source[i] == "["
      next unless source[i] == "]"

      depth -= 1
      return source[(bracket + 1)...i] if depth.zero?
    end
    raise "#{label}'s params literal is unbalanced"
  end

  # Split at commas that are not inside a call, array, hash or string.
  def params_elements(literal)
    elements = []
    depth = 0
    current = +""
    literal.each_char do |c|
      case c
      when "(", "[", "{" then depth += 1
      when ")", "]", "}" then depth -= 1
      end
      if c == "," && depth.zero?
        elements << current
        current = +""
      else
        current << c
      end
    end
    elements << current
    elements.map { |e| e.gsub(%r{#.*$}, "").strip }.reject(&:empty?)
  end

  # The CTE that establishes the Organization's authorization epoch, taken the same way.
  def epoch_cte(source, label)
    open_at = source.index("epoch_authority AS (")
    raise "#{label} carries no epoch_authority CTE" if open_at.nil?

    depth = 0
    paren = source.index("(", open_at)
    (paren...source.length).each do |i|
      depth += 1 if source[i] == "("
      next unless source[i] == ")"

      depth -= 1
      return source[open_at..i] if depth.zero?
    end
    raise "#{label}'s epoch_authority CTE is unbalanced"
  end

  # identity => { slot description => the Ruby expression bound into it }
  def organization_operands
    ProtectedWrites.covered.to_h do |identity|
      const_name, method = identity.split("#")
      path, = Object.const_source_location(const_name)
      source = File.read(path)
      elements = params_elements(params_literal(source, identity))

      slot = lambda do |text, pattern, description|
        index = text[pattern, 1]
        raise "#{identity}: #{description} binds no placeholder (#{pattern.source})" if index.nil?

        [description, elements.fetch(index.to_i - 1)]
      end

      [identity, [
        slot.call(capability_cte(source, identity), /ra\.organization_id = \$(\d+)::uuid/,
                  "the capability CTE's organization"),
        slot.call(epoch_cte(source, identity), /WHERE id = \$(\d+)::uuid/,
                  "the epoch CTE's organization")
      ].to_h.merge("method" => method)]
    end
  end

  it "binds the AUTHENTICATED authority's organization into every organization slot, at every write" do
    organization_operands.each do |identity, slots|
      slots.except("method").each do |description, expression|
        expect(expression).to eq(AUTHORITY_ORGANIZATION),
                              "#{identity}: #{description} is bound to `#{expression}`, not to " \
                              "`#{AUTHORITY_ORGANIZATION}`. A protected write derives its organization " \
                              "from the authenticated Session and never from caller input — a row " \
                              "operand sends the capability CTE looking for grants in whichever " \
                              "organization the caller named (FU-50)."
      end
    end
  end

  it "resolves a real, distinct operand per slot, so the assertion above is not agreeing with nothing" do
    # NON-VACUITY. If `params_elements` returned one blob, or the regex matched the wrong `$n`, every
    # write would report the same expression and the check above would pass while reading nothing.
    # Each store's parameter list is long and its two organization slots are resolved independently,
    # so this requires the parse to have actually worked.
    operands = organization_operands
    expect(operands.length).to be >= 3, "fewer than three protected writes were read"

    operands.each do |identity, slots|
      const_name, = identity.split("#")
      path, = Object.const_source_location(const_name)
      elements = params_elements(params_literal(File.read(path), identity))
      expect(elements.length).to be >= 10,
                                 "#{identity}: the parameter list split into #{elements.length} " \
                                 "element(s), so every index resolved above is meaningless"
      expect(elements).to include("authority.epoch"),
                          "#{identity}: the parsed parameter list does not contain `authority.epoch`, " \
                          "so it is not the list the statement is bound to"
      expect(slots.keys).to contain_exactly("the capability CTE's organization",
                                            "the epoch CTE's organization", "method")
    end
  end

  it "compares a non-trivial predicate, so agreement is not agreement about nothing" do
    # NON-VACUITY. If the extraction returned a fragment, or the split produced one conjunct, three
    # writes would agree perfectly and this file would be worth nothing. The conjuncts round 20
    # enumerated are named individually, so a predicate that lost one still agrees with itself and
    # fails HERE.
    sets = writes.transform_values { |cte| conjuncts(cte) }

    expect(sets.length).to be >= 3, "fewer than three protected writes were compared"
    sets.each do |identity, set|
      expect(set.length).to be >= 8, "#{identity} reduced to #{set.length} conjunct(s): the parse is " \
                                     "returning a fragment and every comparison above is vacuous"
      %w[ra.status ra.effective_at ra.expires_at ra.account_id ra.organization_id
         ra.canonical_role ra.permission_mode
         ra.bootstrap_admin_exception ra.protected_permission_allowlist].each do |column|
        expect(set.join(" ")).to include(column),
                                 "#{identity}'s predicate no longer mentions `#{column}`"
      end
    end
  end
end
