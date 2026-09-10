import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/user_facing_error.dart';
import '../../batches/providers/batch_provider.dart';
import '../../rnd/providers/rnd_batch_provider.dart';
import '../models/purchase_order.dart';
import '../providers/purchase_order_provider.dart';

class PoAssignDialog extends ConsumerStatefulWidget {
  const PoAssignDialog({
    super.key,
    required this.batchId,
    required this.currentPoId,
    this.editable = true,
    this.expectedEditStateVersion,
  });

  final String batchId;
  final String? currentPoId;
  final bool editable;
  final int? expectedEditStateVersion;

  @override
  ConsumerState<PoAssignDialog> createState() => _PoAssignDialogState();
}

class _PoAssignDialogState extends ConsumerState<PoAssignDialog> {
  final _newCodeController = TextEditingController();
  String? _error;
  bool _saving = false;

  @override
  void dispose() {
    _newCodeController.dispose();
    super.dispose();
  }

  Future<void> _assign(String? poId) async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final client = ref.read(apiClientProvider);
      await assignPurchaseOrder(
        client,
        batchId: widget.batchId,
        poId: poId,
        expectedEditStateVersion: widget.expectedEditStateVersion,
      );
      ref.invalidate(batchListProvider);
      ref.invalidate(rndBatchListProvider);
      ref.invalidate(batchDetailProvider(widget.batchId));
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = userFacingError(e, action: 'assign purchase order');
          _saving = false;
        });
      }
    }
  }

  Future<void> _createAndAssign() async {
    final code = _newCodeController.text.trim();
    if (code.isEmpty) {
      setState(() => _error = 'Code is required');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final client = ref.read(apiClientProvider);
      final po = await createPurchaseOrder(client, code);
      await assignPurchaseOrder(
        client,
        batchId: widget.batchId,
        poId: po.id,
        expectedEditStateVersion: widget.expectedEditStateVersion,
      );
      ref.invalidate(purchaseOrderListProvider);
      ref.invalidate(batchListProvider);
      ref.invalidate(rndBatchListProvider);
      ref.invalidate(batchDetailProvider(widget.batchId));
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = userFacingError(e, action: 'remove purchase order');
          _saving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final posAsync = ref.watch(purchaseOrderListProvider);

    return AlertDialog(
      title: const Text('Assign Purchase Order'),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            posAsync.when(
              data: (pos) => _buildPoList(theme, pos),
              loading: () => const Center(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: CircularProgressIndicator(),
                ),
              ),
              error: (e, _) =>
                  Text(userFacingError(e, action: 'load purchase orders')),
            ),
            const Divider(height: 24),
            Text('Create new PO:', style: theme.textTheme.labelMedium),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _newCodeController,
                    enabled: widget.editable && !_saving,
                    decoration: const InputDecoration(
                      labelText: 'PO Code',
                      hintText: 'e.g. PO762',
                      isDense: true,
                    ),
                    textCapitalization: TextCapitalization.characters,
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.add_circle),
                  tooltip: 'Create & Assign',
                  onPressed: _saving || !widget.editable
                      ? null
                      : _createAndAssign,
                ),
              ],
            ),
            if (!widget.editable) ...[
              const SizedBox(height: 8),
              const Text('Read-only — unlock the campaign to assign a PO.'),
            ],
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(
                _error!,
                style: TextStyle(color: theme.colorScheme.error, fontSize: 12),
              ),
            ],
          ],
        ),
      ),
      actions: [
        if (widget.currentPoId != null)
          TextButton(
            onPressed: _saving || !widget.editable ? null : () => _assign(null),
            child: const Text('Unassign'),
          ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
      ],
    );
  }

  Widget _buildPoList(ThemeData theme, List<PurchaseOrder> pos) {
    if (pos.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(
          'No purchase orders yet. Create one below.',
          style: theme.textTheme.bodySmall,
        ),
      );
    }
    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 200),
      child: ListView.builder(
        shrinkWrap: true,
        itemCount: pos.length,
        itemBuilder: (context, index) {
          final po = pos[index];
          final isSelected = po.id == widget.currentPoId;
          return ListTile(
            dense: true,
            selected: isSelected,
            leading: isSelected
                ? const Icon(Icons.check_circle, size: 18)
                : const Icon(Icons.receipt_long, size: 18),
            title: Text(po.code),
            onTap: _saving || !widget.editable
                ? null
                : () {
                    if (!isSelected) _assign(po.id);
                  },
          );
        },
      ),
    );
  }
}
