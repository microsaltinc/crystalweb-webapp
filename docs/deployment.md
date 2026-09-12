# Independent VPS deployment

This repository builds and deploys itself. The backend and webapp can share a VPS
or use separate hosts; they communicate through the configured public API origin.
Each repository owns a distinct Compose project, release directory and loopback port.

## GitHub configuration

Use separate **development** and **production** GitHub environments. The current
VPS belongs to development. Add these secrets to the environment being deployed:

| Secret | Value |
| --- | --- |
| `VPS_HOST` | Deployment host DNS name or IP address, without a URL scheme |
| `VPS_USER` | Dedicated rootless Docker account; `cicd-webapp` on the current VPS |
| `VPS_SSH_KEY` | Complete dedicated SSH private key, usable without a passphrase; install its public key in that account's authorized_keys |
| `VPS_KNOWN_HOSTS` | Verified SSH known_hosts line(s) for this host; use `[host]:port` for a nondefault SSH port |

Verify the host key fingerprint through the VPS console or another trusted
channel before storing known_hosts. The workflow enforces strict host checking.
Do not paste credential values into issues, source files or workflow YAML.

The webapp needs no database or signing secrets.

The workflow publishes to GHCR and pulls its own image using GitHub's automatically
provided `GITHUB_TOKEN`; no registry PAT or password secret is needed. The package
must retain this repository's Actions access. See
[GitHub's container registry authentication documentation](https://docs.github.com/en/packages/working-with-a-github-packages-registry/working-with-the-container-registry).

Set the following as **environment variables** in the matching GitHub environment.
The configuration job supplies its public settings to the image build:

| Variable | Value / default |
| --- | --- |
| `API_PUBLIC_URL` | Real HTTPS API origin, e.g. `https://api.your-domain.com`, without trailing slash or path |
| `WEBAPP_PUBLIC_URL` | Real HTTPS webapp origin, e.g. `https://crystal.your-domain.com`, without trailing slash or path |
| `DEPLOY_ENABLED` | Set to `true` only after the VPS, DNS, TLS and secrets are ready; absent means build/publish only |
| `VPS_PORT` | SSH port; default `22` |
| `VPS_PATH` | Absolute service directory; default `/srv/crystalweb-webapp` |
| `SERVICE_PORT` | Loopback HTTP port; default `3000` |
| `DOCKER_PLATFORMS` | Image architecture; default `linux/amd64`; use `linux/arm64` for an ARM VPS or both separated by a comma |

Configure both public origins consistently in the same environment of both
repositories. Development and production should have different origins. The
webapp embeds the selected environment's API origin at build time. A placeholder
image can be built before configuration, but deployment rejects placeholder origins.

## Provision the VPS

Use a Linux VPS with rootless Docker Engine, Docker Compose **2.24.4 or later**,
bash, Python 3, curl and `flock` (util-linux). Follow
[rootless account provisioning](rootless-deployment.md). An administrator installs
host nginx and provisions trusted TLS certificates and the release directory.
Use a dedicated frontend account and SSH key, separate from the backend, with no
sudo or privileged Docker-group membership. After creating the account:

```sh
sudo install -d -m 0700 -o DEPLOY_USER -g DEPLOY_GROUP /srv/crystalweb-webapp
```

Replace the uppercase account/group placeholders. On one VPS, provision both
`/srv/crystalweb-backend` and `/srv/crystalweb-webapp`; use different paths and
ports, separate owners and separate rootless daemons. Each workflow only operates
on its account's containers. Production activation rejects rootful Docker.

Install the example `deploy/host-nginx.conf.example` in the host nginx http
configuration, replacing domains and certificate paths. Match its proxy port to
`SERVICE_PORT`, validate with `nginx -t`, and reload nginx. Expose HTTPS and your
SSH port; keep the service ports on loopback. DNS must resolve to the corresponding
VPS before running the workflow's public health check.

The webapp's static nginx server listens on `127.0.0.1:3000` by default.
It has no database, uploaded data, runtime credentials or API reverse proxy.
Its health endpoint is `/healthz`. Deployment verifies the image's embedded API
origin matches `API_PUBLIC_URL` before replacing the `crystalweb-webapp` project.
The backend containers and database are never restarted by this workflow.

## Backend storage and database

The backend connects to provider-managed PostgreSQL 16. Microscope files and
reports live on a dedicated mounted filesystem on the API VPS. The webapp needs
no database credentials or image-volume access. See the backend repository's
[storage architecture](https://github.com/microsaltinc/crystalweb-backend/blob/main/docs/storage.md).

## Authentication

Configure the Google Workspace SAML application against the API domain:

- Metadata/entity definition: `API_PUBLIC_URL/api/v1/auth/saml/metadata`.
- Assertion consumer service: `API_PUBLIC_URL/api/v1/auth/saml/acs`.
- Browser callback: `WEBAPP_PUBLIC_URL/auth-callback`.

The backend supplies the callback and allowed browser origin from the variables
above. Its `saml/settings.json` carries the Workspace IdP metadata and public
certificate. Update it if the Workspace SAML application or certificate changes;
it is not an OAuth client secret. Production always disables local bootstrap auth.
Verify a real Workspace login after the first deployment.

## Release behavior

Pull requests run tests and a Docker build. Main runs target development; manually
created release tags target production. With `DEPLOY_ENABLED=true` in the selected
environment, the deploy job uses the image's content digest, transfers
a minimal release bundle through SSH and pulls with an ephemeral registry token.
The token is not persisted on the VPS. Reruns create distinct release directories.

The script serializes deployments for this service, checks local readiness and
then the workflow checks the public HTTPS endpoint. A successful activation
updates `current` and records `previous-release`. A failed public DNS/TLS check
can occur after activation; inspect the workflow and service health before retrying.
Old releases are retained; remove them manually according to your retention policy.
Do not remove backend data or secrets directories when pruning releases.

To roll back the webapp, revert the relevant source change and run the workflow,
or select a retained release's immutable image and reconcile that release's
production Compose configuration. Verify its embedded API origin and compatibility
with the currently deployed API. No database rollback is involved.

To move a service to a different VPS, provision its new host, update that
repository's SSH settings, and move its DNS. The backend uses a dedicated provider-managed PostgreSQL 16 service and a mounted
image volume. Moving its VPS requires remounting/migrating images and authorizing
the new VPS on the managed database network. Preserve coordinated recovery points. If the API origin changes, rebuild the webapp
with the new `API_PUBLIC_URL`, and update backend CORS/SAML settings if the webapp
origin changes. No cross-repository checkout or Docker network changes are needed.

## Development and production releases

The current VPS is the **development** host. Production will use a separate VPS,
its own SSH keys/accounts, managed database, image storage and public origins.
Keep deployment secrets and variables in the matching GitHub environment. Do not
put environment-specific database, SSH or URL values at repository scope, where
they could become fallback values for the other environment.

| Trigger in this repository | Target | Behavior |
| --- | --- | --- |
| Pull request | None | Tests and image build; no deployment environment or registry publication |
| Push to `main` | `development` | Tests, builds and publishes; deploys when development has `DEPLOY_ENABLED=true` |
| Manually create/push `vMAJOR.MINOR.PATCH` | `production` | Tests, verifies the tagged commit is on `origin/main`, builds and publishes; deploys when production has `DEPLOY_ENABLED=true` |
| Manual workflow run on `main` or a release tag | Determined by the ref | Same routing and checks; the environment cannot be chosen independently of the ref |

Release tags use three numeric components, for example `v1.0.0`. Prerelease tags,
malformed version tags, and tags on commits not merged into `main` cannot deploy.
Production releases are serialized across tags. Each repository releases
independently; tagging the backend does not release the webapp, or vice versa.

To release a tested `main` commit, run in the repository being released, choosing
an unused version after verifying the intended commit and its CI results:

```sh
git fetch origin
git tag -a v1.0.0 origin/main -m "Release v1.0.0"
git push origin refs/tags/v1.0.0
```

Creating that tag is the manual production release action. For a retry, rerun its
workflow in Actions or use `gh workflow run deploy.yml --ref v1.0.0`. To retry
development, use `gh workflow run deploy.yml --ref main`. Do not move existing
release tags to different commits.

Restrict the development environment to the `main` branch and production to `v*`
tags in Settings > Environments > Deployment branches and tags. These restrictions
are configured in both repositories. The workflow additionally validates the full
version format and commit ancestry. Leave each environment's `DEPLOY_ENABLED=false`
until its VPS, database, image mount, DNS/TLS, SAML and credentials are ready.

The configuration job enters the selected GitHub environment before reading its
variables, including `DEPLOY_ENABLED`. It exports only nonsecret build settings.
The webapp build receives that environment's API origin; deployment later checks
the embedded origin against its runtime configuration. Image tags include the
environment (`development-sha-...` or `production-sha-...`); activation pins the
image digest. Deployment credentials are supplied only to the deploy job.

Hosted development uses the hardened production runtime and Compose configuration:
`APP_ENV=production`, backend `ENVIRONMENT=production`, verified database TLS,
HTTPS, and `LOCAL_AUTH_ENABLED=false`. `DEPLOYMENT_ENVIRONMENT=development` records
the deployment target in the private release configuration. The runtime setting
retains the security checks required for an Internet-accessible VPS; local
bootstrap authentication is available only on an explicitly local installation.
