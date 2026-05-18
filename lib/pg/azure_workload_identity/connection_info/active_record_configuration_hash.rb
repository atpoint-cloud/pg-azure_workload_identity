# frozen_string_literal: true

module PG
  module AzureWorkloadIdentity
    module ConnectionInfo
      # Wraps an ActiveRecord database configuration hash (as produced from
      # `config/database.yml`) and exposes the connection parameters relevant
      # to Azure Workload Identity authentication, including the non-standard
      # `azure_workload_identity` flag.
      #
      # Accessor names follow this gem's connection-info contract (`user`,
      # `host`, `port`) rather than ActiveRecord's keys (note the
      # `:username` -> `#user` mapping).
      class ActiveRecordConfigurationHash
        # @param configuration_hash [Hash{Symbol => Object}] an ActiveRecord
        #   database configuration hash (symbol keys, as found under an
        #   environment in `database.yml`).
        def initialize(configuration_hash)
          @configuration_hash = configuration_hash
        end

        # @return [Object, nil] the value of the `azure_workload_identity` key,
        #   or `nil` if not set. Truthy values opt the connection into Azure
        #   Workload Identity authentication.
        def azure_workload_identity
          @configuration_hash[:azure_workload_identity]
        end

        # @return [String, nil] the database username (ActiveRecord's
        #   `:username` key).
        def user
          @configuration_hash[:username]
        end

        # @return [String, nil] the database host.
        def host
          @configuration_hash[:host]
        end

        # @return [Integer, String, nil] the database port.
        def port
          @configuration_hash[:port]
        end
      end
    end
  end
end
