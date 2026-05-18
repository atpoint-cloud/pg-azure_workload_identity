# frozen_string_literal: true

require "json"

require_relative "error"

module PG
  module AzureWorkloadIdentity
    # Wraps a fetched OAuth access token together with the moment it was
    # generated, and answers whether it is still safely usable. Validity
    # is measured against the monotonic clock so the answer is not
    # affected by wall-clock jumps (NTP slews, VM clock corrections).
    class AuthToken
      # Seconds before the reported expiry at which the token is
      # considered stale, so callers proactively refresh before it
      # actually expires in flight.
      REFRESH_THRESHOLD_SECONDS = 60

      # @return [String] the bearer access token.
      attr_reader :access_token

      # Parses a token response from the Azure AD token endpoint and builds
      # an {AuthToken} instance.
      #
      # @param json [String] the raw JSON response body from the token   endpoint.
      # @return [AuthToken] the parsed token.
      # @raise [Error] when the JSON is invalid or lacks the expected fields.
      def self.from_json(json)
        JSON.parse(json).then do |data|
          new(
            access_token: data.fetch("access_token").to_s,
            expires_in: data.fetch("expires_in").to_i
          )
        end
      rescue JSON::ParserError => e
        raise Error, "Failed to parse token response from JSON: #{e.message}"
      rescue KeyError => e
        raise Error, "Token response is missing key #{e.key} in #{e.receiver}"
      end

      # @param access_token [String] the bearer access token returned by
      #   the token endpoint.
      # @param expires_in [Integer, String] seconds-until-expiry as
      #   reported by the token endpoint.
      # @param refresh_threshold [Integer] seconds before the reported
      #   expiry at which the token should be considered stale.
      def initialize(
        access_token:,
        expires_in:,
        refresh_threshold: REFRESH_THRESHOLD_SECONDS
      )
        @access_token = access_token
        @expiry = expires_in
        @generated_at = now
        @refresh_threshold = refresh_threshold
      end

      # @return [Boolean] `true` if the token is still valid with the
      #   refresh threshold applied.
      def valid?
        (now - @generated_at) < (@expiry - @refresh_threshold)
      end

      private

      def now
        Process.clock_gettime(Process::CLOCK_MONOTONIC)
      end
    end
  end
end
