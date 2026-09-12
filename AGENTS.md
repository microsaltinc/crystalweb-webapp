# crystalweb-webapp agent instructions

- This repository owns only the Flutter Web client and its static HTTP service. It must build and deploy without backend source or a shared Docker network.
- Never add AWS SDKs, S3 adapters, ECS/Lambda code, AWS credentials, or cloud emulators.
- Preserve API/database compatibility; legacy `s3_key` JSON/database field names are compatibility identifiers only and must never select a cloud backend.
- PostgreSQL 18 is the only supported database engine.
- Files live under the configured mounted filesystem storage root and are served only through authorized API capabilities.
- Google Workspace SAML remains the production authentication mechanism. Local bootstrap auth is opt-in, local-only, and fail-closed elsewhere.
- Analyzer/retrainer runtime is deferred. Never mark an image analyzed without a future analyzer worker actually succeeding.
- Never commit `.env`, secrets, dumps, TIFF/TXT data, generated reports, model weights, or migration evidence.
- Run tests and `scripts/audit-no-aws.py` before commits.
- Production uses its own unprivileged account and rootless Docker daemon. Never grant it sudo or privileged Docker-group membership, share its SSH key with the backend, or fall back to the host Docker socket. Use administrator sudo only for specific host provisioning tasks.
