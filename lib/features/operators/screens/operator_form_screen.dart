import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/user_facing_error.dart';
import '../../../core/auth/auth_provider.dart';
import '../providers/operator_provider.dart';

class OperatorFormScreen extends ConsumerStatefulWidget {
  const OperatorFormScreen({super.key, this.operatorId});

  final String? operatorId;

  @override
  ConsumerState<OperatorFormScreen> createState() => _OperatorFormScreenState();
}

class _OperatorFormScreenState extends ConsumerState<OperatorFormScreen> {
  final _nameController = TextEditingController();
  final _pinController = TextEditingController();
  bool _isSaving = false;
  Set<String> _selectedRoleIds = {};
  String? _error;

  bool get isEditing => widget.operatorId != null;

  @override
  void initState() {
    super.initState();
    if (isEditing) {
      _loadOperator();
    }
  }

  Future<void> _loadOperator() async {
    try {
      final op = await ref.read(
        operatorDetailProvider(widget.operatorId!).future,
      );
      if (mounted) {
        _nameController.text = op.name;
        setState(() {
          _selectedRoleIds = op.roles.map((r) => r.id).toSet();
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error = userFacingError(e, action: 'load operator'));
      }
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _pinController.dispose();
    super.dispose();
  }

  Future<void> _handleSave() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Name is required');
      return;
    }

    setState(() {
      _isSaving = true;
      _error = null;
    });

    try {
      final client = ref.read(apiClientProvider);
      final token = ref.read(authStateProvider).userToken;

      if (isEditing) {
        await client.dio.put(
          '/api/v1/operators/${widget.operatorId}',
          data: {'name': name},
        );
        // Update roles if any are selected
        if (_selectedRoleIds.isNotEmpty) {
          await assignOperatorRoles(
            client,
            operatorId: widget.operatorId!,
            roleIds: _selectedRoleIds.toList(),
            token: token,
          );
        }
      } else {
        final response = await client.dio.post(
          '/api/v1/operators',
          data: {'name': name},
        );
        final newId = response.data['id'] as String;
        // If creating and PIN provided, set PIN on new operator
        final pin = _pinController.text.trim();
        if (pin.isNotEmpty && pin.length >= 4) {
          await client.dio.post(
            '/api/v1/operators/$newId/pin',
            data: {'pin': pin},
          );
        }
        // Assign roles if different from default
        if (_selectedRoleIds.isNotEmpty) {
          await assignOperatorRoles(
            client,
            operatorId: newId,
            roleIds: _selectedRoleIds.toList(),
            token: token,
          );
        }
      }

      // If editing and PIN provided, update PIN
      if (isEditing && _pinController.text.trim().length >= 4) {
        await client.dio.post(
          '/api/v1/operators/${widget.operatorId}/pin',
          data: {'pin': _pinController.text.trim()},
        );
      }

      ref.invalidate(operatorListProvider);

      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error = userFacingError(e, action: 'save operator'));
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final rolesAsync = ref.watch(availableRolesProvider);

    return Scaffold(
      appBar: AppBar(title: Text(isEditing ? 'Edit Operator' : 'Add Operator')),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(labelText: 'Operator Name'),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _pinController,
              decoration: const InputDecoration(
                labelText: 'PIN (optional)',
                hintText: '4-6 digits',
              ),
              keyboardType: TextInputType.number,
              obscureText: true,
              maxLength: 6,
            ),
            const SizedBox(height: 16),
            Text('Roles', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            rolesAsync.when(
              data: (roles) => Wrap(
                spacing: 8,
                children: roles.map((role) {
                  final selected = _selectedRoleIds.contains(role.id);
                  return FilterChip(
                    label: Text(role.name),
                    selected: selected,
                    onSelected: (val) {
                      setState(() {
                        if (val) {
                          _selectedRoleIds.add(role.id);
                        } else {
                          // Prevent deselecting all roles
                          if (_selectedRoleIds.length > 1) {
                            _selectedRoleIds.remove(role.id);
                          }
                        }
                      });
                    },
                  );
                }).toList(),
              ),
              loading: () => const CircularProgressIndicator(),
              error: (e, _) => Text(userFacingError(e, action: 'load roles')),
            ),
            const SizedBox(height: 8),
            Text(
              'At least one role must be assigned',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.outline,
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            const Spacer(),
            SizedBox(
              width: double.infinity,
              child: _isSaving
                  ? const Center(child: CircularProgressIndicator())
                  : ElevatedButton(
                      onPressed: _handleSave,
                      child: Text(isEditing ? 'Update' : 'Create'),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
