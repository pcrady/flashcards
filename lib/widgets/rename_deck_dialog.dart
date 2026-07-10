import 'package:flutter/material.dart';

/// Prompts for a new deck name. Returns the trimmed name, or null if
/// cancelled or empty.
Future<String?> showRenameDeckDialog(
    BuildContext context, String currentName) async {
  final controller = TextEditingController(text: currentName);
  final result = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Rename set'),
      content: SizedBox(
        width: 380,
        child: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Set name'),
          onSubmitted: (v) => Navigator.pop(context, v),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, controller.text),
          child: const Text('Rename'),
        ),
      ],
    ),
  );
  final name = result?.trim();
  if (name == null || name.isEmpty || name == currentName) return null;
  return name;
}
