import 'package:flutter/material.dart';

import '../models.dart';

/// Prompts for new text on both sides of [card]. Returns the trimmed
/// values, or null if cancelled, empty, or unchanged.
Future<({String native, String target})?> showEditCardDialog(
  BuildContext context, {
  required CardItem card,
  required String nativeLanguage,
  required String targetLanguage,
}) async {
  final nativeController = TextEditingController(text: card.native);
  final targetController = TextEditingController(text: card.target);

  final result = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Edit card'),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: targetController,
              autofocus: true,
              decoration: InputDecoration(labelText: targetLanguage),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: nativeController,
              decoration: InputDecoration(labelText: nativeLanguage),
              onSubmitted: (_) => Navigator.pop(context, true),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Save'),
        ),
      ],
    ),
  );

  final native = nativeController.text.trim();
  final target = targetController.text.trim();
  if (result != true || native.isEmpty || target.isEmpty) return null;
  if (native == card.native && target == card.target) return null;
  return (native: native, target: target);
}
