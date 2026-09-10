import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/user_facing_error.dart';
import '../../../core/auth/auth_provider.dart';
import '../../../core/config/app_config.dart';
import '../providers/analyzer_settings_provider.dart';
import '../widgets/campaign_workflow_settings_dialog.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = ref.watch(appConfigProvider);
    final authState = ref.watch(authStateProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(24.0),
        children: [
          Text(
            'Microscope storage',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          const ListTile(
            leading: Icon(Icons.cloud_done_outlined),
            title: Text('Server-managed direct upload'),
            subtitle: Text(
              'Campaign, Sublot, and Bag destinations are created in CrystalApp. '
              'Select exact TIFF/TXT pairs in the Campaign to upload them securely.',
            ),
          ),
          const Divider(height: 48),
          Text(
            'Campaign Workflow',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          ListTile(
            leading: const Icon(Icons.flag_outlined),
            title: const Text('Workflow statuses'),
            subtitle: const Text(
              'Configure campaign status labels, colors, order, and default.',
            ),
            onTap: () => showDialog(
              context: context,
              builder: (_) => const CampaignWorkflowSettingsDialog(),
            ),
          ),
          const Divider(height: 48),
          Text('Analysis', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(
            'Crystals smaller than this area are hidden by default. '
            'Operators can override per-crystal.',
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: Colors.grey[600]),
          ),
          const SizedBox(height: 12),
          const _MinCrystalAreaSetting(),
          const Divider(height: 48),
          Text('Connection', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          ListTile(
            leading: const Icon(Icons.cloud),
            title: const Text('API Server'),
            subtitle: Text(config.apiBaseUrl),
          ),
          ListTile(
            leading: const Icon(Icons.dns),
            title: const Text('Environment'),
            subtitle: Text(config.env.name),
          ),
          const Divider(height: 48),
          Text('Account', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          if (authState.isAuthenticated && authState.user != null) ...[
            ListTile(
              leading: const Icon(Icons.person),
              title: Text(authState.user!.name),
              subtitle: Text(authState.user!.email),
            ),
            ListTile(
              leading: const Icon(Icons.badge),
              title: const Text('Role'),
              subtitle: Text(authState.user!.role.name),
            ),
          ] else
            const ListTile(
              leading: Icon(Icons.person_off),
              title: Text('Not signed in'),
            ),
          const SizedBox(height: 24),
          if (authState.isAuthenticated)
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () async {
                  await ref.read(authServiceProvider).signOut();
                  ref.read(authStateProvider.notifier).setUnauthenticated();
                },
                icon: const Icon(Icons.logout),
                label: const Text('Sign Out'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Theme.of(context).colorScheme.error,
                ),
              ),
            ),
          const SizedBox(height: 48),
          const _AppVersionLabel(),
        ],
      ),
    );
  }
}

/// Inline editor for the minimum crystal area threshold.
class _MinCrystalAreaSetting extends ConsumerStatefulWidget {
  const _MinCrystalAreaSetting();

  @override
  ConsumerState<_MinCrystalAreaSetting> createState() =>
      _MinCrystalAreaSettingState();
}

class _MinCrystalAreaSettingState
    extends ConsumerState<_MinCrystalAreaSetting> {
  final _controller = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final value = double.tryParse(_controller.text);
    if (value == null || value <= 0 || value > 100) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a value between 0 and 100')),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      final client = ref.read(apiClientProvider);
      await updateMinCrystalArea(client, value);
      ref.invalidate(analyzerSettingsProvider);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Threshold saved')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(userFacingError(e, action: 'save threshold'))),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final settingsAsync = ref.watch(analyzerSettingsProvider);

    return settingsAsync.when(
      data: (currentValue) {
        if (_controller.text.isEmpty) {
          _controller.text = currentValue.toStringAsFixed(3);
        }
        return Row(
          children: [
            Expanded(
              child: TextFormField(
                controller: _controller,
                decoration: const InputDecoration(
                  labelText: 'Min Crystal Area (μm²)',
                  helperText: 'Default: 0.636',
                  border: OutlineInputBorder(),
                ),
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
              ),
            ),
            const SizedBox(width: 12),
            ElevatedButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Save'),
            ),
          ],
        );
      },
      loading: () => const ListTile(
        leading: CircularProgressIndicator(),
        title: Text('Loading threshold...'),
      ),
      error: (err, _) => ListTile(
        leading: const Icon(Icons.error, color: Colors.red),
        title: Text(userFacingError(err, action: 'load settings')),
      ),
    );
  }
}

/// Displays the app version read from pubspec.yaml at runtime.
class _AppVersionLabel extends StatelessWidget {
  const _AppVersionLabel();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<PackageInfo>(
      future: PackageInfo.fromPlatform(),
      builder: (context, snapshot) {
        final version = snapshot.data?.version ?? '...';
        return Center(
          child: Text(
            'CrystalApp v$version',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: Colors.grey),
          ),
        );
      },
    );
  }
}
