# frozen_string_literal: true

# Controller specs are decoupled from Rails (the controller must run even if the product app is
# broken). They load only the plain-Ruby autonomous_build library, via the lightweight spec_helper.
require "spec_helper"

$LOAD_PATH.unshift File.expand_path("../../automation/lib", __dir__)
require "autonomous_build"
