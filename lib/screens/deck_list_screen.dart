import 'package:flutter/material.dart';

import '../models.dart';
import '../storage.dart';
import '../theme.dart';
import '../widgets/learn_mode_dialog.dart';
import '../widgets/mastery.dart';
import '../widgets/rename_deck_dialog.dart';
import 'deck_detail_screen.dart';
import 'settings_screen.dart';

/// Home screen (folder == null) showing folders and unfiled decks, or the
/// contents of one folder. Folders are one level deep.
class DeckListScreen extends StatelessWidget {
  final DeckStore store;
  final Folder? folder;
  const DeckListScreen({super.key, required this.store, this.folder});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: folder == null
            ? const Padding(
                padding: EdgeInsets.only(left: 8),
                child: AuroraWordmark(size: 28),
              )
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.folder_outlined,
                      size: 22, color: SprakTheme.fjord),
                  const SizedBox(width: 10),
                  Flexible(
                    child:
                        Text(folder!.name, overflow: TextOverflow.ellipsis),
                  ),
                ],
              ),
        toolbarHeight: 68,
        actions: [
          if (folder == null)
            IconButton(
              icon: const Icon(Icons.create_new_folder_outlined),
              tooltip: 'New folder',
              onPressed: () => _createFolder(context),
            ),
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
          // Decks whose folder no longer exists surface on the home
          // screen instead of vanishing.
          final folderIds = {for (final f in store.folders) f.id};
          final visibleDecks = folder == null
              ? store.decks
                  .where((d) =>
                      d.folderId == null || !folderIds.contains(d.folderId))
                  .toList()
              : store.decks.where((d) => d.folderId == folder!.id).toList();

          if (folder == null &&
              store.decks.isEmpty &&
              store.folders.isEmpty) {
            return _EmptyState(onCreate: () => _createDeck(context));
          }
          if (folder != null && visibleDecks.isEmpty) {
            return Center(
              child: Text('No sets in this folder yet.',
                  style: TextStyle(color: SprakTheme.inkSoft)),
            );
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
                  if (folder == null)
                    for (final f in store.folders)
                      _FolderCard(
                        folder: f,
                        deckCount: store.decks
                            .where((d) => d.folderId == f.id)
                            .length,
                        onOpen: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) =>
                                DeckListScreen(store: store, folder: f),
                          ),
                        ),
                        onRename: () => _renameFolder(context, f),
                        onDelete: () => _confirmDeleteFolder(context, f),
                      ),
                  for (final deck in visibleDecks)
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
                          : () => startLearning(context, store, deck),
                      onRename: () => _renameDeck(context, deck),
                      onMove: () => _moveDeck(context, deck),
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

  Future<String?> _promptFolderName(BuildContext context,
      {String? current}) async {
    final controller = TextEditingController(text: current ?? '');
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(current == null ? 'New folder' : 'Rename folder'),
        content: SizedBox(
          width: 380,
          child: TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Folder name',
              hintText: 'e.g. Russian',
            ),
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
            child: Text(current == null ? 'Create' : 'Rename'),
          ),
        ],
      ),
    );
    final name = result?.trim();
    if (name == null || name.isEmpty || name == current) return null;
    return name;
  }

  Future<void> _createFolder(BuildContext context) async {
    final name = await _promptFolderName(context);
    if (name != null) await store.addFolder(Folder(name: name));
  }

  Future<void> _renameFolder(BuildContext context, Folder f) async {
    final name = await _promptFolderName(context, current: f.name);
    if (name != null) {
      f.name = name;
      await store.save();
    }
  }

  Future<void> _confirmDeleteFolder(BuildContext context, Folder f) async {
    final count = store.decks.where((d) => d.folderId == f.id).length;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete “${f.name}”?'),
        content: Text(count == 0
            ? 'The folder is empty.'
            : 'Its $count ${count == 1 ? "set moves" : "sets move"} back '
                'to the home screen — nothing is deleted.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Delete folder')),
        ],
      ),
    );
    if (ok == true) await store.deleteFolder(f);
  }

  /// Lets the user file [deck] into a folder, back to the home screen, or
  /// into a brand-new folder.
  Future<void> _moveDeck(BuildContext context, Deck deck) async {
    const newFolderSentinel = '__new__';
    final choice = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text('Move “${deck.name}” to…'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, ''),
            child: Row(
              children: [
                const Icon(Icons.home_outlined, size: 20),
                const SizedBox(width: 12),
                const Text('Home screen'),
                if (deck.folderId == null) ...[
                  const Spacer(),
                  Icon(Icons.check, size: 18, color: SprakTheme.fjord),
                ],
              ],
            ),
          ),
          for (final f in store.folders)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, f.id),
              child: Row(
                children: [
                  const Icon(Icons.folder_outlined, size: 20),
                  const SizedBox(width: 12),
                  Expanded(
                      child: Text(f.name, overflow: TextOverflow.ellipsis)),
                  if (deck.folderId == f.id)
                    Icon(Icons.check, size: 18, color: SprakTheme.fjord),
                ],
              ),
            ),
          const Divider(),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, newFolderSentinel),
            child: const Row(
              children: [
                Icon(Icons.create_new_folder_outlined, size: 20),
                SizedBox(width: 12),
                Text('New folder…'),
              ],
            ),
          ),
        ],
      ),
    );
    if (choice == null || !context.mounted) return;

    String? targetId;
    if (choice == newFolderSentinel) {
      final name = await _promptFolderName(context);
      if (name == null) return;
      final f = Folder(name: name);
      await store.addFolder(f);
      targetId = f.id;
    } else {
      targetId = choice.isEmpty ? null : choice;
    }
    deck.folderId = targetId;
    await store.save();
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
    var kind = DeckKind.language;
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
                SegmentedButton<DeckKind>(
                  segments: [
                    for (final k in DeckKind.values)
                      ButtonSegment(value: k, label: Text(k.label)),
                  ],
                  selected: {kind},
                  onSelectionChanged: (s) =>
                      setState(() => kind = s.first),
                ),
                if (kind == DeckKind.language) ...[
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    initialValue: native,
                    decoration: const InputDecoration(labelText: 'I speak'),
                    items: [
                      for (final l in kLanguages)
                        DropdownMenuItem(
                            value: l.name,
                            child: Text('${l.flag}  ${l.name}')),
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
                            value: l.name,
                            child: Text('${l.flag}  ${l.name}')),
                    ],
                    onChanged: (v) => setState(() => target = v!),
                  ),
                ],
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
      final isLanguage = kind == DeckKind.language;
      await store.addDeck(Deck(
        name: name.isEmpty
            ? '${isLanguage ? target : kind.label} basics'
            : name,
        kind: kind,
        nativeLanguage: isLanguage ? native : 'English',
        targetLanguage: isLanguage ? target : kind.label,
        folderId: folder?.id,
      ));
    }
  }
}

/// Grid tile for a folder on the home screen.
class _FolderCard extends StatelessWidget {
  final Folder folder;
  final int deckCount;
  final VoidCallback onOpen;
  final VoidCallback onRename;
  final VoidCallback onDelete;

  const _FolderCard({
    required this.folder,
    required this.deckCount,
    required this.onOpen,
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
                  Icon(Icons.folder_outlined,
                      size: 30, color: SprakTheme.fjord),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    color: SprakTheme.inkSoft,
                    visualDensity: VisualDensity.compact,
                    constraints:
                        const BoxConstraints(minWidth: 32, minHeight: 32),
                    padding: EdgeInsets.zero,
                    tooltip: 'Rename folder',
                    onPressed: onRename,
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline, size: 20),
                    color: SprakTheme.inkSoft,
                    visualDensity: VisualDensity.compact,
                    constraints:
                        const BoxConstraints(minWidth: 32, minHeight: 32),
                    padding: EdgeInsets.zero,
                    tooltip: 'Delete folder',
                    onPressed: onDelete,
                  ),
                ],
              ),
              const Spacer(),
              Text(
                folder.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 4),
              Text(
                'Folder',
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
                      '$deckCount ${deckCount == 1 ? "set" : "sets"}',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                  const Spacer(),
                  FilledButton.tonalIcon(
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 10),
                    ),
                    icon: const Icon(Icons.folder_open_outlined, size: 18),
                    label: const Text('Open'),
                    onPressed: onOpen,
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

class _DeckCard extends StatelessWidget {
  final Deck deck;
  final VoidCallback onOpen;
  final VoidCallback? onLearn;
  final VoidCallback onRename;
  final VoidCallback onMove;
  final VoidCallback onDelete;

  const _DeckCard({
    required this.deck,
    required this.onOpen,
    required this.onLearn,
    required this.onRename,
    required this.onMove,
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
                  Text(deck.emblem, style: const TextStyle(fontSize: 30)),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.drive_file_move_outlined,
                        size: 18),
                    color: SprakTheme.inkSoft,
                    visualDensity: VisualDensity.compact,
                    constraints:
                        const BoxConstraints(minWidth: 32, minHeight: 32),
                    padding: EdgeInsets.zero,
                    tooltip: 'Move to folder',
                    onPressed: onMove,
                  ),
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
                deck.isLanguage
                    ? '${deck.nativeLanguage} → ${deck.targetLanguage}'
                    : deck.kind.label,
                style: TextStyle(color: SprakTheme.inkSoft, fontSize: 13),
              ),
              const SizedBox(height: 10),
              if (deck.cards.isNotEmpty) ...[
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: MasteryBar(deck, height: 5),
                ),
                const SizedBox(height: 8),
              ],
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
                  if (deck.retention != null) ...[
                    const SizedBox(width: 10),
                    RetentionLabel(deck, fontSize: 12),
                  ],
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
