# frozen_string_literal: true

require "rails_helper"

# The ratified action-kind catalogue is a closed vocabulary, and drift from it is
# a contract violation rather than a style question. schemas/POSTGRESQL_SCHEMA.md
# :222 requires exactly this test: "An architecture test extracts the canonical
# literals and all 53 action-to-work rows and fails on any missing, extra or
# differently mapped value; it also fails if `credential_rotation_retry` appears."
#
# The three sources compared are the document
# (specification/volume-ii/BACKGROUND_PROCESSING.md), the Ruby catalogue that the
# dispatch registry validates against, and the database CHECK vocabulary that
# makes an unratified kind unstorable.
RSpec.describe "ScheduledAction action-kind catalogue", type: :model do
  DOC = Rails.root.join("specification/volume-ii/BACKGROUND_PROCESSING.md")

  # Rows between the named heading and the next heading, as [action_kind, value]
  # taken from the first backticked machine token in each of the first two cells.
  def table_rows(heading)
    body = DOC.read.split(/^#+ /).find { |section| section.start_with?(heading) }
    raise "section #{heading.inspect} not found" if body.nil?

    body.lines.filter_map do |line|
      next unless line.start_with?("| `")

      cells = line.split("|").map(&:strip)[1..]
      next if cells.nil? || cells.size < 2

      [machine_token(cells[0]), machine_token(cells[1])]
    end
  end

  # A lowercase machine literal (action kind, queue, work type). A cell with no
  # such literal — the `evaluation_stage_advance` registry row, which defers to
  # the Evaluation stage registry — yields nil, which the catalogue mirrors.
  def machine_token(cell) = cell[/`([a-z][a-z_0-9]*)`/, 1]

  # The Application operation of a generic-dispatch row. Two rows carry ratified
  # prose around the operation (`role_assignment_expire`'s OD-026 block branch and
  # `reassessment_slot`'s OD-025 decision branch), so an explicit "invokes X"
  # naming wins over the first CamelCase token in the cell.
  def operation_token(cell)
    cell[/invokes `([A-Z][A-Za-z]+)`/, 1] || cell[/`([A-Z][A-Za-z]+)`/, 1]
  end

  let(:kind_rows) { table_rows("Action-kind catalogue") }
  let(:registry_rows) { table_rows("Action-to-work dispatch registry") }
  let(:generic_rows) do
    # The generic `scheduled_action_dispatch` mapping table lives inside the
    # Job Catalogue section, after its introducing sentence.
    section = DOC.read.split("The generic `scheduled_action_dispatch` mapping is exhaustive:").last
    section.lines
           .drop_while { |l| !l.start_with?("|") }
           .take_while { |l| l.start_with?("|") }
           .filter_map do |line|
      cells = line.split("|").map(&:strip)[1..]
      next if cells.nil? || cells.size < 2 || !line.start_with?("| `")

      [machine_token(cells[0]), operation_token(cells[1])]
    end
  end

  def database_kind_literals
    clause = ActiveRecord::Base.connection.select_value(<<~SQL)
      SELECT pg_get_constraintdef(c.oid)
      FROM pg_constraint c JOIN pg_class t ON t.oid = c.conrelid
      WHERE t.relname = 'scheduled_actions' AND c.contype = 'c'
        AND pg_get_constraintdef(c.oid) LIKE '%action_kind%'
    SQL
    clause.scan(/'([a-z_]+)'::text/).flatten
  end

  it "transcribes exactly the 53 ratified action kinds, in document order" do
    expect(kind_rows.size).to eq(53)
    expect(Platform::ScheduledActions::Catalogue.kinds).to eq(kind_rows.map(&:first))
  end

  it "maps every action kind to the document's queue" do
    expect(kind_rows.to_h { |kind, queue| [kind, queue] })
      .to eq(Platform::ScheduledActions::Catalogue::KINDS.transform_values(&:first))
  end

  it "maps every action kind to the dispatch registry's work type" do
    expect(registry_rows.size).to eq(53)
    expect(registry_rows.map(&:first)).to eq(kind_rows.map(&:first))
    expect(registry_rows.to_h { |kind, work_type| [kind, work_type] })
      .to eq(Platform::ScheduledActions::Catalogue::KINDS.transform_values(&:last))
  end

  it "transcribes the exhaustive generic scheduled_action_dispatch operation table" do
    expect(generic_rows.size).to eq(17)
    expect(generic_rows.to_h).to eq(Platform::ScheduledActions::Catalogue::GENERIC_OPERATIONS)
  end

  it "never admits credential_rotation_retry, in any source" do
    expect(kind_rows.map(&:first)).not_to include("credential_rotation_retry")
    expect(Platform::ScheduledActions::Catalogue.kinds).not_to include("credential_rotation_retry")
    expect(database_kind_literals).not_to include("credential_rotation_retry")
  end

  it "constrains the database action_kind vocabulary to the same closed set" do
    expect(database_kind_literals.sort).to eq(kind_rows.map(&:first).sort)
  end

  it "routes every generic-dispatch kind to scheduled_action_dispatch and no specialized kind into that table" do
    generic = Platform::ScheduledActions::Catalogue::GENERIC_OPERATIONS.keys
    generic.each do |kind|
      expect(Platform::ScheduledActions::Catalogue.work_type_for(kind)).to eq("scheduled_action_dispatch")
    end
    specialized = Platform::ScheduledActions::Catalogue::KINDS
                  .reject { |_, (_, work_type)| work_type == "scheduled_action_dispatch" }.keys
    expect(specialized & generic).to be_empty
  end
end
