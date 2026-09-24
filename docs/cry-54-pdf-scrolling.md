# CRY-54: PDF scrolling

Issue: https://microsalt.youtrack.cloud/issue/CRY-54/PDF-viewing-on-CrystalApp-jumps

## Findings

The report uses `PdfViewPinch` from pdfx 2.9.2. Its wheel handler applies
screen-space movement directly to the scaled document transform. At 4× zoom,
a 120-pixel scroll moves the document 480 pixels. A second problem occurs when
wheel input interrupts a drag: the old inertia animation continues and can
overwrite the new scroll position on the next frame. Both behaviors were
reproduced with the actual viewer component in Chrome and Flutter widget tests.

The reporter's exact PDF, input device, and zoom level are unknown. Component
reproduction alone does not establish which behavior they encountered.

## Plan

1. Keep the existing viewer, PDF renderer, report layout, and authorized loading
   flow. Correct wheel movement by converting viewport displacement to document
   displacement through the inverse transform.
2. Cancel drag inertia when a nonzero wheel event arrives, before moving or
   zooming the document. Keep ordinary drag momentum when no new input arrives.
3. Check in the required pdfx Dart sources and web plugin registration as a
   local dependency. Preserve attribution and document the small upstream patch.
   Ensure Docker includes it before resolving dependencies. Do not patch a
   developer's global package cache or depend on a build-time download script.
4. Add regression tests for several zoom levels, both scroll axes, fractional
   wheel deltas, direction reversal during inertia, document boundaries, and
   zoom/drag behavior. Run the tests on the VM and Chrome, and include Chrome
   regression coverage in CI.
5. Run the full webapp checks and build, then deploy through the development
   workflow. Check an existing PDF in development before closing the issue.

Production promotion is separate. No backend, database, or report-file changes
are required.
