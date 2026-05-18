# PG::AzureWorkloadIdentity

[![Gem](https://img.shields.io/gem/v/pg-azure_workload_identity?style=flat-square)](https://rubygems.org/gems/pg-azure_workload_identity)
&ensp;
[![Docs](https://img.shields.io/badge/yard-docs-blue?style=flat-square)](https://www.rubydoc.info/gems/pg-azure_workload_identity)

`PG::AzureWorkloadIdentity` is a plugin for the [`pg` gem](https://rubygems.org/gems/pg) that adds support for [Microsoft Entra ID authentication](https://learn.microsoft.com/azure/postgresql/security/security-entra-concepts) when connecting to [Azure Database for PostgreSQL flexible server](https://learn.microsoft.com/azure/postgresql/flexible-server/overview), using [Microsoft Entra Workload Identity](https://learn.microsoft.com/entra/workload-id/workload-identity-federation) — typically as projected into pods by [AKS Workload Identity](https://learn.microsoft.com/azure/aks/workload-identity-overview).

Entra ID authentication lets your application connect to the database using short-lived access tokens instead of a fixed password. Combined with Workload Identity, your pods never carry a long-lived secret at all: the Kubernetes service account JWT is automatically exchanged for an Entra access token via [federated credentials](https://learn.microsoft.com/entra/workload-id/workload-identity-federation), and that token is used as the database password. No client secrets, no certificate rotation, no password storage.

## Installation

Install manually:

```console
$ gem install pg-azure_workload_identity
```

or with Bundler:

```console
$ bundle add pg-azure_workload_identity
```

## Usage

To use Workload Identity authentication for your database connections, you need to

1. enable Microsoft Entra authentication on your Azure Database for PostgreSQL flexible server,
2. provide your application with a Workload Identity, and
3. configure your application to use the gem's token generator.

### 1. Enable Microsoft Entra authentication on your database

Configure your Azure Database for PostgreSQL flexible server to allow Microsoft Entra authentication, either during server provisioning or on an existing server through the **Security → Authentication** pane. See [Use Microsoft Entra ID for authentication with Azure Database for PostgreSQL](https://learn.microsoft.com/azure/postgresql/security/security-entra-configure) for the step-by-step instructions.

Choose between **Microsoft Entra authentication only** (no password-based logins) and **PostgreSQL and Microsoft Entra authentication** (both modes available), then add at least one Microsoft Entra administrator. Only an Entra administrator can subsequently create additional Entra-mapped database roles.

Connect to the database as an Entra administrator and create a role for your application's identity. For a user-assigned managed identity, use its object (principal) ID:

```sql
select * from pgaadauth_create_principal_with_oid('my-app', '<managed-identity-object-id>', 'service', false, false);
```

Grant the role whatever privileges your application needs.

### 2. Provide your application with a Workload Identity

The recommended way to provide a credential to a pod in AKS is [Microsoft Entra Workload ID](https://learn.microsoft.com/azure/aks/workload-identity-overview). It works by federating a Kubernetes service account with an Entra ID identity, so a JWT projected into the pod can be exchanged for an Entra access token without ever sharing a long-lived secret.

The setup steps are (see [Deploy and configure an AKS cluster with Workload ID](https://learn.microsoft.com/azure/aks/workload-identity-deploy-cluster) for the full walkthrough):

1. Enable the OIDC issuer and Workload Identity add-on on your AKS cluster.
2. Create a user-assigned managed identity (or use an existing one).
3. Create a [federated identity credential](https://learn.microsoft.com/entra/workload-id/workload-identity-federation) on the managed identity, with the cluster's OIDC issuer as the `issuer`, `api://AzureADTokenExchange` as the `audience`, and `system:serviceaccount:<namespace>:<service-account-name>` as the `subject`.
4. Create a Kubernetes service account annotated with `azure.workload.identity/client-id: <managed-identity-client-id>` and use it for your application's pods.
5. Add `azure.workload.identity/use: "true"` to your pod template's labels.

Once that's in place, the Workload Identity mutating webhook automatically injects the following environment variables into your pod, which the gem uses to acquire access tokens:

| Variable | Provided by |
| --- | --- |
| `AZURE_TENANT_ID` | Workload Identity webhook |
| `AZURE_CLIENT_ID` | Workload Identity webhook (from the service-account annotation) |
| `AZURE_FEDERATED_TOKEN_FILE` | Workload Identity webhook (path to the projected service-account JWT) |

### 3. Configure your application to use the workload-identity token generator

Set the non-standard `azure_workload_identity` connection parameter to a truthy value (e.g. `true`). When the gem sees this parameter on a connection, it acquires an Entra access token using the environment variables above and injects it as the database password before handing the connection string to `libpq`.

You can set this parameter in

* the query string of a connection URI:

  ```
  postgresql://my-app@my-server.postgres.database.azure.com:5432/appdb?sslmode=require&azure_workload_identity=true
  ```

* a `key=value` pair in a connection string:

  ```
  user=my-app host=my-server.postgres.database.azure.com port=5432 dbname=appdb sslmode=require azure_workload_identity=true
  ```

* a `key: value` pair in a connection hash:

  ```ruby
  PG.connect(
    user: "my-app",
    host: "my-server.postgres.database.azure.com",
    port: 5432,
    dbname: "appdb",
    sslmode: "require",
    azure_workload_identity: "true"
  )
  ```

* `database.yml`, if you're using Rails:

  ```yaml
  production:
    adapter: postgresql
    username: my-app
    host: my-server.postgres.database.azure.com
    port: 5432
    database: appdb
    sslmode: require
    azure_workload_identity: true
  ```

The gem caches access tokens in memory for their reported lifetime (with a small refresh threshold), so concurrent and back-to-back connections share a single token exchange. Tokens are refreshed automatically on demand before they expire.

If the defaults don't match your environment (for example, you're using a sovereign cloud or a non-OSS-RDBMS scope), you can install a custom token generator at boot:

```ruby
PG::AzureWorkloadIdentity.auth_token_generator = PG::AzureWorkloadIdentity::AuthTokenGenerator.new(
  identity_endpoint: "https://login.microsoftonline.us/<tenant-id>/oauth2/v2.0/token",
  client_id: "<client-id>",
  scope: "https://ossrdbms-aad.database.usgovcloudapi.net/.default",
  grant_type: "client_credentials",
  client_assertion_type: "urn:ietf:params:oauth:client-assertion-type:jwt-bearer",
  federated_token_file: "/var/run/secrets/azure/tokens/azure-identity-token"
)
```

The object you assign just needs to respond to `#call` and return a string token, so you can swap in an entirely different implementation when needed.

### 4. Set `sslmode` to `verify-full` (recommended)

Although Azure Database for PostgreSQL flexible server requires TLS by default (`sslmode=require`), the strongest setting is `sslmode=verify-full` — this also verifies the server's certificate chain and hostname, preventing man-in-the-middle attacks. You'll need to point `sslrootcert` at the Azure-issued certificate bundle; see [TLS certificates for Azure Database for PostgreSQL flexible server](https://learn.microsoft.com/azure/postgresql/flexible-server/concepts-networking-ssl-tls#downloading-root-ca-certificates-and-updating-application-clients-in-certificate-pinning-scenarios) for the current chain and download instructions. Note that this might no be possible when using private endpoints with entries in private DNS zones.

## Development

After checking out the repo, run `bundle install` to install dependencies.
Then, run `bundle exec rake` to run the linter and unit tests.

The acceptance suite spins up a local PostgreSQL container via Docker Compose and exercises the full connection flow (with WebMock stubbing the Entra token endpoint) — run it with:

```console
$ bundle exec rake test:acceptance
```

To release a new version:

1. Update the version number in [version.rb](lib/pg/azure_workload_identity/version.rb), and run `bundle install` to update [Gemfile.lock](Gemfile.lock).
2. Update [CHANGELOG.md](CHANGELOG.md).
3. Submit the changes as a pull request.
4. Once merged, tag the release and push the tag to GitHub.

## Contributing

Bug reports and pull requests are welcome [on GitHub](https://github.com/atpoint-cloud/pg-azure_workload_identity).

## Credits

This gem is built on the design and structure of [`pg-aws_rds_iam`](https://github.com/haines/pg-aws_rds_iam) which provides the equivalent functionality for AWS RDS IAM authentication.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
