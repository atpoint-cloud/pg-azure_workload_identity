# frozen_string_literal: true

require_relative "auth_token_injector"

module PG
  module AzureWorkloadIdentity
    # Patch prepended to
    # `ActiveRecord::Tasks::PostgreSQLDatabaseTasks` that wires Azure
    # Workload Identity authentication into rake tasks that shell out to
    # `psql` (e.g. `db:structure:load`, `db:structure:dump`).
    #
    # ActiveRecord builds an environment hash for the `psql` subprocess via
    # the private `#psql_env` method; this override generates an auth token
    # and adds it to that hash as `PGPASSWORD` whenever the configuration
    # opts into workload identity, so the `psql` invocation authenticates
    # without prompting.
    module ActiveRecordPostgreSQLDatabaseTasks
      private

      # Builds the environment hash for the `psql` subprocess, injecting a
      # freshly generated Azure Workload Identity auth token as
      # `PGPASSWORD` when the configuration enables it.
      #
      # @return [Hash{String => String}] the environment hash to pass to
      #   the `psql` subprocess.
      def psql_env
        super.tap do |psql_env|
          AuthTokenInjector.new.inject_into_psql_env! configuration_hash, psql_env
        end
      end
    end
  end
end
