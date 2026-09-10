import 'package:flutter/material.dart';

class CampaignWorkflowStatusChip extends StatelessWidget {
  const CampaignWorkflowStatusChip({
    super.key,
    required this.label,
    required this.colorToken,
  });

  final String label;
  final String colorToken;

  static Color background(String token) => switch (token) {
    'blue' => Colors.blue.shade700,
    'teal' => Colors.teal.shade700,
    'green' => Colors.green.shade700,
    'amber' => Colors.amber.shade800,
    'orange' => Colors.orange.shade800,
    'purple' => Colors.purple.shade700,
    'red' => Colors.red.shade700,
    _ => Colors.grey.shade700,
  };

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Workflow status: $label',
    child: Chip(
      avatar: const Icon(Icons.flag_outlined, size: 16, color: Colors.white),
      label: Text(label, style: const TextStyle(color: Colors.white)),
      backgroundColor: background(colorToken),
    ),
  );
}
