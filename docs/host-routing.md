# Host routing and certificate renewal

Public DNS, HTTPS certificates and hostname redirects belong to host provisioning.
Application releases run behind that configuration and must not replace it.

## Production routing

| Name | DNS target | Host behavior |
| --- | --- | --- |
| `crystal.microsalt.in` | A record: production VPS address | HTTPS proxy to the webapp on `127.0.0.1:3000` |
| `crystal-api.microsalt.in` | A record: production VPS address | HTTPS proxy to the backend on `127.0.0.1:8081` |
| `lab.microsalt.in` | CNAME: `crystal.microsalt.in` | HTTP/HTTPS 303 redirect to `https://crystal.microsalt.in/` |

The legacy name is an entry point to the canonical webapp, not a second application
origin. Keep the existing production API URL and Google Workspace SAML URLs. The
redirect does not forward old API calls or authentication request bodies to the new
API. Its fixed destination drops legacy paths and query strings; access logging is
disabled on the redirect virtual host.

Manage these DNS records independently of retired application infrastructure. Keep
the CNAME when moving to another VPS and update the canonical A records. Ensure the
new host is ready to serve all three hostnames before changing their addresses.

## Files outside application releases

The production redirect lives in:

```text
/etc/nginx/sites-available/crystalweb-production-legacy-lab
/etc/nginx/sites-enabled/crystalweb-production-legacy-lab
/etc/letsencrypt/live/lab.microsalt.in/
/etc/letsencrypt/renewal/lab.microsalt.in.conf
```

The enabled site is a symlink to the available site. Nginx configuration and its
parent directories must be owned by root and not writable by either deployment
account. Certificate private keys must remain private and outside repositories,
release bundles and container mounts. The backend and webapp deployment accounts
must have no sudo permission and no access to the privileged Docker socket.

`scripts/deploy-vps.sh` uploads releases under `/srv/crystalweb-webapp/releases`;
`scripts/activate-release.sh` changes only the account's rootless Compose service
and release links. Backend deployment uses its separate account and release root.
Neither deployment should install host examples or modify `/etc/nginx`,
`/etc/letsencrypt`, host services or DNS. Keep these boundaries when changing the
deployment scripts. Container restarts and release rollbacks do not remove the
host redirect.

## Provisioning or restoring the redirect

Use [the redirect example](../deploy/host-nginx-redirect.conf.example), replacing
`legacy.example.invalid` with `lab.microsalt.in` and `crystalweb.example.invalid`
with `crystal.microsalt.in`. It uses Nginx 1.25.1 or newer (`http2 on`). Install it
as a separate root-owned host site; do not overwrite the webapp or API sites.

Obtain a certificate covering the legacy hostname before routing public HTTPS
traffic to a new host. DNS validation can be used for that initial certificate so
the old endpoint continues to work during preparation. After installing the site:

```sh
sudo nginx -t
sudo systemctl reload nginx
```

Run the configuration check successfully before reloading. Use a graceful reload,
not a server restart. Check HTTPS with `curl --resolve` against the new VPS before
cutover; do not bypass certificate verification with `-k`.

Once public DNS resolves to the new VPS, configure unattended HTTP validation:

```sh
sudo certbot reconfigure --cert-name lab.microsalt.in \
  --webroot -w /var/lib/letsencrypt --preferred-challenges http \
  --non-interactive --run-deploy-hooks
sudo systemctl enable --now certbot.timer
```

`reconfigure` tests renewal before saving the settings. A certificate initially
issued with manual DNS validation must not remain configured for manual renewal.
Keep port 80 and the `/.well-known/acme-challenge/` webroot reachable. That path
must be served locally rather than redirected. The host deploy hook at
`/etc/letsencrypt/renewal-hooks/deploy/crystalweb-nginx` should run:

```sh
#!/bin/sh
nginx -t && systemctl reload nginx
```

Enable Nginx at boot, retain the enabled-site symlink, and include host configuration
and certificate recovery in VPS backups. Restore or reissue certificates securely;
do not put private keys in GitHub secrets for routine application deployment.

## Checks after host changes and application releases

```sh
curl --fail --silent --show-error https://crystal.microsalt.in/healthz
curl --fail --silent --show-error https://crystal-api.microsalt.in/health
curl --silent --show-error --head https://lab.microsalt.in/
curl --silent --show-error --head http://lab.microsalt.in/
```

Both legacy requests should return `303` with
`Location: https://crystal.microsalt.in/`; the two health endpoints should return
`200`. Existing deployment workflows check their own public health endpoint. Run
the additional legacy-host checks when changing DNS, host configuration, TLS,
ports, deployment accounts or deployment scripts. Periodically test renewal with
`sudo certbot renew --cert-name lab.microsalt.in --dry-run --run-deploy-hooks`.

These boundaries protect routing from normal application deployments. They do not
replace application health tests or prevent a broken application release from
serving errors behind the proxy.
