import 'package:flutter/material.dart';

import '../models.dart';
import '../theme.dart';
import 'tag_chips.dart';

/// Prompts for new text and tags for [card]. Returns the trimmed values,
/// or null if cancelled, empty, or unchanged. New tags typed here are
/// added to [deck], so the deck itself may change even when null comes
/// back — the caller should save either way.
Future<({String native, String target, List<String> tags})?>
    showEditCardDialog(
  BuildContext context, {
  required CardItem card,
  required Deck deck,
}) async {
  final nativeController = TextEditingController(text: card.native);
  final targetController = TextEditingController(text: card.target);
  var tags = List.of(card.tags);

  final result = await showDialog<bool>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: const Text('Edit card'),
        content: SizedBox(
          width: 380,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: targetController,
                  autofocus: true,
                  decoration: InputDecoration(
                    labelText: deck.targetLabel,
                    alignLabelWithHint: true,
                  ),
                  minLines: 5,
                  maxLines: 5,
                  textInputAction: TextInputAction.next,
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: nativeController,
                  decoration: InputDecoration(
                    labelText: deck.nativeLabel,
                    alignLabelWithHint: true,
                  ),
                  minLines: 5,
                  maxLines: 5,
                  // Enter still submits instead of inserting a newline.
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => Navigator.pop(context, true),
                ),
                const SizedBox(height: 18),
                Text(
                  'Tags',
                  style: TextStyle(
                    color: SprakTheme.inkSoft,
                    fontSize: 11,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 8),
                TagSelector(
                  deck: deck,
                  selected: tags,
                  onChanged: (next) => setState(() => tags = next),
                  onTagCreated: () => setState(() {}),
                ),
              ],
            ),
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
    ),
  );

  final native = nativeController.text.trim();
  final target = targetController.text.trim();
  if (result != true || native.isEmpty || target.isEmpty) return null;
  final sameTags = tags.length == card.tags.length &&
      tags.every(card.tags.contains);
  if (native == card.native && target == card.target && sameTags) return null;
  return (native: native, target: target, tags: tags);
}
