# frozen_string_literal: true

module Platform
  # Defence in depth: a connection handed to a unit of work must carry no leftover
  # proved context (TESTING_ARCHITECTURE.md § connection checkout assertions).
  class LeakedContextError < StandardError; end
end
