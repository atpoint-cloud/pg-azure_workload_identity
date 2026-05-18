# frozen_string_literal: true

require "uri"

module PG
  module AzureWorkloadIdentity
    module ConnectionInfo
      # Parses and manipulates a PostgreSQL connection string in URI format
      # (e.g. `postgres://user@host:5432/db?param=value`).
      #
      # Connection parameters may be provided either as URI components (userinfo,
      # host, port) or as query-string parameters. Accessors prefer the URI
      # component and fall back to the query string when absent.
      #
      # The non-standard `azure_workload_identity` query parameter is recognized
      # and extracted on construction so the value can drive Azure Workload
      # Identity authentication while keeping the rest of the connection string
      # valid for libpq.
      class URI
        # Tests whether a connection string is in URI format.
        #
        # @param connection_string [String] the connection string to test.
        # @return [Boolean] `true` if the string matches the RFC 2396 absolute
        #   URI reference grammar, `false` otherwise.
        def self.matches?(connection_string)
          /\A#{::URI::RFC2396_PARSER.regexp[:ABS_URI_REF]}\z/.match?(connection_string)
        end

        # @return [String, nil] the value of the `azure_workload_identity` query
        #   parameter that was present in the original connection string, or
        #   `nil` if the parameter was not set.
        attr_reader :azure_workload_identity

        # Parses the given connection string and extracts the
        # `azure_workload_identity` query parameter (if any) so it is not
        # forwarded to libpq.
        #
        # @param connection_string [String] a PostgreSQL connection URI.
        def initialize(connection_string)
          @uri = ::URI.parse(connection_string)
          @query = @uri.query ? ::URI.decode_www_form(@uri.query).to_h : {} # : Hash[String, String]
          @azure_workload_identity = @query.delete("azure_workload_identity")
        end

        # @return [String, nil] the username from the URI userinfo, falling back
        #   to the `user` query parameter.
        def user
          @uri.user || @query["user"]
        end

        # @return [String, nil] the host from the URI authority, falling back to
        #   the `host` query parameter when the URI host is missing or empty.
        def host
          return @query["host"] if @uri.host.nil? || @uri.host.empty?

          @uri.host
        end

        # @return [Integer, String, nil] the port from the URI authority,
        #   falling back to the `port` query parameter.
        def port
          @uri.port || @query["port"]
        end

        # Sets the password, storing it as a `password` query parameter and
        # clearing any password embedded in the URI userinfo.
        #
        # @param value [String] the password to set.
        # @return [String] the value that was set.
        def password=(value)
          @uri.password = nil
          @query["password"] = value
        end

        # Serializes the connection info back to a URI string.
        #
        # The query string is rebuilt from the current parameters (so the
        # `azure_workload_identity` flag is omitted) and the scheme is normalized
        # to always include the `"//"` authority separator, ensuring the result
        # is a valid libpq connection URI.
        #
        # @return [String] the connection URI.
        def to_s
          @uri.query = ::URI.encode_www_form(@query)

          @uri.to_s.sub(%r{^#{@uri.scheme}:(?!//)}, "#{@uri.scheme}://")
        end
      end
    end
  end
end
