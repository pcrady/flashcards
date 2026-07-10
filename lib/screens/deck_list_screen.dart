import 'package:flutter/material.dart';

import '../models.dart';
import '../storage.dart';
import '../theme.dart';
import '../widgets/rename_deck_dialog.dart';
import 'deck_detail_screen.dart';
import 'quiz_screen.dart';
import 'settings_screen.dart';

class DeckListScreen extends StatelessWidget {
  final DeckStore store;
  const DeckListScreen({super.key, required this.store});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Padding(
          padding: EdgeInsets.only(left: 8),
          child: AuroraWordmark(size: 28),
        ),
        toolbarHeight: 68,
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Settings',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            ),
          ),
          const SizedBox(width: 12),
        ],
      ),
      body: ListenableBuilder(
        listenable: store,
        builder: (context, _) {
          if (!store.loaded) {
            return const Center(child: CircularProgressIndicator());
          }
          if (store.decks.isEmpty) {
            return _EmptyState(onCreate: () => _createDeck(context));
          }
          return Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1100),
              child: GridView(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 96),
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 340,
                  mainAxisSpacing: 16,
                  crossAxisSpacing: 16,
                  // Fixed tile height so card content never overflows as
                  // the window resizes.
                  mainAxisExtent: 195,
                ),
                children: [
                  for (final deck in store.decks)
                    _DeckCard(
                      deck: deck,
                      onOpen: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) =>
                              DeckDetailScreen(store: store, deck: deck),
                        ),
                      ),
                      onLearn: deck.cards.isEmpty
                          ? null
                          : () => Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) =>
                                      QuizScreen(store: store, deck: deck),
                                ),
                              ),
                      onRename: () => _renameDeck(context, deck),
                      onDelete: () => _confirmDelete(context, deck),
                    ),
                ],
              ),
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.add),
        label: const Text('New set'),
        onPressed: () => _createDeck(context),
      ),
    );
  }

  Future<void> _renameDeck(BuildContext context, Deck deck) async {
    final name = await showRenameDeckDialog(context, deck.name);
    if (name != null) {
      deck.name = name;
      await store.save();
    }
  }

  Future<void> _confirmDelete(BuildContext context, Deck deck) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete “${deck.name}”?'),
        content: Text('This removes the set and its ${deck.cards.length} '
            'cards permanently.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Delete')),
        ],
      ),
    );
    if (ok == true) await store.deleteDeck(deck);
  }

  Future<void> _createDeck(BuildContext context) async {
    final nameController = TextEditingController();
    String native = 'English';
    String target = 'Russian';

    final created = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('New set'),
          content: SizedBox(
            width: 380,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  autofocus: true,
                  decoration: const InputDecoration(
                    labelText: 'Set name',
                    hintText: 'e.g. Travel phrases',
                  ),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  initialValue: native,
                  decoration: const InputDecoration(labelText: 'I speak'),
                  items: [
                    for (final l in kLanguages)
                      DropdownMenuItem(
                          value: l.name, child: Text('${l.flag}  ${l.name}')),
                  ],
                  onChanged: (v) => setState(() => native = v!),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: target,
                  decoration:
                      const InputDecoration(labelText: 'I am learning'),
                  items: [
                    for (final l in kLanguages)
                      DropdownMenuItem(
                          value: l.name, child: Text('${l.flag}  ${l.name}')),
                  ],
                  onChanged: (v) => setState(() => target = v!),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel')),
            FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Create')),
          ],
        ),
      ),
    );

    if (created == true) {
      final name = nameController.text.trim();
      await store.addDeck(Deck(
        name: name.isEmpty ? '$target basics' : name,
        nativeLanguage: native,
        targetLanguage: target,
      ));
    }
  }
}

class _DeckCard extends StatelessWidget {
  final Deck deck;
  final VoidCallback onOpen;
  final VoidCallback? onLearn;
  final VoidCallback onRename;
  final VoidCallback onDelete;

  const _DeckCard({
    required this.deck,
    required this.onOpen,
    required this.onLearn,
    required this.onRename,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 12, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(flagFor(deck.targetLanguage),
                      style: const TextStyle(fontSize: 30)),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    color: SprakTheme.inkSoft,
                    visualDensity: VisualDensity.compact,
                    constraints:
                        const BoxConstraints(minWidth: 32, minHeight: 32),
                    padding: EdgeInsets.zero,
                    tooltip: 'Rename set',
                    onPressed: onRename,
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline, size: 20),
                    color: SprakTheme.inkSoft,
                    visualDensity: VisualDensity.compact,
                    constraints:
                        const BoxConstraints(minWidth: 32, minHeight: 32),
                    padding: EdgeInsets.zero,
                    tooltip: 'Delete set',
                    onPressed: onDelete,
                  ),
                ],
              ),
              const Spacer(),
              Text(
                deck.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 4),
              Text(
                '${deck.nativeLanguage} → ${deck.targetLanguage}',
                style: TextStyle(color: SprakTheme.inkSoft, fontSize: 13),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: SprakTheme.panel,
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: SprakTheme.line),
                    ),
                    child: Text(
                      '${deck.cards.length} '
                      '${deck.cards.length == 1 ? "card" : "cards"}',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                  const Spacer(),
                  FilledButton.tonalIcon(
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 10),
                    ),
                    icon: const Icon(Icons.school_outlined, size: 18),
                    label: const Text('Learn'),
                    onPressed: onLearn,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final VoidCallback onCreate;
  const _EmptyState({required this.onCreate});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const AuroraWordmark(size: 56),
          const SizedBox(height: 12),
          Text(
            'Collect words. Hear them. Keep them.',
            style: TextStyle(color: SprakTheme.inkSoft, fontSize: 16),
          ),
          const SizedBox(height: 28),
          FilledButton.icon(
            icon: const Icon(Icons.add),
            label: const Text('Create your first set'),
            onPressed: onCreate,
          ),
        ],
      ),
    );
  }
}
