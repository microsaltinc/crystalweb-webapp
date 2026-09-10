import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:pdfx/pdfx.dart';

import '../../../core/api/user_facing_error.dart';

/// Full-screen Web PDF viewer backed by a short-lived artifact capability.
class PdfViewerScreen extends StatefulWidget {
  const PdfViewerScreen({super.key, required this.url, required this.title});

  final String url;
  final String title;

  @override
  State<PdfViewerScreen> createState() => _PdfViewerScreenState();
}

class _PdfViewerScreenState extends State<PdfViewerScreen> {
  PdfControllerPinch? _controller;
  String? _error;
  double _progress = 0;

  @override
  void initState() {
    super.initState();
    _loadPdf();
  }

  Future<void> _loadPdf() async {
    try {
      final response = await Dio().get<List<int>>(
        widget.url,
        options: Options(responseType: ResponseType.bytes),
        onReceiveProgress: _onProgress,
      );
      final data = response.data;
      if (data == null) throw StateError('The report response was empty.');
      _setController(PdfDocument.openData(Uint8List.fromList(data)));
    } on DioException catch (error) {
      if (!mounted) return;
      if (error.response?.statusCode == 403) {
        setState(
          () => _error =
              'PDF link has expired. Go back and re-open the report to get a fresh link.',
        );
      } else {
        setState(() => _error = userFacingError(error, action: 'load PDF'));
      }
    } catch (error) {
      if (mounted) {
        setState(() => _error = userFacingError(error, action: 'load PDF'));
      }
    }
  }

  void _onProgress(int received, int total) {
    if (total > 0 && mounted) {
      setState(() => _progress = received / total);
    }
  }

  void _setController(Future<PdfDocument> document) {
    if (mounted) {
      setState(() {
        _controller = PdfControllerPinch(document: document);
      });
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.error_outline,
              size: 48,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(_error!, textAlign: TextAlign.center),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () {
                setState(() {
                  _error = null;
                  _progress = 0;
                });
                _loadPdf();
              },
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    if (_controller == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(value: _progress > 0 ? _progress : null),
            const SizedBox(height: 16),
            Text(
              _progress > 0
                  ? 'Downloading... ${(_progress * 100).toInt()}%'
                  : 'Loading PDF...',
            ),
          ],
        ),
      );
    }

    return PdfViewPinch(
      controller: _controller!,
      builders: const PdfViewPinchBuilders<DefaultBuilderOptions>(
        options: DefaultBuilderOptions(),
      ),
    );
  }
}
