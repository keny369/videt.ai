# frozen_string_literal: true

module App
  # `/app/projects/:project_id/measurements` — the narrowest real product path for staging an
  # owner-approval Measurement Set package (OD-010 § Required Owner Approval Package).
  #
  # THIS SCREEN CANNOT ACTIVATE ANYTHING, AND THAT IS ITS MOST IMPORTANT PROPERTY. The permission
  # baseline denies `measurement_set.activate` to EVERY human role — OrganizationAdmin included —
  # and reserves it for the owner-approval release service. So there is no activate button here,
  # no route to one, and no controller action that could be reached by guessing a URL. What this
  # screen does is stage a package as `proposed` and show the operator its exact SHA-256, which is
  # the value both owners must sign. Activation happens elsewhere, on signed bytes.
  #
  # The import itself runs under a SERVICE identity, as every intake path does. Reading the list
  # is ordinary tenant authority (`crawl.read` over the Project), because a proposed package is
  # tenant configuration a customer is entitled to see.
  class MeasurementsController < ApplicationController
    def index
      outcome = authorize!("crawl.read", resource: { type: "project", id: params[:project_id] }) do |actor, conn|
        store = IdentityAccess::Infrastructure::TenantReadStore.new(conn.raw_connection)
        project = store.project(organization_id: actor.organization_id, project_id: params[:project_id])
        next nil if project.nil?

        { project:, sets: read_sets(actor.organization_id, conn) }
      end
      return if outcome.nil?
      return render("shared/not_found", status: :not_found) if outcome.value.nil?

      @project = outcome.value[:project]
      @sets = outcome.value[:sets]
    end

    def create
      gate = authorize!("crawl.read", resource: { type: "project", id: params[:project_id] })
      return if gate.nil?

      result = import(gate.actor.organization_id, params[:project_id], params[:package].to_s)
      if result&.ok?
        redirect_to app_project_measurements_path(params[:project_id]), status: :see_other,
                    notice: "Package staged as proposed. It measures nothing until both owners sign " \
                            "#{hex(result.record['package_sha256'])}."
      else
        redirect_to app_project_measurements_path(params[:project_id]), status: :see_other,
                    alert: refusal(result)
      end
    end

    private

    def read_sets(organization_id, conn)
      store = IdentityAccess::Infrastructure::EvaluationInputStore.new(conn.raw_connection)
      store.measurement_sets_for(organization_id)
    end

    def import(organization_id, project_id, raw)
      package = JSON.parse(raw)
      catalog = Workflows::Wf007::CheckCatalog
      Platform::UnitOfWork.run do |conn|
        store = IdentityAccess::Infrastructure::EvaluationInputStore.new(conn.raw_connection)
        store.enter_org_context(org: organization_id, correlation_id: correlation_id)
        Workflows::Wf006::MeasurementIntake.import(
          store:, package:, organization_id:, project_id:, now: Time.now.utc,
          correlation_id:, catalog_version: catalog::CATALOG_VERSION,
          catalog_sha256: catalog.hex(catalog.catalog_digest)
        )
      end
    rescue JSON::ParserError
      nil
    end

    # The refusal reason is shown as itself, with the failing fields listed. An operator staging a
    # package needs to know WHICH of the register's required parts is missing; "invalid package"
    # would send them back to the register to guess.
    def refusal(result)
      return "That package is not valid JSON." if result.nil?

      detail = Array(result.detail).first(6).join(", ")
      base = Measurements::REASONS.fetch(result.reason, "That package was refused (#{result.reason}).")
      detail.empty? ? base : "#{base} #{detail}"
    end

    def hex(value) = value.to_s.sub(/\A\\x/, "")
  end

  module Measurements
    REASONS = {
      "measurement_package_invalid" =>
        "That package is missing or contradicts something OD-010 requires, so it authorizes nothing:",
      "measurement_set_version_reused" =>
        "A different package already exists at that set version. Corrected bytes need a new version."
    }.freeze
  end
end
