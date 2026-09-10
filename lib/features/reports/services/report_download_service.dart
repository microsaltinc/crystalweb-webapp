import 'package:url_launcher/url_launcher.dart';

/// Opens short-lived, provider-neutral report capabilities in the browser.
class ReportDownloadService {
  const ReportDownloadService();

  static String fileNameFromUrl(String url, {required String fallback}) {
    if (url.isEmpty) return fallback;
    try {
      final uri = Uri.parse(url);
      final lastSegment = uri.pathSegments.isNotEmpty
          ? uri.pathSegments.last
          : '';
      return lastSegment.isNotEmpty ? lastSegment : fallback;
    } catch (_) {
      return fallback;
    }
  }

  Future<String?> downloadFile({
    required String url,
    required String defaultFileName,
  }) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
    return null;
  }
}
