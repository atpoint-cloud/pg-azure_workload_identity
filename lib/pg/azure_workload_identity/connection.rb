# frozen_string_literal: true

require_relative "auth_token_injector"
require_relative "connection_info"

module PG
  module AzureWorkloadIdentity
    # Patch prepended to `PG::Connection.singleton_class` that teaches libpq's
    # connection-parameter machinery about the non-standard
    # `azure_workload_identity` option and injects a freshly generated auth
    # token as the password when that option is set.
    #
    # The three overrides cooperate:
    # - {#conndefaults} adds `azure_workload_identity` to the list of known
    #   parameters so it is recognized rather than rejected as unknown.
    # - {#conninfo_parse} parses a connection string while preserving the
    #   value of `azure_workload_identity` in the returned parameter list
    #   (libpq would otherwise drop it).
    # - {#parse_connect_args} runs the final connection string through
    #   {AuthTokenInjector} so the password is replaced with a generated
    #   token whenever `azure_workload_identity` is set.
    module Connection
      # Lists libpq's connection parameter defaults, with the
      # `azure_workload_identity` option appended.
      #
      # @return [Array<Hash>] the connection parameter defaults.
      def conndefaults
        super + [conndefault_azure_workload_identity]
      end

      # Parses a connection string into the libpq parameter array, preserving
      # the `azure_workload_identity` option.
      #
      # The input is first round-tripped through {ConnectionInfo} so the
      # custom option is stripped before being handed to libpq's parser, and
      # then re-appended to the parsed result with its original value.
      #
      # @param connection_string [String] either a URI-style or key=value
      #   connection string.
      # @return [Array<Hash>] the parsed parameter array, including the
      #   `azure_workload_identity` entry when set.
      def conninfo_parse(connection_string)
        connection_info = ConnectionInfo.from_connection_string(connection_string)

        super(connection_info.to_s).tap do |result|
          if connection_info.azure_workload_identity
            result << conndefault_azure_workload_identity.merge(val: connection_info.azure_workload_identity)
          end
        end
      end

      # Normalizes connection arguments and injects an Azure Workload Identity
      # auth token as the password when `azure_workload_identity` is set.
      #
      # @param args [Array] the arguments passed to `PG::Connection.new` /
      #   `PG.connect` (forwarded to `super`).
      # @return [String] the connection string with the auth token injected
      #   if applicable, otherwise unchanged.
      def parse_connect_args(...)
        AuthTokenInjector.new.inject_into_connection_string(super)
      end

      private

      # Connection-parameter descriptor for the `azure_workload_identity`
      # option, matching the shape of entries returned by libpq's
      # `PQconndefaults`.
      #
      # @return [Hash] the descriptor hash.
      def conndefault_azure_workload_identity
        {
          keyword: "azure_workload_identity",
          envvar: nil,
          compiled: nil,
          val: nil,
          label: "Azure-Workload-Identity",
          dispchar: "",
          dispsize: 64
        }
      end
    end
  end
end
