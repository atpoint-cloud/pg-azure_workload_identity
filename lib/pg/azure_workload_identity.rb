# frozen_string_literal: true

require_relative "azure_workload_identity/auth_token_generator"
require_relative "azure_workload_identity/connection"
require_relative "azure_workload_identity/error"
require_relative "azure_workload_identity/version"

module PG
  # Namespace for the pg-azure_workload_identity gem, which provides Azure
  # Workload Identity authentication support for the pg gem and related tools.
  module AzureWorkloadIdentity
    # Returns the process-wide {AuthTokenGenerator}, lazily instantiated on
    # first access via {AuthTokenGenerator.default} so that env-loading
    # libraries (e.g. dotenv) have a chance to populate `ENV` before the
    # generator captures its configuration.
    #
    # @return [AuthTokenGenerator]
    def self.auth_token_generator
      @auth_token_generator ||= AuthTokenGenerator.default
    end

    # Overrides the process-wide {AuthTokenGenerator}. Mainly useful for
    # tests or for callers that want to provide a custom-configured
    # generator instead of the env-driven default.
    #
    # @param generator [#call] any callable that returns an access token.
    # @return [#call] the generator that was set.
    def self.auth_token_generator=(generator)
      @auth_token_generator = generator
    end

    PG::Connection.singleton_class.prepend Connection

    if defined?(ActiveRecord)
      require "active_record/connection_adapters/postgresql_adapter"

      require_relative "azure_workload_identity/active_record_postgresql_adapter"
      require_relative "azure_workload_identity/active_record_postgresql_database_tasks"

      ActiveRecord::ConnectionAdapters::PostgreSQLAdapter.singleton_class.prepend ActiveRecordPostgreSQLAdapter
      ActiveRecord::Tasks::PostgreSQLDatabaseTasks.prepend ActiveRecordPostgreSQLDatabaseTasks
    end
  end
end
