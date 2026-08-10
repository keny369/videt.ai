# frozen_string_literal: true

# FU-12(a) and FU-12(d). Two schema statements the surrounding tables already
# make everywhere else, missing on exactly one table each.
#
# (a) `crawl_limit_decisions.decided_by_service_identity_id` IS `NOT NULL` AND
# REFERENCES NOTHING. `Platform::ServiceIdentity` states that "existence is
# guaranteed by the ledger foreign keys", and for this column it was not: the
# migration's own promise that "a limit decision has an author" was enforced by
# nothing, so a decision could name an identity that has never existed.
#
# AND FU-12(a)'s PREMISE IS WRONG IN THE DIRECTION THAT MATTERS. The record says
# this column is unbound "unlike every other Service-Identity reference in the
# schema". Derived from the catalogue on 2026-08-10 — every column named
# `%service_identity_id`, against `pg_constraint` — FIVE were unbound, not one:
#
#     crawl_limit_decisions.decided_by_service_identity_id        NOT NULL
#     entitlement_lease_heartbeats.worker_service_identity_id     NOT NULL
#     fingerprint_collision_decisions.detecting_service_identity_id  NOT NULL
#     entitlement_decisions.service_identity_id                   nullable
#     plan_assignments.assigned_by_service_identity_id            nullable
#
# Three of them NOT NULL, so each was a column whose declaration promises an author
# that no constraint required to exist. All five are bound here rather than one,
# because binding one and leaving four would leave the general rule — "a Service
# Identity attribution names a registered identity" — still unstatable, and it is
# the rule, not this column, that stops the next one being missed.
#
# (d) `crawl_sitemap_document_charges` CANNOT BE A PARENT. POSTGRESQL_SCHEMA.md :128
# requires a Project-owned table to carry `UNIQUE (organization_id, project_id, id)`,
# because that unique is what a tenant-carrying composite foreign key REFERENCES — a
# table without one cannot be the parent of such a link at all. This table carried
# only `UNIQUE (organization_id, id)`. There is no live defect, nothing references it
# today, which is exactly why it is cheap now and expensive once something does.
#
# AND AGAIN THE RECORD NAMED ONE TABLE WHERE THE CATALOGUE HAS THREE. Derived on
# 2026-08-10 over every `crawl%` table with a NOT NULL `project_id`, three lacked the
# key: `crawl_sitemap_document_charges`, `crawl_frontier_occurrences` and
# `crawl_sources`. All three are bound here for the same reason as (a) — the rule
# "a Project-owned table can be a parent" is only statable if it is true.
#
# `crawl_policies` IS DELIBERATELY NOT AMONG THEM. Its `project_id` is NULLABLE
# because a policy is scoped to an Organization OR a Project (:390's resolution takes
# the most restrictive of both), so it is not Project-OWNED in :128's sense and the
# derived rule excludes it on that ground rather than by name.
#
# NEITHER IS A BEHAVIOUR CHANGE AND BOTH ARE VALIDATED AGAINST EXISTING ROWS. Adding
# a foreign key takes a `SHARE ROW EXCLUSIVE` lock and verifies every existing row;
# adding a unique constraint builds an index over them. Both fail loudly here rather
# than admitting a row that violates them later.
class EnforceLimitDecisionAuthorAndChargeChildLink < ActiveRecord::Migration[8.1]
  # table => the column carrying the Service Identity attribution, and the constraint name, in the
  # `<table>_<role>_service_identity_fkey` shape the six already-bound columns use.
  UNBOUND_ATTRIBUTIONS = {
    "crawl_limit_decisions" => %w[decided_by_service_identity_id crawl_limit_decisions_service_identity_fkey],
    "entitlement_decisions" => %w[service_identity_id entitlement_decisions_service_identity_fkey],
    "entitlement_lease_heartbeats" => %w[worker_service_identity_id
                                         entitlement_lease_heartbeats_worker_service_identity_fkey],
    "fingerprint_collision_decisions" => %w[detecting_service_identity_id
                                            fingerprint_collision_decisions_service_identity_fkey],
    "plan_assignments" => %w[assigned_by_service_identity_id plan_assignments_assigned_by_service_identity_fkey]
  }.freeze

  # Every `crawl%` table with a NOT NULL `project_id` that lacked :128's three-column key.
  PROJECT_OWNED_WITHOUT_THE_KEY = %w[
    crawl_sitemap_document_charges
    crawl_frontier_occurrences
    crawl_sources
  ].freeze

  def up
    UNBOUND_ATTRIBUTIONS.each do |table, (column, constraint)|
      execute <<~SQL
        ALTER TABLE public.#{table}
          ADD CONSTRAINT #{constraint}
          FOREIGN KEY (#{column}) REFERENCES public.service_identities(id);
      SQL
    end

    PROJECT_OWNED_WITHOUT_THE_KEY.each do |table|
      execute <<~SQL
        ALTER TABLE public.#{table}
          ADD CONSTRAINT #{table}_org_project_id_unique
          UNIQUE (organization_id, project_id, id);
      SQL
    end
  end

  def down
    PROJECT_OWNED_WITHOUT_THE_KEY.each do |table|
      execute "ALTER TABLE public.#{table} DROP CONSTRAINT #{table}_org_project_id_unique;"
    end
    UNBOUND_ATTRIBUTIONS.each do |table, (_column, constraint)|
      execute "ALTER TABLE public.#{table} DROP CONSTRAINT #{constraint};"
    end
  end
end
