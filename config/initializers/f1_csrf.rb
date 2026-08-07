# frozen_string_literal: true

# Replace Rails' session-backed CSRF secret with F1's derived one.
#
# SECURITY_PERFORMANCE.md :80 forbids the second Rails session cookie the default
# strategy requires. Platform::DerivedCsrfStorage computes the base secret from the
# browser's own F1 cookie instead, so Rails' masking and constant-time verification are
# unchanged while nothing is stored.
Rails.application.config.to_prepare do
  ActionController::Base.csrf_token_storage_strategy = Platform::DerivedCsrfStorage.new
end
