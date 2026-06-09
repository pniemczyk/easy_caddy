# frozen_string_literal: true

module EasyCaddy
  # Raised for expected, user-actionable failures: invalid Caddy config,
  # domain/port conflicts, unwritable log files. The CLI prints the message
  # and exits non-zero WITHOUT a Ruby backtrace — these are not bugs, they're
  # things the user is expected to fix and re-run.
  class Error < StandardError; end
end
