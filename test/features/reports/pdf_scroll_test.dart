import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfx/src/viewer/interactive_viewer.dart' as pdf;

const _pointer = Offset(300, 250);

Future<pdf.TransformationController> _viewer(
  WidgetTester tester, {
  double zoom = 1,
  Offset position = const Offset(-300, -1000),
  pdf.InteractiveViewerScrollControls controls =
      pdf.InteractiveViewerScrollControls.scrollPans,
  GestureScaleUpdateCallback? onUpdate,
}) async {
  final controller = pdf.TransformationController();
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 600,
          height: 500,
          child: pdf.InteractiveViewer(
            transformationController: controller,
            scrollControls: controls,
            onInteractionUpdate: onUpdate,
            constrained: false,
            minScale: 1,
            maxScale: 20,
            child: const SizedBox(width: 2000, height: 12000),
          ),
        ),
      ),
    ),
  );
  controller.value = Matrix4.diagonal3Values(zoom, zoom, 1)
    ..setTranslationRaw(position.dx, position.dy, 0);
  await tester.pump();
  return controller;
}

Offset _position(pdf.TransformationController controller) {
  final translation = controller.value.getTranslation();
  return Offset(translation.x, translation.y);
}

Future<void> _wheel(WidgetTester tester, Offset delta) {
  return tester.sendEventToBinding(
    PointerScrollEvent(
      position: _pointer,
      scrollDelta: delta,
      kind: PointerDeviceKind.mouse,
    ),
  );
}

void _expectPosition(Offset actual, Offset expected) {
  expect(actual.dx, closeTo(expected.dx, 0.001));
  expect(actual.dy, closeTo(expected.dy, 0.001));
}

void main() {
  for (final zoom in [1.0, 1.5, 2.0, 4.0]) {
    testWidgets('wheel travel stays constant at ${zoom}x zoom', (tester) async {
      final controller = await _viewer(tester, zoom: zoom);
      final before = _position(controller);
      await _wheel(tester, const Offset(40, 120));
      await tester.pump();
      _expectPosition(_position(controller), before - const Offset(40, 120));

      await _wheel(tester, const Offset(-40, -120));
      await tester.pump();
      _expectPosition(_position(controller), before);
      expect(controller.value.getMaxScaleOnAxis(), closeTo(zoom, 0.001));
    });
  }

  testWidgets('small trackpad-style deltas accumulate without jumps', (
    tester,
  ) async {
    final controller = await _viewer(tester, zoom: 4);
    final before = _position(controller);
    for (var i = 0; i < 20; i++) {
      await _wheel(tester, const Offset(0.25, 1.5));
      await tester.pump(const Duration(milliseconds: 16));
      _expectPosition(
        _position(controller),
        before - Offset(0.25 * (i + 1), 1.5 * (i + 1)),
      );
    }
  });

  for (final zoom in [1.0, 4.0]) {
    testWidgets('wheel cancels drag momentum at ${zoom}x zoom', (tester) async {
      final controller = await _viewer(tester, zoom: zoom);
      await tester.flingFrom(
        const Offset(300, 400),
        const Offset(0, -200),
        1000,
      );
      await tester.pump(const Duration(milliseconds: 16));
      final beforeWheel = _position(controller);

      await _wheel(tester, const Offset(0, -120));
      final afterWheel = _position(controller);
      _expectPosition(afterWheel, beforeWheel + const Offset(0, 120));

      // The old animation must not overwrite the new position on any frame.
      for (var frame = 0; frame < 30; frame++) {
        await tester.pump(const Duration(milliseconds: 16));
        _expectPosition(_position(controller), afterWheel);
      }
      await tester.pumpAndSettle();
      _expectPosition(_position(controller), afterWheel);
    });
  }

  testWidgets('drag momentum continues when no wheel input interrupts it', (
    tester,
  ) async {
    final controller = await _viewer(tester);
    await tester.flingFrom(const Offset(300, 400), const Offset(0, -200), 1000);
    await tester.pump(const Duration(milliseconds: 16));
    final before = _position(controller);
    await _wheel(tester, Offset.zero);
    await tester.pump(const Duration(milliseconds: 32));
    expect(_position(controller).dy, lessThan(before.dy));
    await tester.pumpAndSettle();
  });

  testWidgets('wheel keeps the top and bottom document boundaries', (
    tester,
  ) async {
    final controller = await _viewer(tester, zoom: 2, position: Offset.zero);
    await _wheel(tester, const Offset(0, -120));
    await tester.pump();
    _expectPosition(_position(controller), Offset.zero);

    const bottom = 500.0 - 12000.0 * 2;
    controller.value = Matrix4.diagonal3Values(2, 2, 1)
      ..setTranslationRaw(0, bottom, 0);
    await _wheel(tester, const Offset(0, 120));
    await tester.pump();
    _expectPosition(_position(controller), const Offset(0, bottom));

    await _wheel(tester, const Offset(0, -120));
    await tester.pump();
    _expectPosition(_position(controller), const Offset(0, bottom + 120));
  });

  testWidgets('interaction callbacks use viewport coordinates after zooming', (
    tester,
  ) async {
    ScaleUpdateDetails? update;
    await _viewer(tester, zoom: 4, onUpdate: (value) => update = value);
    await _wheel(tester, const Offset(10, 120));
    expect(update, isNotNull);
    expect(update!.localFocalPoint, _pointer - const Offset(10, 120));
    expect(update!.scale, 1);
  });

  testWidgets('pinch zoom still works in the report scroll mode', (
    tester,
  ) async {
    final controller = await _viewer(tester);
    final left = await tester.startGesture(const Offset(250, 250), pointer: 1);
    final right = await tester.startGesture(const Offset(350, 250), pointer: 2);
    await tester.pump();
    await left.moveTo(const Offset(200, 250));
    await right.moveTo(const Offset(400, 250));
    await tester.pump(const Duration(milliseconds: 16));
    await left.moveTo(const Offset(150, 250));
    await right.moveTo(const Offset(450, 250));
    await tester.pump(const Duration(milliseconds: 16));
    await left.up();
    await right.up();
    await tester.pumpAndSettle();
    expect(controller.value.getMaxScaleOnAxis(), greaterThan(1));

    final beforeWheel = _position(controller);
    await _wheel(tester, const Offset(0, 120));
    await tester.pumpAndSettle();
    _expectPosition(_position(controller), beforeWheel - const Offset(0, 120));
  });

  testWidgets('wheel zoom stays anchored and cancels old drag momentum', (
    tester,
  ) async {
    final controller = await _viewer(
      tester,
      controls: pdf.InteractiveViewerScrollControls.scrollScales,
    );
    await tester.flingFrom(const Offset(300, 400), const Offset(0, -200), 1000);
    await tester.pump(const Duration(milliseconds: 16));
    final anchor = controller.toScene(_pointer);
    await _wheel(tester, const Offset(0, -60));
    expect(controller.value.getMaxScaleOnAxis(), greaterThan(1));
    _expectPosition(controller.toScene(_pointer), anchor);
    final afterWheel = _position(controller);
    await tester.pumpAndSettle();
    _expectPosition(_position(controller), afterWheel);
    _expectPosition(controller.toScene(_pointer), anchor);
  });
}
