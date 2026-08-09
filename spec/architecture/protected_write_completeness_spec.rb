# frozen_string_literal: true

require "rails_helper"
require "prism"

# THE PROTECTED-WRITE SET, DERIVED FROM THE REPOSITORY RATHER THAN REMEMBERED (FU-61).
#
# WHAT WAS OPEN. `wf005_grant_battery_spec.rb` runs twelve shared examples at every entry in a map
# of protected writes, and round 19 called that STRUCTURAL rather than three more proofs. The claim
# rests entirely on inheritance, and inheritance only covers what is in the map — so A FOURTH
# PROTECTED WRITE WOULD INHERIT NONE OF THEM and nothing would say so. Round 20 built exactly that
# fourth write and watched the suite stay green.
#
# Completeness WAS established that round, by planning all 391 SQL statements in `app/` and `lib/`
# through `EXPLAIN (GENERIC_PLAN)` and collecting `ModifyTable` nodes: exactly six statements modify
# `crawls`/`crawl_policies`, the three human-authorized ones carry `WriteAuthority` and the three
# service ones have no human path. That was a REVIEW ACTIVITY. It does not run again, and this
# repository's standing lesson — recorded four separate times in `governed_write_sentinel.rb` alone
# — is that a list is always one entry short of reality. This is the gate.
#
# WHY THE `capability_authority` CTE IS THE DERIVATION, AND WHY THE OBVIOUS ALTERNATIVE IS WRONG.
# An earlier draft of the follow-up offered "every store method taking an `authority:` parameter".
# Measured, that derivation covers 1 of 3: only `CrawlStartStore#cancel` takes it as a keyword;
# `insert_crawl` and `activate_version` receive it inside a row Hash via `row.fetch(:authority)`,
# and an `[:authority]` grep additionally matches an unrelated WF-013 ledger column. A gate written
# to that spec would have covered a third of the set AND PASSED — this tranche's own defect class
# inside the repair for it. The CTE derivation is exact repo-wide: 3 of 3, zero false positives.
RSpec.describe "the protected-write set is derived, not remembered", type: :architecture do
  # THE CTE THAT MAKES A WRITE PROTECTED. `WriteAuthority` exists so the capability axis has a
  # write-level counterpart, and this is the counterpart: the statement re-reads the granting
  # Assignments under `FOR SHARE` and applies nothing when none survives. A statement carrying it is
  # a protected write by definition, which is what makes this a derivation rather than a second list.
  def capability_cte = "capability_authority AS ("
  # The sibling limb, used only to CORROBORATE. Every protected write carries both, so a set derived
  # from one and a set derived from the other must agree; if they ever disagree, one of the two
  # derivations has stopped describing the same thing and this gate says so before it is trusted.
  def epoch_cte = "epoch_authority AS ("

  def sources
    @sources ||= (Rails.root.glob("app/**/*.rb") + Rails.root.glob("lib/**/*.rb")).sort
  end

  # `Namespace::Class#method` => how many times `marker` occurs inside that definition, read out of
  # the parsed source.
  #
  # PARSED, NOT GREPPED. A line-counting scan has to guess where a method ends, and a guess that
  # attributes a statement to the wrong method — or to no method — fails OPEN: the derived set comes
  # back short and the comparison below passes. Prism gives the enclosing definition exactly, and
  # the first example checks that every occurrence in the corpus landed in one.
  def occurrences_in_definitions(marker)
    sources.each_with_object(Hash.new(0)) do |path, tally|
      source = path.read
      next unless source.include?(marker)

      walk(Prism.parse(source).value, source, marker, [], tally)
    end
  end

  def walk(node, source, marker, scope, tally)
    case node
    when Prism::ClassNode, Prism::ModuleNode
      scope += [node.constant_path.slice]
    when Prism::DefNode
      body = source.byteslice(node.location.start_offset, node.location.length)
      count = body.scan(marker).length
      # `def self.x` is reported as `.x`, so a singleton method carrying the CTE could never be
      # mistaken for the instance method of the same name.
      tally["#{scope.join('::')}#{node.receiver.nil? ? '#' : '.'}#{node.name}"] += count if count.positive?
      return
    end
    node.child_nodes.compact.each { |child| walk(child, source, marker, scope, tally) }
  end

  def definitions_containing(marker) = occurrences_in_definitions(marker).keys.sort

  # How many times `marker` occurs in the corpus at all. THE NON-VACUITY OF THE DERIVATION ITSELF:
  # a marker inside a constant, a class body or a lambda belongs to no `def`, so it would be dropped
  # silently and the derived set would come back short — which is a gate that fails open.
  def raw_occurrences(marker) = sources.sum { |path| path.read.scan(marker).length }

  it "attributes every occurrence of the marker to a method, so nothing is dropped silently" do
    attributed = occurrences_in_definitions(capability_cte).values.sum

    expect(raw_occurrences(capability_cte)).to be > 0,
                                               "no statement in `app/` or `lib/` carries a " \
                                               "`capability_authority` CTE, so this whole gate is " \
                                               "deriving from nothing and passing"
    expect(attributed).to eq(raw_occurrences(capability_cte)),
                          "#{raw_occurrences(capability_cte) - attributed} occurrence(s) of the CTE " \
                          "belong to no method definition, so the derived set is short and this " \
                          "gate fails open"
  end

  it "derives exactly the protected writes the registry enumerates" do
    derived = definitions_containing(capability_cte)

    expect(derived).to eq(ProtectedWrites.covered),
                       "the repository and `spec/support/protected_writes.rb` disagree about which " \
                       "writes are protected.\n" \
                       "  in the repository, not driven by the battery: #{(derived - ProtectedWrites.covered).inspect}\n" \
                       "  driven by the battery, not in the repository: #{(ProtectedWrites.covered - derived).inspect}\n" \
                       "A write in the first list inherits NONE of the battery's shared examples. " \
                       "Register it in `ProtectedWrites::WRITES` with its drivers rather than " \
                       "widening this expectation."
  end

  it "corroborates the derivation with the epoch limb, which every protected write also carries" do
    # TWO DERIVATIONS OF ONE SET. FU-48 gave the write two axes and both are CTEs of the same
    # statement, so a set derived from either must be the same set. This is not a second gate on the
    # registry; it is the check that the marker above still means what this file says it means.
    expect(definitions_containing(epoch_cte)).to eq(definitions_containing(capability_cte)),
                                                "the capability limb and the epoch limb are no " \
                                                "longer carried by the same statements, so one of " \
                                                "the two is not the protected-write set"
  end

  it "names each registered write at a class and method that exist" do
    # THE REGISTRY'S SIDE OF THE COMPARISON, CHECKED AGAINST RUBY RATHER THAN AGAINST TEXT. The
    # equality above compares two strings; if a registry entry named a class that does not exist,
    # the derivation would simply never produce it and the failure would read as a missing write
    # rather than as a typo.
    ProtectedWrites.covered.each do |identity|
      const_name, method = identity.split("#")
      klass = Object.const_get(const_name)

      expect(klass.instance_methods(false) + klass.private_instance_methods(false))
        .to include(method.to_sym), "#{identity} is registered, and `#{const_name}` has no such method"
    end
  end
end
