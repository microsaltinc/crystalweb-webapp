import 'package:flutter/material.dart';

/// Dialog that lets the user choose which image format to download.
///
/// Returns the selected format string ('cropped', 'original', 'thumbnail')
/// or null if the user cancels.
class DownloadFormatDialog extends StatelessWidget {
  const DownloadFormatDialog({super.key});

  static Future<String?> show(BuildContext context) {
    return showDialog<String>(
      context: context,
      builder: (_) => const DownloadFormatDialog(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Download Images'),
      content: const Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Choose the image format to download:'),
          SizedBox(height: 16),
          _FormatOption(
            icon: Icons.crop,
            title: 'Cropped Images',
            subtitle: 'Processed JPEGs without metadata bar',
            format: 'cropped',
          ),
          Divider(height: 1),
          _FormatOption(
            icon: Icons.image,
            title: 'Original TIFFs',
            subtitle: 'Full-resolution raw microscope images',
            format: 'original',
          ),
          Divider(height: 1),
          _FormatOption(
            icon: Icons.photo_size_select_small,
            title: 'Thumbnails',
            subtitle: 'Small preview images',
            format: 'thumbnail',
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}

class _FormatOption extends StatelessWidget {
  const _FormatOption({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.format,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String format;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      subtitle: Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
      onTap: () => Navigator.pop(context, format),
      dense: true,
    );
  }
}
