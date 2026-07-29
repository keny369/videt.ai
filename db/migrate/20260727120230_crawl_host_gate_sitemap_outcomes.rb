# frozen_string_literal: true

# S-07-006 review hardening (ADR-026 contract lens).
#
# :450 requires that "malformed XML, unsupported format, cross-host location, unsafe XML, parser
# limit, over-depth index, and over-count sitemap are RECORDED and skipped", and — critically —
# that "any sitemap depth/count/body/time/XML limit still produces `limit_reached`", which :442 turns
# into `coverage_status=partial` and `completion_reason=limit_reached` for the whole run.
#
# The tranche computed those reason codes and discarded them, so S-07-008 had nothing to read; and
# because the sitemap decision is write-once, the loss was IRREVERSIBLE — a run where one candidate
# hit `sitemap_xml_limit` would have completed `full` where the contract mandates `limit_reached`.
#
# `sitemap_skipped` records every skipped or failed candidate with its reason. `sitemap_limit_reasons`
# separates the subset that are LIMIT outcomes, because only those force `limit_reached`; the rest are
# telemetry when at least one candidate succeeded. Keeping them apart is what lets the consuming
# tranche apply :450's distinction without re-deriving it.
class CrawlHostGateSitemapOutcomes < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL
      ALTER TABLE crawl_host_gates
        ADD COLUMN sitemap_skipped jsonb NOT NULL DEFAULT '[]',
        ADD COLUMN sitemap_limit_reasons jsonb NOT NULL DEFAULT '[]';
    SQL
  end

  def down
    execute <<~SQL
      ALTER TABLE crawl_host_gates
        DROP COLUMN sitemap_limit_reasons,
        DROP COLUMN sitemap_skipped;
    SQL
  end
end
