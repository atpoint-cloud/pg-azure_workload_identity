# frozen_string_literal: true

require_relative "lib/pg/azure_workload_identity/version"

Gem::Specification.new do |spec|
  spec.name = "pg-azure_workload_identity"
  spec.version = PG::AzureWorkloadIdentity::VERSION
  spec.authors = ["Simon Schmid"]
  spec.email = ["simon@at-point.ch"]

  spec.summary = "Workload identity authentication for Azure PostgreSQL flexible server/"
  spec.homepage = "https://github.com/atpoint-cloud/pg-azure_workload_identity"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.3"
  spec.metadata["bug_tracker_uri"] = "#{spec.homepage}/issues"
  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "#{spec.homepage}/blob/main"
  spec.metadata["changelog_uri"] = "#{spec.homepage}/blob/main/CHANGELOG.md"

  # Uncomment the line below to require MFA for gem pushes.
  # This helps protect your gem from supply chain attacks by ensuring
  # no one can publish a new version without multi-factor authentication.
  # See: https://guides.rubygems.org/mfa-requirement-opt-in/
  spec.metadata["rubygems_mfa_required"] = "true"

  # Specify which files should be added to the gem when it is released.
  spec.files = Dir[
    "lib/**/*.rb",
    ".yardopts",
    "CHANGELOG.md",
    "LICENSE.txt",
    "README.md",
    "pg-azure_workload_identity.gemspec"
  ]

  spec.require_paths = ["lib"]

  # Uncomment to register a new dependency of your gem
  spec.add_dependency "pg", "~> 1.5"

  # For more information and examples about making a new gem, check out our
  # guide at: https://guides.rubygems.org/make-your-own-gem/
end
