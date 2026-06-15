# frozen_string_literal: true

require_relative '../caddy'
require_relative '../error'

module EasyCaddy
  module Commands
    # Removes and re-installs Caddy's local root CA, then restarts the service so it
    # reissues fresh leaf certs — clearing browser ERR_CERT_DATE_INVALID / authority errors.
    class Retrust
      # rubocop:disable Metrics/MethodLength
      def call
        raise Error, 'Caddy is not running. Start it with: brew services start caddy' unless Caddy.running?

        puts '  Removing local CA from trust store...'
        puts '    (you may be prompted for your password)'
        output, success = Caddy.untrust_with_output
        raise Error, "caddy untrust failed:\n#{output}" unless success

        puts '  Re-trusting local CA...'
        puts '    (you may be prompted for your password)'
        output, success = Caddy.trust_with_output
        raise Error, "caddy trust failed:\n#{output}" unless success

        # Re-trusting only re-installs the root CA; it does not refresh the short-lived
        # `*.localhost` leaf certs a browser may have cached as expired (ERR_CERT_DATE_INVALID).
        # Restarting forces Caddy to reissue them.
        puts '  Restarting Caddy to reissue certificates...'
        raise Error, 'caddy restart failed — try: brew services restart caddy' unless Caddy.restart_service

        puts '  Done. CA re-trusted and certificates reissued.'
        puts '  Fully reload your browser (or quit and reopen it) to clear the cached certificate.'
      end
      # rubocop:enable Metrics/MethodLength
    end
  end
end
