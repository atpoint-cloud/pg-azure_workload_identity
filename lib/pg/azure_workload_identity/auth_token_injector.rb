# frozen_string_literal: true

require "pg"
require_relative "connection_info"

module PG
  module AzureWorkloadIdentity
    # AuthTokenInjector is responsible for injecting auth tokens into connection
    # strings and PSQL environment variables when required.
    class AuthTokenInjector
      # Initializes a new AuthTokenInjector.
      #
      # The generator is resolved lazily — only on the code paths that
      # actually need a token — so that constructing an injector is cheap
      # and side-effect-free for connections that don't opt into workload
      # identity.
      #
      # @param auth_token_generator [#call, nil] A callable that generates
      #   an auth token. Defaults to the module-level generator at the time
      #   a token is first needed.
      def initialize(auth_token_generator: nil)
        @auth_token_generator = auth_token_generator
      end

      # Injects an auth token into the given connection string as password if required.
      #
      # @param connection_string [String] The original connection string.
      # @return [String] The modified connection string with the auth token injected if required.
      def inject_into_connection_string(connection_string)
        connection_info = ConnectionInfo.from_connection_string(connection_string)
        return connection_string unless generate_auth_token?(connection_info)

        connection_info.password = auth_token_generator.call
        connection_info.to_s
      end

      # Injects an auth token into the given PSQL environment hash if required.
      # This is used for the db:console rake task.
      #
      # @param configuration_hash [Hash] The ActiveRecord connection configuration hash from database.yml
      # @param psql_env [Hash] The environment hash to be passed to the PSQL process.
      def inject_into_psql_env!(configuration_hash, psql_env)
        connection_info = ConnectionInfo.from_active_record_configuration_hash(configuration_hash)
        return unless generate_auth_token?(connection_info)

        psql_env["PGPASSWORD"] = auth_token_generator.call
      end

      private

      # Resolves the auth token generator lazily, falling back to the
      # module-level default only when a token is actually needed.
      def auth_token_generator
        @auth_token_generator ||= AzureWorkloadIdentity.auth_token_generator
      end

      # Determines whether an auth token should be generated based on the connection information.
      #
      # @param connection_info [ConnectionInfo] The parsed connection information.
      # @return [Boolean] true if `azure_workload_identity` is set, false otherwise.
      def generate_auth_token?(connection_info)
        connection_info.azure_workload_identity
      end
    end
  end
end
