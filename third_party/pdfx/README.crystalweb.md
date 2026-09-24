# pdfx web dependency for CrystalWeb

Based on the published **pdfx 2.9.2** package:

- Source: https://github.com/ScerIO/packages.flutter/tree/main/packages/pdfx
- Package: https://pub.dev/packages/pdfx/versions/2.9.2
- Original pub.dev archive SHA-256:
  `29db9b71d46bf2335e001f91693f2c3fbbf0760e4c2eb596bf4bafab211471c1`
- License and author attribution: `LICENSE`, `AUTHORS`.

The complete upstream `lib/` is retained. CrystalWeb builds only Flutter Web, so
the local manifest registers only the web plugin. Native platform projects,
examples, generators, and upstream development dependencies are omitted.
The runtime dependency constraints are unchanged. This copy is not published.

## CRY-54 patch

Line endings and trailing whitespace are normalized. Only
`lib/src/viewer/interactive_viewer.dart` has application-specific logic changes:

1. Ignore zero-displacement wheel events.
2. Cancel drag inertia before handling a new wheel event, so the old animation
   cannot overwrite the user's new position (including wheel zoom).
3. Convert wheel pan displacement from viewport coordinates to scene coordinates
   before applying it to the matrix. Preserve viewport coordinates in callbacks.

The existing boundary, zoom, drag, rendering, and document-loading logic remains
upstream code. See `test/features/reports/pdf_scroll_test.dart` for VM and Chrome
regressions. Docker copies this dependency before `flutter pub get`, and CI uses
the checked-in path dependency. Do not modify the global pub cache.

When upgrading pdfx, compare this patch with upstream, rerun these regressions,
and check real reports. Return to a hosted dependency once an upstream version
passes them without the patch; remove the Docker copy and vendored sources then.
