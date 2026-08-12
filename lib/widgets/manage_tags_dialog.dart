import 'package:flutter/material.dart';

import '../models.dart';
import '../theme.dart';

/// Edits the set of tags a deck's cards may use. Renaming or deleting a
/// tag updates every card carrying it. Returns true if anything changed.
Future<bool> showManageTagsDialog(BuildContext context, Deck deck) async {
  final changed = await showDialog<bool>(
    context: context,
    builder: (_) => _ManageTagsDialog(deck: deck),
  );
  return changed ?? false;
}

class _ManageTagsDialog extends StatefulWidget {
  final Deck deck;
  const _ManageTagsDialog({required this.deck});

  @override
  State<_ManageTagsDialog> createState() => _ManageTagsDialogState();
}

class _ManageTagsDialogState extends State<_ManageTagsDialog> {
  final _newController = TextEditingController();
  final _renameController = TextEditingController();

  /// Tag currently being renamed, if any.
  String? _renaming;
  bool _changed = false;

  Deck get deck => widget.deck;

  @override
  void dispose() {
    _newController.dispose();
    _renameController.dispose();
    super.dispose();
  }

  void _add() {
    final before = deck.tags.length;
    deck.addTag(_newController.text);
    if (deck.tags.length == before) return; // blank or already there
    _newController.clear();
    setState(() => _changed = true);
  }

  void _startRename(String tag) {
    _renameController.text = tag;
    _renameController.selection = TextSelection(
      baseOffset: 0,
      extentOffset: tag.length,
    );
    setState(() => _renaming = tag);
  }

  void _commitRename() {
    final tag = _renaming;
    if (tag == null) return;
    final to = _renameController.text.trim();
    setState(() => _renaming = null);
    if (to.isEmpty || to == tag) return;
    deck.renameTag(tag, to);
    setState(() => _changed = true);
  }

  Future<void> _delete(String tag) async {
    final used = deck.tagUseCount(tag);
    if (used > 0) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Delete “$tag”?'),
          content: Text(
            'It will be removed from $used '
            '${used == 1 ? "card" : "cards"}. The cards stay.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Delete'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }
    deck.removeTag(tag);
    setState(() => _changed = true);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Tags'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Tags belong to this set. Cards can carry any number of them. '
              'A tag\'s color comes from its name, so the same name looks '
              'the same in every set.',
              style: TextStyle(color: SprakTheme.inkSoft, fontSize: 13),
            ),
            const SizedBox(height: 16),
            if (deck.tags.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  'No tags yet — add one below.',
                  style: TextStyle(color: SprakTheme.inkSoft),
                ),
              )
            else
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 320),
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: deck.tags.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 6),
                  itemBuilder: (context, i) => _row(deck.tags[i]),
                ),
              ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 42,
                    child: TextField(
                      controller: _newController,
                      style: const TextStyle(fontSize: 14),
                      decoration: const InputDecoration(
                        isDense: true,
                        hintText: 'New tag (e.g. verb)',
                        contentPadding: EdgeInsets.symmetric(
                            horizontal: 14, vertical: 12),
                      ),
                      onSubmitted: (_) => _add(),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                FilledButton(
                  onPressed: _add,
                  child: const Text('Add'),
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.pop(context, _changed),
          child: const Text('Done'),
        ),
      ],
    );
  }

  Widget _row(String tag) {
    final used = deck.tagUseCount(tag);
    if (_renaming == tag) {
      return SizedBox(
        height: 42,
        child: TextField(
          controller: _renameController,
          autofocus: true,
          style: const TextStyle(fontSize: 14),
          decoration: InputDecoration(
            isDense: true,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            suffixIcon: IconButton(
              icon: const Icon(Icons.check, size: 18),
              color: SprakTheme.fjord,
              tooltip: 'Save',
              onPressed: _commitRename,
            ),
          ),
          onSubmitted: (_) => _commitRename(),
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.only(left: 14, right: 4),
      decoration: BoxDecoration(
        color: SprakTheme.panel,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: SprakTheme.line),
      ),
      child: Row(
        children: [
          Container(
            width: 9,
            height: 9,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: SprakTheme.tagColor(tag),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              tag,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: SprakTheme.tagColor(tag),
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Text(
            used == 0 ? 'unused' : '$used ${used == 1 ? "card" : "cards"}',
            style: TextStyle(color: SprakTheme.inkSoft, fontSize: 12),
          ),
          IconButton(
            icon: const Icon(Icons.edit_outlined, size: 18),
            color: SprakTheme.inkSoft,
            tooltip: 'Rename tag',
            onPressed: () => _startRename(tag),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline, size: 18),
            color: SprakTheme.inkSoft,
            tooltip: 'Delete tag',
            onPressed: () => _delete(tag),
          ),
        ],
      ),
    );
  }
}
