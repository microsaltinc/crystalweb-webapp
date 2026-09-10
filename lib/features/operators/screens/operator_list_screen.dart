import 'dart:developer' as dev;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/api/user_facing_error.dart';
import '../providers/operator_provider.dart';

class OperatorListScreen extends ConsumerWidget {
  const OperatorListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final operatorsAsync = ref.watch(operatorListProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Operators'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(operatorListProvider),
          ),
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () => context.push('/operators/new'),
          ),
        ],
      ),
      body: operatorsAsync.when(
        data: (operators) {
          dev.log(
            'OperatorListScreen loaded ${operators.length} operators',
            name: 'OperatorList',
          );
          if (operators.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text('No operators yet'),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: () => ref.invalidate(operatorListProvider),
                    icon: const Icon(Icons.refresh),
                    label: const Text('Refresh'),
                  ),
                ],
              ),
            );
          }
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(operatorListProvider),
            child: ListView.builder(
              itemCount: operators.length,
              itemBuilder: (context, index) {
                final op = operators[index];
                final canDelegate = op.active && op.hasPin;
                return ListTile(
                  leading: CircleAvatar(
                    backgroundColor: canDelegate ? null : Colors.grey[300],
                    child: Text(
                      op.initials,
                      style: TextStyle(color: canDelegate ? null : Colors.grey),
                    ),
                  ),
                  title: Text(
                    op.name,
                    style: TextStyle(color: canDelegate ? null : Colors.grey),
                  ),
                  subtitle: Text(
                    '${op.active ? "Active" : "Inactive"}'
                    '${op.hasPin ? " | PIN set" : " | No PIN"}'
                    '${op.email.isNotEmpty ? " | ${op.email}" : ""}',
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.edit),
                    onPressed: () => context.push('/operators/${op.id}/edit'),
                  ),
                  onTap: canDelegate
                      ? () => context.push(
                          '/operators/${op.id}/pin?name=${Uri.encodeComponent(op.name)}',
                        )
                      : null,
                );
              },
            ),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, stack) {
          dev.log('OperatorListScreen error: $err', name: 'OperatorList');
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(userFacingError(err, action: 'load operators')),
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  onPressed: () => ref.invalidate(operatorListProvider),
                  icon: const Icon(Icons.refresh),
                  label: const Text('Retry'),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
