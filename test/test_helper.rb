# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
# Load ActiveRecord before the gem so the gem's load-time AR-integration
# path fires deterministically.
require "active_record"
require "pg/azure_workload_identity"

require "minitest/reporters"
Minitest::Reporters.use!

require "timecop"
Timecop.mock_process_clock = true
Timecop.safe_mode = true

require "webmock/minitest"
# Block external HTTP across all tests, but permit loopback so acceptance
# tests can talk to local fake servers (e.g. FakeAADEndpoint on 127.0.0.1).
WebMock.disable_net_connect!(allow_localhost: true)

require "minitest/autorun"
