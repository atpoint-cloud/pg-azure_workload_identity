# frozen_string_literal: true

require "pg"

require_relative "connection_info/uri"
require_relative "connection_info/key_value_string"
require_relative "connection_info/active_record_configuration_hash"

module PG
  module AzureWorkloadIdentity
    # Factory methods that wrap a PostgreSQL connection description (a
    # connection string or an ActiveRecord configuration hash) in an object
    # exposing a uniform accessor contract (`user`, `host`, `port`,
    # `azure_workload_identity`, ...).
    #
    # Concrete return types are {URI}, {KeyValueString}, and
    # {ActiveRecordConfigurationHash}.
    module ConnectionInfo
      # Wraps a PostgreSQL connection string, dispatching to the URI or
      # key=value parser based on its format.
      #
      # @param connection_string [String] either a URI-style connection
      #   string (e.g. `"postgres://user@host/db"`) or a libpq key=value
      #   string (e.g. `"host=localhost user=admin"`).
      # @return [URI, KeyValueString] a wrapper around the parsed
      #   connection parameters.
      def self.from_connection_string(connection_string)
        if URI.matches?(connection_string)
          URI.new(connection_string)
        else
          KeyValueString.new(connection_string)
        end
      end

      # Wraps an ActiveRecord database configuration hash.
      #
      # @param configuration_hash [Hash{Symbol => Object}] an ActiveRecord
      #   database configuration hash (as produced from `database.yml`).
      # @return [ActiveRecordConfigurationHash] a wrapper around the
      #   configuration hash.
      def self.from_active_record_configuration_hash(configuration_hash)
        ActiveRecordConfigurationHash.new(configuration_hash)
      end
    end
  end
end
