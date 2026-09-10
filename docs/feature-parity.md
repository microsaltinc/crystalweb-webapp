# CrystalApp feature parity

Reviewed on September 9, 2026 against the fetched CrystalApp `main` commit
`3b9c0f446206ca26d95610cae800b40192178e12` (September 7), version `0.9.40+40`.
CrystalWeb's original portability baseline was `fe82f5b692bec27948c0136646aea8ede86451a3`.

The neighboring checkout was on `016-CRY-32-fix-formula-edit` at `939cc73`, with
uncommitted Dart formatting changes. Its branch and working files were preserved.
The comparison used committed `origin/main` files, including `f2e4cfd` (manual
campaign assignment) and `a0001b3` (assignment directory accounts from parent SSO
users). At the time of that parity pass, CrystalWeb had no `.git` directory. On September
10 the backend and webapp were split into independent repositories. This document
records the combined feature review; current standalone commands are in README.md.

## Feature coverage

| CrystalApp capability | CrystalWeb behavior and validation |
| --- | --- |
| Google Workspace SAML, JWT sessions, operator PIN delegation | Preserved, with browser callback capture, session restoration, group memberships, and role routing. Auth API and Flutter auth/routing tests pass. |
| Operator/team management and roles | Preserved. Changes to operator records, PINs and roles require the owning SSO user. Delegated users cannot modify another account's operators. |
| Production campaigns | Create/list/detail, existing lot/date/dryer/formula rules, filters, purchase order assignment and download controls are preserved. Browser creation replaces native folder creation. |
| R&D experiments and projects | Experiment creation, testing-formula selection, project assignment and all experiment filters are preserved. Chrome filter tests pass. |
| Formulas and formula options | Composition fields, extra ingredients, generated codes, testing/production modes, filters, conflict messages and CRUD are preserved. |
| Manual assignment and reassignment | Added the latest eligible-operator directory, two-column Operator/Account picker, current-owner marker, confirmation, and ownership version conflicts. API, widget and Chrome tests pass. |
| Earlier ownership API | Claim/release/transfer endpoints remain compatible and advance the same ownership version. PostgreSQL races prove only one competing update commits. |
| Campaign collaboration | Ownership filters, comments, attribution and assignment audit events are preserved. |
| Workflow settings and status | Catalog labels, colors, order, defaults, transitions and catalog version checks are preserved. |
| Review completion and campaign locking | Image reviews, readiness checks, locking/unlocking, stale-write protection and publication checks are preserved. PostgreSQL locking tests pass. |
| Qualification and structure | Campaign/Sublot/Bag qualification, creation, renaming, relocation, renumbering, archive and audit workflows are preserved. Source identity remains immutable. |
| Registration conflicts | Preserved registration conflicts can still be reviewed/resolved through the API and UI, using logical filesystem identifiers. |
| TIFF/TXT uploads | Browser file selection, grouping, whole-file/part hashing, bounded multipart uploads, progress, pause/resume, cancellation, expiry, exact retry and cross-operator recovery use durable filesystem staging. Chrome exercises file hashing and release. |
| Image browsing and SEM metadata | Grids, filtering, metadata, zoom, overlays and image details are preserved. Input/artifact access uses API-issued capabilities. |
| Crystal annotation | Add/edit/delete/discard, interactive overlays, keyboard shortcuts, measurements, review state and edit history are preserved for existing analysis data. |
| Invalidation, relocation and reprocessing requests | Existing API/UI workflows remain. Reprocessing queues work as pending; this phase does not execute analysis. |
| Reports | Campaign/Sublot/Bag generation, accepted-population statistics, charts, source attribution, PDF/CSV viewing and downloads are preserved. Files are published to mounted storage; persisted unfinished report jobs resume at API startup. |
| Image ZIP export | Original TIFF, cropped images and thumbnails remain available; cropped exports include `plain/` and `crystals/` folders. Archives are built on mounted temporary storage with size limits. |
| Settings and navigation | Workflow settings, minimum crystal area, account/session, connection information, version and logout are preserved. |
| Legacy release download routes | Remain protected and can serve release artifacts placed under the configured storage root. Native builds themselves are outside this web project. |

## Intentional boundaries

The native folder picker, filesystem scanning, OS file-manager integration, native
save/share dialogs and deep links are replaced by browser campaign/structure
creation, direct file uploads and browser downloads. Native device folder-path
preferences have no browser equivalent because storage destinations are managed
by the server. The unused upstream workflow-draft provider is unnecessary: the
active settings dialog manages and validates its own draft.

Analyzer/retrainer execution, weights, trigger dispatch, cloud reconciliation and
cloud infrastructure remain deferred or excluded, as required by `AGENTS.md` and
the README. The annotation and reporting features can use existing analyzed data;
new uploads remain pending. No successful analysis is fabricated. OAuth remains
retired; production uses SAML and local bootstrap remains explicitly opt-in.

These boundaries mean this is application feature parity for the agreed backend
and browser scope, not a claim that this phase runs the CrystalApp ML pipeline.

## Migration compatibility

CrystalApp used revision `030` for manual assignment. CrystalWeb already uses
`030` for analyzer slot reservations and `031` for SAML group persistence. The
assignment changes therefore live in **`032_add_manual_campaign_assignment.py`**,
after `031`. Existing revisions were not changed or renumbered.

The new revision adds `batches.ownership_version` (default `1`) and
`batch_ownership_events.assignment_source` (default `manual`), with the same
constraints as upstream. Existing owners/events are preserved. PostgreSQL tests
exercise upgrade, constraints, downgrade and re-upgrade; a separate empty database
successfully applied the entire migration chain through `032`.

A future source-database import must reconcile migration provenance: an exported
CrystalApp `alembic_version = '030'` is **not** CrystalWeb revision `030`. Do not
blindly stamp or run a source dump as a local database. Reconcile its actual schema
with the local slot/group/assignment migrations in an isolated import rehearsal.
Legacy `s3_*` API/database fields retain their names as logical identifiers only.

## Repeatable source audit

```bash
git -C /path/to/crystalApp fetch origin refs/heads/main:refs/remotes/origin/main
python3 scripts/audit-feature-parity.py --source /path/to/crystalApp
python3 scripts/audit-no-aws.py
```

The explicit branch ref avoids confusing the source repository's `main` tag with
its branch. `--source` and `--ref` can select another checkout or committed ref.
The parity audit itself performs no fetch and does not need CrystalWeb Git metadata.

The original combined audit compared **289 tracked source files** across backend API/core/migrations,
Flutter application code, web assets and the frontend manifest: **229 are byte
identical, 49 have reviewed adaptations, and 11 are intentionally omitted**.
Each standalone repository now audits only its own source prefix. Its
`scripts/feature-parity.json` records exact source and destination Git blob hashes
and a rationale for each adaptation, including renamed files. New or changed
feature files fail the audit until their implementation and tests are reviewed.
The manifest is review configuration, not runtime behavior or proof of execution.
Tests and generated build output are outside the source comparison.

## Standalone repository validation (September 10)

The repositories build separate Docker images and run as separate Compose
projects. Each remains healthy when the other project is stopped. API CORS
exposes upload/download headers to the configured independent browser origin.
The split backend suite passed 761 tests (66 explicit skips); Flutter passed
389 tests (3 VM-only skips), and all 8 selected Chrome tests passed. Deployment
bundle tests, source parity, no-AWS audits and workflow/shell validation passed.
Actual VPS deployment and Workspace login require the deployment configuration.

## Original combined validation

- Backend suite: **760 passed, 66 skipped**, with a disposable PostgreSQL 16 server.
  Skips include opt-in deployment tests and inherited conditional tests; they are
  not counted as verified execution. Lightweight inherited API tests still use
  in-memory fixtures; migration/concurrency proofs use real PostgreSQL 16.
- Flutter suite: **389 passed, 3 browser-only tests skipped on the VM**.
- Chrome: **8 passed**, including those browser-only file-source/filter tests and
  the assignment/reassignment dialogs.
- `flutter analyze`: no issues. Ruff, source parity and no-AWS audits passed.
- Production-configured JavaScript Web release build passed with explicit HTTPS
  API origin and local authentication disabled. Dependencies still emit optional
  WebAssembly compatibility warnings; this project builds the JavaScript target.
- Compose configuration validates; OpenAPI exposes **93 paths, 113 operations,
  105 schemas**, including both new assignment routes.

Current build and verification commands are in [README.md](../README.md).
Backend and webapp source paths above identify the upstream layout; no sibling
checkout is required. Production Workspace login, representative imported data,
TLS and VPS backup/restore still require validation in the target environment.
See [deployment.md](deployment.md) for the independent deployment configuration.
