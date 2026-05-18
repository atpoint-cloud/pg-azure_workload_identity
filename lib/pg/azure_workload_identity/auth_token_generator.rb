# frozen_string_literal: true

require "net/http"
require "openssl"
require "uri"

require_relative "auth_token"
require_relative "error"

module PG
  module AzureWorkloadIdentity
    # Exchanges a Kubernetes-projected federated identity token (as mounted
    # into pods by AKS Workload Identity) for an Azure AD access token via the
    # OAuth 2.0 client-credentials flow with a JWT bearer client assertion.
    #
    # Instances are callable via {#call}, which returns a cached access token
    # while it is still valid (with a refresh threshold applied) and otherwise
    # fetches a new one. Token fetches are guarded by a mutex so concurrent
    # callers share a single in-flight request.
    #
    # Configuration may be passed explicitly to {#initialize} or populated
    # from the standard Azure Workload Identity environment variables via
    # {.default}.
    class AuthTokenGenerator
      IDENTITY_ENDPOINT = "https://login.microsoftonline.com/%<tenant_id>s/oauth2/v2.0/token"
      SCOPE = "https://ossrdbms-aad.database.windows.net/.default"
      GRANT_TYPE = "client_credentials"
      CLIENT_ASSERTION_TYPE = "urn:ietf:params:oauth:client-assertion-type:jwt-bearer"

      # Builds an {AuthTokenGenerator} using the standard Azure Workload
      # Identity environment variables (`AZURE_TENANT_ID`,
      # `AZURE_CLIENT_ID`, `AZURE_FEDERATED_TOKEN_FILE`) and conventional
      # OAuth defaults.
      #
      # @return [AuthTokenGenerator]
      def self.default
        new(
          identity_endpoint: format(IDENTITY_ENDPOINT, tenant_id: ENV.fetch("AZURE_TENANT_ID")),
          client_id: ENV.fetch("AZURE_CLIENT_ID"),
          scope: SCOPE,
          grant_type: GRANT_TYPE,
          client_assertion_type: CLIENT_ASSERTION_TYPE,
          federated_token_file: ENV.fetch("AZURE_FEDERATED_TOKEN_FILE")
        )
      end

      # @return [String] the Azure AD token endpoint URL.
      attr_reader :identity_endpoint

      # @return [String] the AAD application/client id.
      attr_reader :client_id

      # @return [String] the requested OAuth scope.
      attr_reader :scope

      # @return [String] the OAuth grant type
      #   (typically `"client_credentials"`).
      attr_reader :grant_type

      # @return [String] the client-assertion type
      #   (typically `"urn:ietf:params:oauth:client-assertion-type:jwt-bearer"`).
      attr_reader :client_assertion_type

      # @return [String] absolute path to the file containing the
      #   Kubernetes-projected federated identity JWT.
      attr_reader :federated_token_file

      # @param identity_endpoint [String] the Azure AD token endpoint.
      # @param client_id [String] the AAD application id.
      # @param scope [String] the requested OAuth scope.
      # @param grant_type [String] the OAuth grant type.
      # @param client_assertion_type [String] the client-assertion type.
      # @param federated_token_file [String] path to the projected
      #   federated identity JWT.
      def initialize( # rubocop:disable Metrics/ParameterLists
        identity_endpoint:,
        client_id:,
        scope:,
        grant_type:,
        client_assertion_type:,
        federated_token_file:
      )
        @identity_endpoint = URI.parse(identity_endpoint)
        @client_id = client_id
        @scope = scope
        @grant_type = grant_type
        @client_assertion_type = client_assertion_type
        @federated_token_file = federated_token_file
        @mutex = Mutex.new
        @token = nil
      end

      # Returns a currently valid Azure AD access token, fetching a new one
      # from the identity endpoint when the cached token is missing or about
      # to expire. Thread-safe: concurrent callers share a single in-flight
      # fetch.
      #
      # @return [String] the bearer access token.
      # @raise [Error] when the federated token cannot be read, the HTTP
      #   request fails, the response is non-2xx, or the response body is
      #   not valid JSON / lacks the expected fields.
      def call
        @mutex.synchronize do
          @token = refresh unless @token&.valid?
          @token.access_token
        end
      end

      private

      def refresh
        response = request_token
        return AuthToken.from_json(response.body) if response.is_a?(Net::HTTPSuccess)

        raise Error, "Azure AD token endpoint responded with #{response.code} #{response.message}: #{response.body}"
      end

      def request_token
        Net::HTTP.start(
          @identity_endpoint.hostname.to_s,
          @identity_endpoint.port,
          use_ssl: @identity_endpoint.scheme == "https"
        ) do |http|
          http.request(build_request)
        end
      rescue Net::OpenTimeout, Net::ReadTimeout, Net::WriteTimeout,
             SocketError, IOError, SystemCallError, OpenSSL::SSL::SSLError => e
        raise Error, "Failed to reach Azure AD token endpoint: #{e.class}: #{e.message}"
      end

      def build_request
        Net::HTTP::Post.new(@identity_endpoint).tap do |request|
          request["Content-Type"] = "application/x-www-form-urlencoded"
          request.body = URI.encode_www_form(
            client_id: client_id,
            scope: scope,
            client_assertion_type: client_assertion_type,
            client_assertion: read_federated_token,
            grant_type: grant_type
          )
        end
      end

      def read_federated_token
        File.read(federated_token_file).strip
      rescue SystemCallError, IOError => e
        raise Error, "Failed to read federated token file #{federated_token_file.inspect}: #{e.class}: #{e.message}"
      end
    end
  end
end
