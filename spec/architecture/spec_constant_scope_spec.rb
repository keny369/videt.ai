# frozen_string_literal: true

require "rails_helper"
require "prism"

# FU-42. A constant assigned inside an `RSpec.describe ... do` block is NOT scoped to the
# example group. A block does not open a lexical scope for constants, so the assignment
# lands at top level — on `Object` — and is visible to, and overwritable by, every other
# file in the run.
#
# REPRODUCED, NOT SUPPOSED. `spec/architecture/scheduled_action_catalogue_spec.rb` defines
# `DOC = .../BACKGROUND_PROCESSING.md` this way. The first draft of
# `permission_baseline_transcription_spec.rb` defined its own `DOC = .../WORKFLOW_SPECIFICATIONS.md`
# and, in the suite, read BACKGROUND_PROCESSING.md instead: green alone, wrong together, and
# which one wins decided purely by RSpec's load order.
#
# THE DANGEROUS PART IS THAT IT PASSES. That spec happened to assert its own parse before
# using it. A file without such a guard parses zero rows from the wrong document and every
# derived example passes VACUOUSLY — the same defect class as R3-8/R3-9, arriving through a
# new door. The original finding avoided the collision in one file and left the landmine
# armed; this is the check it asked for instead.
#
# Scoped to genuine top-level assignments: a constant inside `class`/`module` is properly
# namespaced and is not a collision, so the AST is walked rather than the text grepped.
RSpec.describe "Spec-level constant scope", type: :model do
  # Every constant a spec file writes at top level, as {name => [relative paths]}.
  def self.top_level_constant_writes
    @top_level_constant_writes ||= Rails.root.glob("spec/**/*.rb").each_with_object({}) do |file, acc|
      relative = file.relative_path_from(Rails.root).to_s
      collect_writes(Prism.parse(file.read).value, false) do |name|
        (acc[name] ||= []) << relative
      end
    end
  end

  # A `class` or `module` body opens a real constant scope; a block (`do ... end`) does not.
  # So descending through a ClassNode/ModuleNode means everything below it is namespaced,
  # and everything else keeps the enclosing scope — which at the file root is `Object`.
  def self.collect_writes(node, namespaced, &block)
    return unless node.is_a?(Prism::Node)

    inside = namespaced || node.is_a?(Prism::ClassNode) || node.is_a?(Prism::ModuleNode)
    yield node.name.to_s if !inside && node.is_a?(Prism::ConstantWriteNode)
    node.compact_child_nodes.each { |child| collect_writes(child, inside, &block) }
  end

  it "parses the spec tree at all" do
    # Everything below is only as strong as the walk that feeds it. If Prism ever returns
    # nothing for this tree, the collision check would pass by comparing nothing to nothing.
    expect(self.class.top_level_constant_writes).not_to be_empty
    expect(Rails.root.glob("spec/**/*.rb").length).to be > 100
  end

  it "never lets two spec files write the same top-level constant" do
    collisions = self.class.top_level_constant_writes
                     .select { |_name, files| files.uniq.length > 1 }
                     .transform_values { |files| files.uniq.sort }

    expect(collisions).to be_empty,
                          "these constants are written at top level by more than one spec file, so " \
                          "which value wins is decided by RSpec's load order and the loser reads the " \
                          "winner's data silently:\n" +
                          collisions.map { |name, files| "  #{name}: #{files.join(', ')}" }.join("\n") +
                          "\nUse a method or `let` instead — a constant inside a describe block is " \
                          "not scoped to the example group."
  end
end
