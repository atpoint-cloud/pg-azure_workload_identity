# frozen_string_literal: true

require "test_helper"

module PG
  class TestAzureWorkloadIdentity < Minitest::Test
    def test_that_it_has_a_version_number
      refute_nil ::PG::AzureWorkloadIdentity::VERSION
    end
  end
end
