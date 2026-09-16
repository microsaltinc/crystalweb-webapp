# crystalweb-webapp

Independent Flutter Web application served by nginx. This repository contains
all frontend code, assets, tests and deployment configuration. Its Docker image
serves static files and needs no backend checkout, shared Docker network or
backend container to start. The browser calls the configured API over HTTPS.

The API lives in
[crystalweb-backend](https://github.com/microsaltinc/crystalweb-backend).
Google Workspace SAML remains the production login mechanism.

## Run locally

Install Docker Engine/Desktop with Compose v2 and Python 3:

```sh
git clone git@github.com:microsaltinc/crystalweb-webapp.git
cd crystalweb-webapp
./scripts/bootstrap-local.sh
```

Open http://localhost:3000. The default API is http://localhost:8081. To use another
backend, set `API_PUBLIC_URL` in `.env` and rebuild. The webapp starts independently;
application data and login require a reachable API with the webapp origin allowed
in its CORS and SAML callback configuration.

For Flutter development, install the pinned Flutter 3.41.1 SDK:

```sh
flutter pub get --enforce-lockfile
flutter run -d chrome --web-port=3000 --dart-define=API_URL=http://localhost:8081
```

For opt-in local bootstrap login, add `--dart-define=LOCAL_AUTH_ENABLED=true` and
explicitly enable local auth on a local backend. Production builds disable it.

`API_URL`, `APP_ENV` and `LOCAL_AUTH_ENABLED` are compile-time configuration.
Changing the API origin requires rebuilding the webapp. No database password,
signing key or other runtime secret belongs in Flutter defines or client assets.

## Verify

```sh
python3 scripts/audit-no-aws.py
python3 -m unittest discover -s scripts/tests -v
python3 scripts/test-static-http.py
flutter analyze
flutter test
flutter test --platform chrome test/features/batches/campaign_assignment_dialog_test.dart test/features/batches/campaign_ownership_section_test.dart test/features/microscope_upload/microscope_file_source_web_test.dart test/features/rnd/rnd_experiment_filter_web_test.dart
flutter build web --release --dart-define=APP_ENV=production --dart-define=API_URL=https://api.example.invalid --dart-define=LOCAL_AUTH_ENABLED=false
```

The example HTTPS origin is only a build placeholder; use the real API origin for
a release. The supported release target is JavaScript. PDF.js assets are bundled
locally. Browser uploads, downloads and campaign structure management replace
native folder scanning and OS integration.

[Feature parity](docs/feature-parity.md) records the reviewed CrystalApp version.
The optional source audit accepts an independent source checkout:
`python3 scripts/audit-feature-parity.py --source /path/to/crystalApp`.
Neither CI nor deployment needs that checkout.

## Deploy

[Deployment guide](docs/deployment.md) lists GitHub secrets and variables, VPS
setup and host TLS configuration. Main pushes target the development VPS; manually
created `vMAJOR.MINOR.PATCH` tags release production on its separate VPS. Each
environment has its own settings and `DEPLOY_ENABLED` switch. The selected
environment's API origin is embedded in its image. Hosted development retains
the production security settings.
The server defaults to loopback port 3000, with `/healthz` for readiness.

Analyzer/retrainer execution remains deferred on the backend. New uploads do not
become analyzed merely because the browser accepted them. Never commit `.env`,
secrets, TIFF/TXT data, reports, model weights or migration evidence. Run tests
and `scripts/audit-no-aws.py` before committing.
