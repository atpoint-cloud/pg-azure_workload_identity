# frozen_string_literal: true

require_relative "auth_token_injector"

module PG
  module AzureWorkloadIdentity
    # Patch prepended to
    # `ActiveRecord::ConnectionAdapters::PostgreSQLAdapter.singleton_class`
    # that wires Azure Workload Identity authentication into the
    # `rails dbconsole` / `rails db` flow.
    #
    # The adapter's `dbconsole` class method is responsible for launching
    # `psql` against the configured database; without this patch, `psql`
    # would prompt for (or fail without) a password when the configuration
    # opts into workload identity. The override generates an auth token and
    # exposes it via `PGPASSWORD` before delegating to the original
    # implementation.
    module ActiveRecordPostgreSQLAdapter
      # Sets `PGPASSWORD` on the environment to a freshly generated Azure
      # Workload Identity auth token when the configuration enables it, then
      # delegates to the original `dbconsole` implementation.
      #
      # @param config [ActiveRecord::DatabaseConfigurations::DatabaseConfig]
      #   the configuration for the database `psql` is being launched
      #   against.
      # @return [void]
      def dbconsole(config, options = {})
        AuthTokenInjector.new.inject_into_psql_env! config.configuration_hash, ENV
        super
      end
    end
  end
end
