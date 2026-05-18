# frozen_string_literal: true

require "test_helper"

module PG
  module AzureWorkloadIdentity
    class TestAuthToken < Minitest::Test
      # Trimmed but representative response body from Azure AD's
      # /oauth2/v2.0/token endpoint.
      EXAMPLE_TOKEN_RESPONSE = <<~JSON
        {
          "token_type": "Bearer",
          "expires_in": 86399,
          "ext_expires_in": 86399,
          "access_token": "eyJ0eXAiOiJKV1QiLCJhbGciOiJSUzI1NiJ9.eyJhdWQiOiJodHRwczovL3N0b3JhZ2UuYXp1cmUuY29tIn0.signature"
        }
      JSON

      # --- construction & basic accessors -----------------------------------

      def test_access_token_is_exposed_via_reader
        token = AuthToken.new(access_token: "abc.def.ghi", expires_in: 3600)

        assert_equal "abc.def.ghi", token.access_token
      end

      # --- validity (security-critical) -------------------------------------
      #
      # The validity check must err on the side of refreshing too early, not
      # too late: a token used past its real expiry is rejected by Azure and
      # leaves the connection unauthenticated, but a token refreshed slightly
      # early is harmless.

      def test_is_valid_immediately_after_creation_when_lifetime_exceeds_threshold
        Timecop.freeze do
          token = AuthToken.new(access_token: "x", expires_in: 3600, refresh_threshold: 60)

          assert_predicate token, :valid?
        end
      end

      def test_remains_valid_well_within_the_effective_lifetime
        # expires_in=100, threshold=60 → effective lifetime = 40s; check at 30s.
        Timecop.freeze do
          token = AuthToken.new(access_token: "x", expires_in: 100, refresh_threshold: 60)

          Timecop.travel(Time.now + 30) do
            assert_predicate token, :valid?
          end
        end
      end

      def test_is_invalid_at_the_refresh_threshold_boundary
        # The check is strictly `<`, so at the exact boundary the token is
        # considered stale — we refresh slightly early rather than slightly
        # late. This is the safe direction.
        Timecop.freeze do
          token = AuthToken.new(access_token: "x", expires_in: 100, refresh_threshold: 60)

          Timecop.travel(Time.now + 40) do
            refute_predicate token, :valid?
          end
        end
      end

      def test_is_invalid_inside_the_refresh_threshold_before_actual_expiry
        # 50s elapsed of a 100s lifetime — still 50s of real life left, but
        # already inside the 60s refresh threshold, so we refresh.
        Timecop.freeze do
          token = AuthToken.new(access_token: "x", expires_in: 100, refresh_threshold: 60)

          Timecop.travel(Time.now + 50) do
            refute_predicate token, :valid?
          end
        end
      end

      def test_is_invalid_after_actual_expiry
        Timecop.freeze do
          token = AuthToken.new(access_token: "x", expires_in: 100, refresh_threshold: 60)

          Timecop.travel(Time.now + 200) do
            refute_predicate token, :valid?
          end
        end
      end

      def test_custom_refresh_threshold_changes_the_validity_window
        # With threshold 0, the token is valid right up to actual expiry.
        Timecop.freeze do
          token = AuthToken.new(access_token: "x", expires_in: 100, refresh_threshold: 0)

          Timecop.travel(Time.now + 99) do
            assert_predicate token, :valid?
          end
        end

        # With threshold 90, the token is stale after only 10s of real life.
        Timecop.freeze do
          token = AuthToken.new(access_token: "x", expires_in: 100, refresh_threshold: 90)

          Timecop.travel(Time.now + 15) do
            refute_predicate token, :valid?
          end
        end
      end

      # --- from_json --------------------------------------------------------

      def test_from_json_parses_a_realistic_azure_ad_response
        token = AuthToken.from_json(EXAMPLE_TOKEN_RESPONSE)

        assert_match(/^eyJ0eXAi/, token.access_token)
        assert_predicate token, :valid?
      end

      def test_from_json_raises_error_on_invalid_json
        error = assert_raises(Error) { AuthToken.from_json("not json{{{") }

        assert_match(/Failed to parse token response/, error.message)
      end

      def test_from_json_raises_error_when_required_fields_are_missing
        assert_raises(Error) { AuthToken.from_json(%({"token_type":"Bearer","expires_in":3600})) }
        assert_raises(Error) { AuthToken.from_json(%({"access_token":"x"})) }
      end
    end
  end
end
