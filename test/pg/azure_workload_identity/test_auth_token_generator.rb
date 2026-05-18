# frozen_string_literal: true

require "test_helper"
require "tempfile"

module PG
  module AzureWorkloadIdentity
    class TestAuthTokenGenerator < Minitest::Test
      ENDPOINT = "https://login.microsoftonline.com/cc2fbc6b-4194-4bcf-9e12-b86ba0425176/oauth2/v2.0/token"
      CLIENT_ID = "a49df2cc-f0bd-461a-93fd-aacfaa038ca0"
      SCOPE = "https://ossrdbms-aad.database.windows.net/.default"

      FEDERATED_TOKEN = "eyJhbGciOiJSUzI1NiJ9.federated.signature"

      # Realistic-ish access token, trimmed for readability.
      AAD_ACCESS_TOKEN = "eyJ0eXAiOiJKV1QiLCJhbGciOiJSUzI1NiJ9.access.signature"

      def setup
        super
        @federated_token_file = Tempfile.new("federated_token")
        @federated_token_file.write(FEDERATED_TOKEN)
        @federated_token_file.close

        @generator = AuthTokenGenerator.new(
          identity_endpoint: ENDPOINT,
          client_id: CLIENT_ID,
          scope: SCOPE,
          grant_type: "client_credentials",
          client_assertion_type: "urn:ietf:params:oauth:client-assertion-type:jwt-bearer",
          federated_token_file: @federated_token_file.path
        )
      end

      def teardown
        @federated_token_file.unlink
        super
      end

      # --- happy path & request shape ---------------------------------------

      def test_returns_the_access_token_from_a_successful_response
        stub_token_endpoint

        assert_equal AAD_ACCESS_TOKEN, @generator.call
      end

      def test_posts_the_expected_form_payload_to_the_identity_endpoint
        stub_token_endpoint

        @generator.call

        assert_requested :post, ENDPOINT,
                         headers: { "Content-Type" => "application/x-www-form-urlencoded" },
                         body: {
                           "client_id" => CLIENT_ID,
                           "scope" => SCOPE,
                           "client_assertion_type" => "urn:ietf:params:oauth:client-assertion-type:jwt-bearer",
                           "client_assertion" => FEDERATED_TOKEN,
                           "grant_type" => "client_credentials"
                         }
      end

      def test_reads_the_federated_token_file_on_each_request_so_rotation_is_picked_up
        stub_token_endpoint(expires_in: 100)

        Timecop.freeze do
          @generator.call

          File.write(@federated_token_file.path, "rotated.token.value")

          Timecop.travel(Time.now + 80) do
            @generator.call
          end
        end

        assert_requested(:post, ENDPOINT, times: 1) do |req|
          URI.decode_www_form(req.body).to_h["client_assertion"] == "rotated.token.value"
        end
      end

      # --- caching ----------------------------------------------------------

      def test_caches_the_token_across_calls_while_still_valid
        stub = stub_token_endpoint(expires_in: 3600)

        Timecop.freeze do
          3.times { @generator.call }
        end

        assert_requested stub, times: 1
      end

      def test_refreshes_when_travelling_inside_the_refresh_threshold
        # expires_in=100, default threshold=60 → effective lifetime 40s.
        stub = stub_token_endpoint(expires_in: 100)

        Timecop.freeze do
          @generator.call

          Timecop.travel(Time.now + 50) do
            @generator.call
          end
        end

        assert_requested stub, times: 2
      end

      def test_refreshes_when_travelling_past_actual_expiry
        stub = stub_token_endpoint(expires_in: 100)

        Timecop.freeze do
          @generator.call

          Timecop.travel(Time.now + 200) do
            @generator.call
          end
        end

        assert_requested stub, times: 2
      end

      # --- error conditions -------------------------------------------------

      def test_raises_error_on_non_2xx_response_and_includes_status_in_message
        stub_request(:post, ENDPOINT).to_return(
          status: [401, "Unauthorized"],
          body: %({"error":"invalid_client","error_description":"AADSTS70002: ..."})
        )

        error = assert_raises(Error) { @generator.call }
        assert_match(/401/, error.message)
        assert_match(/invalid_client/, error.message)
      end

      def test_raises_error_when_response_body_is_html_instead_of_json
        stub_request(:post, ENDPOINT).to_return(
          status: 200,
          headers: { "Content-Type" => "text/html" },
          body: "<html><body>Service Unavailable</body></html>"
        )

        error = assert_raises(Error) { @generator.call }
        assert_match(/parse token response/, error.message)
      end

      def test_raises_error_on_network_timeout
        stub_request(:post, ENDPOINT).to_timeout

        error = assert_raises(Error) { @generator.call }
        assert_match(/Failed to reach Azure AD token endpoint/, error.message)
      end

      def test_raises_error_on_connection_refused
        stub_request(:post, ENDPOINT).to_raise(Errno::ECONNREFUSED)

        error = assert_raises(Error) { @generator.call }
        assert_match(/Failed to reach Azure AD token endpoint/, error.message)
      end

      def test_raises_error_on_ssl_handshake_failure
        stub_request(:post, ENDPOINT).to_raise(OpenSSL::SSL::SSLError.new("certificate verify failed"))

        error = assert_raises(Error) { @generator.call }
        assert_match(/Failed to reach Azure AD token endpoint/, error.message)
      end

      def test_raises_error_when_federated_token_file_is_missing
        @federated_token_file.unlink

        error = assert_raises(Error) { @generator.call }
        assert_match(/Failed to read federated token file/, error.message)
      end

      def test_failed_call_does_not_pollute_the_cache
        stub_request(:post, ENDPOINT).to_return(status: 500, body: "boom")
        assert_raises(Error) { @generator.call }

        # Recover with a fresh stub — the next call must retry the network.
        WebMock.reset!
        success_stub = stub_token_endpoint

        assert_equal AAD_ACCESS_TOKEN, @generator.call
        assert_requested success_stub, times: 1
      end

      private

      def stub_token_endpoint(access_token: AAD_ACCESS_TOKEN, expires_in: 86_399)
        stub_request(:post, ENDPOINT).to_return(
          status: 200,
          headers: { "Content-Type" => "application/json; charset=utf-8" },
          body: {
            token_type: "Bearer",
            expires_in: expires_in,
            ext_expires_in: expires_in,
            access_token: access_token
          }.to_json
        )
      end
    end
  end
end
