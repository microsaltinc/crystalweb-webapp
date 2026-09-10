import 'package:flutter/material.dart';
import '../models/campaign_workflow_status.dart';

Future<CampaignWorkflowStatus?> showWorkflowStatusPicker(
  BuildContext context,
  List<CampaignWorkflowStatus> statuses,
) => showDialog<CampaignWorkflowStatus>(
  context: context,
  builder: (context) => AlertDialog(
    title: const Text('Change workflow status'),
    content: SizedBox(
      width: 360,
      child: ListView(
        shrinkWrap: true,
        children: statuses
            .map(
              (status) => ListTile(
                title: Text(status.label),
                leading: const Icon(Icons.flag_outlined),
                onTap: () => Navigator.pop(context, status),
              ),
            )
            .toList(),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
    ],
  ),
);
