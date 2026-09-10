# Independent VPS deployment

This repository builds and deploys itself. The backend and webapp can share a VPS
or use separate hosts; they communicate through the configured public API origin.
Each repository owns a distinct Compose project, release directory and loopback port.

## GitHub configuration

Create an environment named **production** in this repository. Add these secrets
there (repository secrets with the same names also work):

| Secret | Value |
| --- | --- |
| `VPS_HOST` | Deployment host DNS name or IP address, without a URL scheme |
| `VPS_USER` | SSH deployment account with Docker permission |
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

Set the following as **repository Actions variables**, because the image build
runs before entering the production environment:

| Variable | Value / default |
| --- | --- |
| `API_PUBLIC_URL` | Real HTTPS API origin, e.g. `https://api.your-domain.com`, without trailing slash or path |
| `WEBAPP_PUBLIC_URL` | Real HTTPS webapp origin, e.g. `https://crystal.your-domain.com`, without trailing slash or path |
| `DEPLOY_ENABLED` | Set to `true` only after the VPS, DNS, TLS and secrets are ready; absent means build/publish only |
| `VPS_PORT` | SSH port; default `22` |
| `VPS_PATH` | Absolute service directory; default `/srv/crystalweb-webapp` |
| `SERVICE_PORT` | Loopback HTTP port; default `3000` |
| `DOCKER_PLATFORMS` | Image architecture; default `linux/amd64`; use `linux/arm64` for an ARM VPS or both separated by a comma |

Configure both public origins consistently in both repositories. Keep these
variables at repository scope; do not override them differently in the production
environment. The webapp embeds its API origin at build time. A placeholder image
can be built before configuration, but deployment rejects placeholder origins.

## Provision the VPS

Use a Linux VPS with Docker Engine, Docker Compose **2.24.4 or later**, bash,
Python 3, curl and `flock` (util-linux). Install host nginx and provision trusted
TLS certificates for the public domains. Grant the deployment user Docker access
and ownership of its service directory. For example, after creating the account:

```sh
sudo install -d -m 0700 -o DEPLOY_USER -g DEPLOY_GROUP /srv/crystalweb-webapp
```

Replace the uppercase account/group placeholders. On one VPS, provision both
`/srv/crystalweb-backend` and `/srv/crystalweb-webapp`; use different paths and
ports. Each workflow only operates on its own Compose project. Docker permission
is a privileged host capability, so use an account intended for deployment.

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

Pull requests run tests and a Docker build. Pushes to `main` and manual runs on
`main` test, build and publish an immutable image tagged with the commit. With
`DEPLOY_ENABLED=true`, the deploy job uses the image's content digest, transfers
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
