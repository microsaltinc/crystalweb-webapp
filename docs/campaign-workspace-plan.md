# Campaign and experiment workspace redesign

Status: implemented locally; development deployment and browser verification in progress.
Date: 2026-09-19.
Deployment scope: development only.

## User request and checkpoint

The user approved the proposed redesign and requested implementation followed by
testing in development. They then interrupted the first implementation turn to
request that the design and plan be written down and context compacted before
implementation continues. This document is that durable handoff.

The plan was saved before implementation. The shared workspace and early preview
stage are now implemented in the independent webapp/backend repositories. Existing
qualification rules, editor routes, and locking contracts are preserved.

## Problem and agreed direction

The current detail page stacks campaign metadata, editing/locking, qualification,
physical structure, workflow, processing progress, ownership, comments, reports,
and finally images. Structure, qualification, and images repeat the same
sublot/bag hierarchy. Sparse full-width rows separate labels from actions and
push the main review work below several screens of administration.

Replace that organization with one shared campaign/experiment workspace:

- Compact campaign identity, owner, workflow, editing state, and labeled progress.
- A contextual next-action message.
- Sublot/bag navigation beside the selected scope's images and decisions.
- Reports and Discussion as separate workspace tabs.
- Campaign metadata and less frequent campaign controls in a Details/completion
  panel, with clear entry points and no lost capabilities.
- One entity has one place to upload, review, change its decision, and manage it.

Alternative layouts considered:

1. Compact nested cards: smaller change, but still becomes a long page.
2. Separate Setup/Images/Qualification tabs: shorter pages, but repeats context
   switching for the same bag.
3. Navigation beside the working area: recommended and approved; scales to many
   bags while supporting a simple one-bag campaign.

## Proposed layout

```text
Campaigns / E26262A-1
GR.MS.CN.NI.IP.50 · Dryer E · Campaign 1

Owner: Unassigned [Assign]   Workflow: In Progress   Editing: Editable
Analysis: 16/16 ready        Bag decisions: 1 pending         [Details]

Next step: Review the analyzed images.               [Review next image]

[ Images & review ]     Reports     Discussion
-----------------------------------------------------------------------
SUBLOTS & BAGS          Sublot A / Bag 1
                       16 images · Decision pending
All bags
                       [Upload images] [Review images] [Bag actions ...]
v Sublot A       ...
  > Bag 1              Analysis complete · Human review required
    16 images
                       Show: All    Sort: Image number    Thumbnail size
[+ Add sublot]
                       [Image 1]       [Image 2]       [Image 3]
                       Needs review    Needs review    Needs review

                       Bag decision
                       [Accept bag]    [Reject & exclude]
                       Explain any unmet requirement here.
```

This is a conceptual arrangement, not a new required backend schema. Scope
selection should use stable sublot/bag IDs. One bag is selected automatically.
Selecting a sublot or All bags shows a compact overview and/or scoped gallery;
do not force a user to scroll through every bag before reaching images.

For many bags, an overview aligns Bag, Images, Analysis, Human review, and
Decision. Do not invent review counts if the available evidence is incomplete.
Keep bag numbers as identifiers; real bags include 1, 40, 41, 80, etc.

On smaller screens, use a scope picker or drawer rather than squeezing the tree
and gallery into narrow columns. Keep touch targets and keyboard navigation
usable. Thumbnail sizes should remain useful on wide screens and preserve the
full image composition. Distinguish the control widths from the gallery width.

## Capabilities that must remain available

| Scope | Capabilities and proposed home |
| --- | --- |
| Campaign/experiment identity | Lot code, formula, dryer, campaign number, dates, stable IDs and copy controls in compact header/Details |
| Collaboration | Assign/reassign owner and change workflow in header; comments in Discussion |
| Business context | Purchase-order association for campaigns; Project association for R&D experiments |
| Sublot | Add, rename, label, add bag, archive/delete when allowed, restore; actions beside the sublot |
| Bag structure | Add, renumber, edit/move between sublots, archive/delete when allowed, restore; bag actions |
| Upload | Visible text button, explicit destination, matching TIFF/TXT guidance, progress, pause/resume/retry, retained-work recovery and discard controls |
| Image | Open existing editor, edit annotations, complete/clear review, reanalyze, relocate to another bag, discard/restore |
| Bag qualification | Accept, reject/exclude with reason/notes, return to pending; show prerequisites inline |
| Sublot bulk action | Accept eligible bags with explicit scope/count and skipped bags; never imply a separate sublot qualification decision |
| Campaign qualification | Finalize accepted, accepted with exclusions, or rejected according to existing eligibility rules |
| Reports | Generate/regenerate campaign and bag reports, view PDF, download PDF/CSV, current/stale/history state, retry failures |
| Downloads | Existing campaign image download and format choice |
| Locking | Readiness/blocker details, lock/unlock and optional reason, read-only presentation, consequences explained |
| Problems | Registration conflicts, incomplete uploads, analysis failures and actionable recovery attached to affected scope |

Keep frequent actions visible with text. Put infrequent structural actions in
labeled menus. Destructive actions need clear names and existing protections.
Archive, reject/exclude, discard image, and discard unfinished upload are distinct
operations and must not become one generic Remove command.

Preserve original/source identifiers and audit history; keep them in Details
instead of repeating them in every row. Renaming/moving logical structure must
not rename or delete original files.

## State vocabulary and guidance

- Replace ambiguous analysis `complete` labels with "Analysis complete".
- Explicitly distinguish upload, analysis, human review, bag decision, workflow,
  and editability. Never imply that AI completion is human approval.
- Show queued/analyzing/ready/failed counts and update them automatically while
  work is active. Poll safely, stop when inactive/disposed, preserve selected
  scope and scroll position, and avoid disrupting editing or in-flight dialogs.
- LLM processing has no reliable percentage ETA; show actual counts/status.
- Empty bag: Upload microscope images, with TIFF/TXT pairing guidance.
- Uploading: progress/resume status. An uploaded image may still await analysis.
- Analysis in progress: review already completed images while others run.
- Analysis complete: Review next image.
- Review/qualification outstanding: navigate to the relevant bag or image.
- Completion: show applicable report/qualification/locking requirements and
  direct navigation to resolve them. Use current server rules, not a made-up
  mandatory wizard sequence.
- Explain disabled actions in visible text, not only hover tooltips.
- Prefer "Create campaign" / "Create experiment" over "Create destination".

## Important domain constraints discovered in the code

1. Qualification is recorded on bags and campaigns. Sublots aggregate bag
   decisions and have no independent qualification status.
2. `operator_reviewed_bag_ids` currently means a bag has at least one
   non-discarded Crystal with `source == 'operator'`. This is separate from
   explicit image review-complete evidence. Explain this rule in the UI.
3. The prior proposal identified changing that acceptance rule as a separate
   product decision. Do not silently change it in this redesign. A reviewer
   should eventually be able to confirm correct AI results without manufacturing
   an annotation, but the acceptance semantics are not approved for alteration.
4. Locking uses server readiness including analysis, explicit image reviews,
   current campaign reports, and active work. Do not replace this with a
   client-invented readiness rule. Existing workflow Done and locking are separate.
5. Locked content stays read-only; viewing, existing downloads, comments, and
   authorized Unlock remain available. Preserve concurrent-edit/version guards.
6. Rejected bags remain auditable and affect report inclusion. Reports have
   historical/current/stale meanings that must survive the reorganization.

## Previews before analysis

The approved proposal includes showing uploaded images before the LLM finishes.
Currently `core/analyzer/worker.py` invokes the model, validates results, and only
then calls `write_previews` and publishes the preview/thumbnail keys with results.

Implement an appropriate early preview preparation path in the backend. Inspect
the existing upload-finalization and durable worker architecture before choosing
the exact mechanism. Preparation must not wait behind all long-running LLM calls
or mark an image analyzed. Avoid doing expensive multi-image processing inline in
an upload HTTP request. Keep the source image/calibration/footer coordinate
contract, authenticated storage access, fencing, crash recovery, and bounded
resource usage. If this needs a separate durable stage, implement and test it
explicitly rather than presenting local temporary thumbnails as persisted previews.

The separate analyzer library does not need a detector/prompt redesign for this UI
project. Maintain 4 images/request, maximum 100 annotations/image, and at most two
concurrent provider requests.

## Implementation sequence

- [x] Inspect current branches, local instructions, deployment workflows, widget
      tests, providers and reusable action dialogs. Preserve unrelated changes.
- [x] Turn this plan into shared workspace components and stable scope state.
      Refactor existing actions/dialogs for reuse instead of duplicating logic.
- [x] Build the compact header, next-action guidance, tabs and responsive scope
      navigator; auto-select the only bag where applicable.
- [x] Integrate scoped images, bag qualification, inline prerequisites and
      structural actions. Preserve bulk acceptance, archive/restore and conflicts.
- [x] Rehome reports, discussion, details, assignment, workflow and completion
      controls without removing any existing path.
- [x] Add safe progress refresh, explicit status vocabulary, practical gallery
      density, meaningful empty/error/locked states, and friendly creation copy.
- [x] Implement/test early backend previews separately from analysis completion.
- [x] Run relevant Flutter tests/analyzer/build, backend tests for any backend
      change, and each repository's `scripts/audit-no-aws.py` before commits.
- [ ] Commit/push the appropriate independent repositories. Main deploys dev;
      never create production tags or trigger production deployment for this task.
- [ ] Verify GitHub workflows, dev service health, deployed UI layout and core
      flows. Report precisely what was tested and any remaining limitations.

Do not stop after merely building the mock: user authorized implementation and
development deployment. Their latest instruction is to compact first and resume
implementation from this document.

## Acceptance and test scenarios

1. New user creates a one-bag campaign, finds Upload without icon hunting, sees
   previews/progress, opens review, and understands the pending bag decision.
2. Experienced reviewer handles an eight-bag campaign with no repeated hierarchy,
   can switch scope, review images, inspect eligibility, and use eligible bulk
   acceptance without accidentally accepting other bags.
3. A locked campaign remains viewable with reports/history/downloads/comments;
   prohibited mutations cannot be triggered.
4. R&D uses the same interactions and correct experiment terminology/Project
   context; campaign purchase-order behavior is preserved.
5. Polling updates status without resetting tabs/selection, interrupting uploads,
   losing unsaved edits, or causing unnecessary background requests.
6. Empty, archived, rejected, failed, paused/resumable, stale-report, and missing
   qualification-data states remain understandable and recoverable.
7. Image editor supports current four-sided annotations and measurements; review
   evidence, user changes and concurrency guards remain intact.
8. Early previews are accessible before LLM completion and do not fabricate
   analysis success, calibration, or human review.
9. Desktop and narrower viewports have no inaccessible controls or overflow;
   color is not the sole status indicator, and controls have accessible labels.

Browser testing must use Playwright CLI, not MCP, per the user's standing
preference. Reuse existing authorized dev tabs when available; do not open many
tabs or interact with production. Existing user campaigns should be read-only
during validation; use clearly labeled development QA data for mutations.

## Files and operational context for resuming

Workspace: `/Users/rdc/Dev/crystalWeb` (not a single Git repository).

Repositories:
- `crystalweb-webapp`: Flutter Web, primary implementation target.
- `crystalweb-backend`: FastAPI, PostgreSQL 18, mounted filesystem, analyzer worker.
- `crystalweb-analyzer`: already-published private library; no changes planned here.
- `../crystalApp`: original application, read-only; do not change it.

Key frontend files under `lib/features/`:
- `batches/screens/batch_detail_screen.dart` (also used for R&D via routeRoot).
- `batches/widgets/campaign_structure_section.dart` (dialogs/help/actions).
- `batches/widgets/campaign_qualification_section.dart` (bag and bulk decisions).
- `batches/widgets/campaign_locking_section.dart` (readiness dialog/transition).
- `batches/widgets/campaign_ownership_section.dart`, `campaign_workflow_section.dart`.
- `batches/widgets/campaign_comments_section.dart`, `campaign_registration_conflicts_section.dart`.
- `batches/widgets/campaign_create_dialog.dart`.
- `batches/models/` and `batches/providers/` for structure, qualification, locks,
  workflow, assignment and list filters.
- `images/widgets/image_grid.dart` (currently grouped by sublot, sorted by bag).
- `images/screens/image_detail_screen.dart`, `images/widgets/image_review_status.dart`.
- `images/providers/image_provider.dart` (currently no automatic campaign polling).
- `microscope_upload/widgets/microscope_upload_dialog.dart` and its providers.
- `reports/widgets/report_section.dart`.
- `rnd/screens/rnd_batch_list_screen.dart` (Project association).
- `core/routing/app_router.dart` (preserve campaign/experiment image deep links).

Key backend files:
- `api/campaign_qualification/service.py`, `core/campaign_qualification.py`.
- `api/campaign_locking/service.py` (readiness and review evidence).
- `api/microscope_uploads/service.py` (finalization/enqueue transaction).
- `core/analyzer/{adapter,worker,queue,publish}.py` and queue models.
- `docs/analyzer.md` (current analysis mapping/queue/credentials/operations).

Existing tests are in frontend `test/features/{batches,images,microscope_upload,reports,rnd}`
(discover exact paths with rg); backend queue tests are in
`tests/integration/test_analyzer_queue.py`. Both repos use
`.github/workflows/deploy.yml`; read their actual validation commands before work.

Development URLs:
- Webapp: `https://dev-crystal.microsalt.in`.
- API: `https://dev-crystal-api.microsalt.in`.
- Backend SSH alias: `vps-cicd`, unprivileged `cicd-user`, rootless Docker.
- Webapp service account is separate `cicd-webapp`; discover existing SSH/workflow
  configuration without printing credentials. No host root/sudo for routine work.

Useful existing development campaigns (read-only references):
- `908d4450-5fda-4905-95ed-c1aae10a9b52`, E26262A-1: one bag, 16 analyzed images;
  user screenshots show all 16 processed after initial upload/analysis delay.
- `3bb4604f-55b8-43b5-9f26-9f33cb59110d`, L26063A-1: eight bags visible in screenshot.
- `e6a0e8b3-7b3a-466d-a49d-2e82b6904438`: prior labeled analyzer QA campaign, five images.

Earlier analyzer integration is complete: backend `be2d26d411e0678252b903bd8a22f807c8a7d905`,
analyzer `1b0fdc091cbf36a7b4135788b425b8cf5707c036`; verify current heads rather than
assuming no subsequent changes. Its live test passed; do not re-migrate data or
redo authentication setup. Source audit uses no AWS additions. Do not commit
secrets, image data, dumps, generated reports or migration evidence.

GitHub is accessible via `gh`. Machine default Git SSH credentials previously
failed for these private repos; authenticated HTTPS with the gh credential helper
worked. Do not print tokens or change unrelated credential configuration.

No sub-agents have been authorized for this work; proceed locally unless that
instruction changes. Keep the user informed during implementation.
