# frozen_string_literal: true

require "pg"

module PG
  module AzureWorkloadIdentity
    module AcceptanceSupport
      # Ensures a postgres instance is reachable for the acceptance suite by
      # bringing up the `docker-compose.test.yml` stack on demand and tearing
      # it down at the end of the run.
      #
      # If postgres is already reachable on the configured host/port, we
      # assume it's a developer-managed instance and leave it alone — we
      # neither start nor stop anything. This keeps `rake test:acceptance`
      # from clobbering a long-running dev database.
      module DockerCompose
        COMPOSE_FILE = File.expand_path("../../../docker-compose.test.yml", __dir__)

        class << self
          # Bring up the compose stack if postgres isn't already reachable.
          # Returns true on success, false if Docker isn't available (caller
          # can use that to decide whether to skip tests).
          def ensure_running!(host:, port:, user:, password:, dbname:)
            @conn_params = { host: host, port: port, user: user, password: password, dbname: dbname }
            return true if reachable?

            return false unless docker_available?

            puts "[acceptance] postgres not reachable, starting #{COMPOSE_FILE}..."
            system("docker", "compose", "-f", COMPOSE_FILE, "up", "-d", "--wait", exception: true)
            @started_by_us = true
            true
          end

          # Tears down the compose stack only if we started it.
          def stop_if_started
            return unless @started_by_us

            puts "[acceptance] stopping #{COMPOSE_FILE}..."
            system("docker", "compose", "-f", COMPOSE_FILE, "down")
          end

          def reachable?
            PG.connect(**@conn_params, connect_timeout: 1).close
            true
          rescue PG::ConnectionBad
            false
          end

          def docker_available?
            system("docker", "version", out: File::NULL, err: File::NULL)
          end
        end
      end
    end
  end
end
