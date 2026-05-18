# frozen_string_literal: true

require "rake/clean"

require "bundler/gem_tasks"
require "minitest/test_task"

namespace :test do
  require "pg/version"
  require "active_record/version"

  Minitest::TestTask.create :acceptance do |t|
    t.test_globs = %w[test/acceptance/test_*.rb]
    t.test_prelude = <<~RUBY
      ENV["SIMPLECOV_COMMAND_NAME"] = "test:acceptance ruby:#{RUBY_VERSION} pg:#{PG::VERSION} activerecord:#{ActiveRecord.version}"
      require "simplecov"
    RUBY
  end

  Minitest::TestTask.create :unit do |t|
    t.test_globs = %w[test/pg/**/test_*.rb]
    t.test_prelude = <<~RUBY
      ENV["SIMPLECOV_COMMAND_NAME"] = "test:unit ruby:#{RUBY_VERSION} pg:#{PG::VERSION} activerecord:#{ActiveRecord.version}"
      require "simplecov"
    RUBY
  end

  desc "Run all tests"
  task all: %i[acceptance unit]
end

require "rubocop/rake_task"
RuboCop::RakeTask.new do |task|
  task.formatters = ENV["CI"] ? %w[github clang] : %w[fuubar]
end

require "yard"
CLEAN.include ".yardoc"
CLOBBER.include "doc"

desc "Generate documentation"
YARD::Rake::YardocTask.new

namespace :yard do
  desc "Run documentation server"
  task :server do
    exec "bin/yard", "server", "--reload"
  end
end

namespace :rbs do
  desc "Validate RBS signatures"
  task :validate do
    require "rbs"
    require "rbs/cli"
    RBS::CLI.new(stdout: $stdout, stderr: $stderr).run(%w[-I sig validate])
  end
end

require "steep/rake_task"
Steep::RakeTask.new

namespace :coverage do
  CLEAN.include "coverage"

  desc "Collate coverage reports"
  task :collate do
    require "simplecov"
    SimpleCov.collate Dir.glob("coverage-*/.resultset.json") do
      formatter SimpleCov::Formatter::HTMLFormatter
    end
  end
end

namespace :release do
  desc "Extract release notes from changelog"
  task :notes do
    require_relative "lib/pg/azure_workload_identity/version"

    version = PG::AzureWorkloadIdentity::VERSION

    mkdir_p "pkg", verbose: false

    lines = File.open "CHANGELOG.md", "r" do |changelog|
      changelog
        .each_line
        .lazy
        .drop_while { |line| !line.start_with?("## [#{version}] ") }
        .drop(1)
        .drop_while { |line| line == "\n" }
        .take_while { |line| !line.start_with?("## ") }
        .to_a
    end

    lines.pop while lines.last == "\n"

    File.open "pkg/release.md", "w" do |release_notes|
      lines.each do |line|
        release_notes << line
      end
    end

    File.write "pkg/version.txt", version
  end
end

task default: ["test:unit", :rubocop, "rbs:validate", "steep:check"]
