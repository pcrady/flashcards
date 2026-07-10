import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models.dart';
import '../services/claude_service.dart';
import '../services/llm_service.dart';
import '../services/tts_service.dart';
import '../storage.dart';
import '../theme.dart';
import '../widgets/ai_deck_edit_dialog.dart';
import '../widgets/learn_mode_dialog.dart';
import '../widgets/rename_deck_dialog.dart';

/// Shows a deck's cards and lets the user add new ones. While typing a word
/// in either language, the other field is auto-filled with a translation
/// from Claude after a short pause.
class DeckDetailScreen extends StatefulWidget {
  final DeckStore store;
  final Deck deck;
  const DeckDetailScreen({super.key, required this.store, required this.deck});

  @override
  State<DeckDetailScreen> createState() => _DeckDetailScreenState();
}

enum _SortMode { added, mostMissed }

class _DeckDetailScreenState extends State<DeckDetailScreen> {
  _SortMode _sortMode = _SortMode.added;
  final _nativeController = TextEditingController();
  final _targetController = TextEditingController();
  final _nativeFocus = FocusNode();
  final _targetFocus = FocusNode();
  final _suggestionFocus = FocusNode();

  bool _translating = false;
  String? _translateError;
  int _requestSeq = 0;

  /// Pending translation suggestion, shown as a dropdown the user must
  /// pick (click, or ↓ then Enter) before it lands in the text box.
  String? _suggestion;
  bool _suggestionForTarget = true;

  Deck get deck => widget.deck;

  @override
  void initState() {
    super.initState();
    _nativeController.addListener(() => _onTyped(fromNative: true));
    _targetController.addListener(() => _onTyped(fromNative: false));
  }

  @override
  void dispose() {
    _nativeController.dispose();
    _targetController.dispose();
    _nativeFocus.dispose();
    _targetFocus.dispose();
    _suggestionFocus.dispose();
    super.dispose();
  }

  void _onTyped({required bool fromNative}) {
    // Only react to typing in the focused field, so programmatic fills of
    // the other field don't dismiss things unexpectedly.
    final focused = fromNative ? _nativeFocus.hasFocus : _targetFocus.hasFocus;
    if (!focused) return;

    // Typing invalidates a pending suggestion.
    if (_suggestion != null) setState(() => _suggestion = null);
  }

  /// Enter in a text field: accept a pending suggestion; otherwise
  /// translate when the other side is still empty; otherwise add the card.
  void _onSubmit({required bool fromNative}) {
    if (_translating) return;
    if (_suggestion != null) {
      _acceptSuggestion();
      return;
    }
    final source = fromNative ? _nativeController : _targetController;
    final other = fromNative ? _targetController : _nativeController;
    if (source.text.trim().isNotEmpty && other.text.trim().isEmpty) {
      _translate(fromNative: fromNative);
      // Keep focus in the field so the next Enter accepts the suggestion.
      (fromNative ? _nativeFocus : _targetFocus).requestFocus();
      return;
    }
    _addCard();
  }

  Future<void> _translate({required bool fromNative}) async {
    final source = fromNative ? _nativeController : _targetController;
    final text = source.text.trim();
    if (text.isEmpty) return;

    final seq = ++_requestSeq;
    setState(() {
      _translating = true;
      _translateError = null;
    });
    try {
      final result = await LlmService.translate(
        text: text,
        from: fromNative ? deck.nativeLanguage : deck.targetLanguage,
        to: fromNative ? deck.targetLanguage : deck.nativeLanguage,
      );
      if (!mounted || seq != _requestSeq) return;
      setState(() {
        _suggestion = result;
        _suggestionForTarget = fromNative;
      });
    } on LlmException catch (e) {
      if (!mounted || seq != _requestSeq) return;
      setState(() => _translateError = e.message);
    } finally {
      if (mounted && seq == _requestSeq) {
        setState(() => _translating = false);
      }
    }
  }

  void _acceptSuggestion() {
    final suggestion = _suggestion;
    if (suggestion == null) return;
    final dest = _suggestionForTarget ? _targetController : _nativeController;
    dest.text = suggestion;
    setState(() => _suggestion = null);
    // Return focus to the field the user was typing in, so Enter adds
    // the card straight away.
    (_suggestionForTarget ? _nativeFocus : _targetFocus).requestFocus();
  }

  void _dismissSuggestion() {
    if (_suggestion == null) return;
    setState(() => _suggestion = null);
    (_suggestionForTarget ? _nativeFocus : _targetFocus).requestFocus();
  }

  /// Intercepts ↓ / Esc anywhere in the add-card panel so the suggestion
  /// dropdown is keyboard-reachable from the text fields.
  KeyEventResult _handlePanelKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent || _suggestion == null) {
      return KeyEventResult.ignored;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      _suggestionFocus.requestFocus();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      _dismissSuggestion();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  Future<void> _addCard() async {
    final native = _nativeController.text.trim();
    final target = _targetController.text.trim();
    if (native.isEmpty || target.isEmpty) return;

    deck.cards.add(CardItem(native: native, target: target));
    await widget.store.save();
    _requestSeq++; // invalidate any in-flight translation
    _nativeController.clear();
    _targetController.clear();
    setState(() {
      _translateError = null;
      _suggestion = null;
    });
    _nativeFocus.requestFocus();
  }

  Future<void> _renameDeck() async {
    final name = await showRenameDeckDialog(context, deck.name);
    if (name != null) {
      deck.name = name;
      await widget.store.save();
      if (mounted) setState(() {});
    }
  }

  /// Cards in display order for the current sort mode. Sorting is applied
  /// to a copy — the stored order ("as added") is never mutated.
  List<CardItem> get _sortedCards {
    if (_sortMode == _SortMode.added) return deck.cards;
    return List.of(deck.cards)
      ..sort((a, b) {
        final byWrong = b.timesWrong.compareTo(a.timesWrong);
        if (byWrong != 0) return byWrong;
        return a.timesCorrect.compareTo(b.timesCorrect);
      });
  }

  String _norm(String s) => s.toLowerCase().trim();

  Future<void> _openAiEdit() async {
    final plan = await showDialog<DeckEditPlan>(
      context: context,
      builder: (_) => AiDeckEditDialog(deck: deck),
    );
    if (plan == null) return;

    var removed = 0;
    for (final target in plan.removals) {
      final before = deck.cards.length;
      deck.cards.removeWhere((c) => _norm(c.target) == _norm(target));
      removed += before - deck.cards.length;
    }
    var added = 0;
    for (final a in plan.additions) {
      final duplicate = deck.cards.any((c) =>
          _norm(c.target) == _norm(a.target) &&
          _norm(c.native) == _norm(a.native));
      if (!duplicate) {
        deck.cards.add(CardItem(native: a.native, target: a.target));
        added++;
      }
    }
    await widget.store.save();
    if (!mounted) return;
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text([
          if (added > 0) 'Added $added ${added == 1 ? "card" : "cards"}',
          if (removed > 0)
            'removed $removed ${removed == 1 ? "card" : "cards"}',
          if (added == 0 && removed == 0) 'No changes applied',
        ].join(', ')),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: InkWell(
          onTap: _renameDeck,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(flagFor(deck.targetLanguage),
                    style: const TextStyle(fontSize: 22)),
                const SizedBox(width: 10),
                Flexible(
                  child: Text(deck.name, overflow: TextOverflow.ellipsis),
                ),
                const SizedBox(width: 8),
                Icon(Icons.edit_outlined,
                    size: 16, color: SprakTheme.inkSoft),
              ],
            ),
          ),
        ),
        actions: [
          FilledButton.tonalIcon(
            icon: const Icon(Icons.auto_awesome, size: 18),
            label: const Text('Edit with AI'),
            onPressed: _openAiEdit,
          ),
          const SizedBox(width: 10),
          FilledButton.tonalIcon(
            icon: const Icon(Icons.school_outlined, size: 18),
            label: const Text('Learn'),
            onPressed: deck.cards.isEmpty
                ? null
                : () => startLearning(context, widget.store, deck),
          ),
          const SizedBox(width: 16),
        ],
      ),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 860),
          child: Column(
            children: [
              // --- Add-card panel with auto-translation ---
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
                child: Card(
                  child: Focus(
                    canRequestFocus: false,
                    onKeyEvent: _handlePanelKey,
                    child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Add a word or phrase',
                            style: Theme.of(context).textTheme.titleLarge),
                        const SizedBox(height: 4),
                        Text(
                          'Type in either language and press Enter to '
                          'translate. Enter again accepts the suggestion, '
                          'and once more adds the card.',
                          style: TextStyle(
                              color: SprakTheme.inkSoft, fontSize: 13),
                        ),
                        const SizedBox(height: 16),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _nativeController,
                                focusNode: _nativeFocus,
                                decoration: InputDecoration(
                                  labelText: deck.nativeLanguage,
                                ),
                                onSubmitted: (_) =>
                                    _onSubmit(fromNative: true),
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 14),
                              child: _translating
                                  ? const SizedBox(
                                      width: 22,
                                      height: 22,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2.5),
                                    )
                                  : Icon(Icons.swap_horiz,
                                      color: SprakTheme.inkSoft),
                            ),
                            Expanded(
                              child: TextField(
                                controller: _targetController,
                                focusNode: _targetFocus,
                                decoration: InputDecoration(
                                  labelText: deck.targetLanguage,
                                ),
                                onSubmitted: (_) =>
                                    _onSubmit(fromNative: false),
                              ),
                            ),
                            const SizedBox(width: 14),
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: FilledButton.icon(
                                icon: const Icon(Icons.add),
                                label: const Text('Add'),
                                onPressed: _addCard,
                              ),
                            ),
                          ],
                        ),
                        if (_suggestion != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 10),
                            child: Material(
                              color: SprakTheme.panel,
                              borderRadius: BorderRadius.circular(12),
                              child: InkWell(
                                focusNode: _suggestionFocus,
                                borderRadius: BorderRadius.circular(12),
                                focusColor:
                                    SprakTheme.fjord.withValues(alpha: 0.15),
                                onTap: _acceptSuggestion,
                                child: Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 14, vertical: 10),
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(12),
                                    border:
                                        Border.all(color: SprakTheme.line),
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(Icons.subdirectory_arrow_right,
                                          size: 18,
                                          color: SprakTheme.fjord),
                                      const SizedBox(width: 10),
                                      Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            _suggestionForTarget
                                                ? deck.targetLanguage
                                                : deck.nativeLanguage,
                                            style: TextStyle(
                                                color: SprakTheme.inkSoft,
                                                fontSize: 11,
                                                letterSpacing: 0.5),
                                          ),
                                          Text(_suggestion!,
                                              style: SprakTheme.vocab(
                                                  size: 18)),
                                        ],
                                      ),
                                      const Spacer(),
                                      Text(
                                        '⏎ to insert',
                                        style: TextStyle(
                                            color: SprakTheme.inkSoft,
                                            fontSize: 12),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        if (_translateError != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(_translateError!,
                                style: TextStyle(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .error)),
                          ),
                      ],
                    ),
                    ),
                  ),
                ),
              ),
              // --- Sort bar ---
              if (deck.cards.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
                  child: Row(
                    children: [
                      Text(
                        '${deck.cards.length} '
                        '${deck.cards.length == 1 ? "card" : "cards"}',
                        style: TextStyle(
                            color: SprakTheme.inkSoft, fontSize: 13),
                      ),
                      const Spacer(),
                      PopupMenuButton<_SortMode>(
                        initialValue: _sortMode,
                        onSelected: (v) => setState(() => _sortMode = v),
                        color: SprakTheme.surface,
                        itemBuilder: (context) => const [
                          PopupMenuItem(
                            value: _SortMode.added,
                            child: Text('As added'),
                          ),
                          PopupMenuItem(
                            value: _SortMode.mostMissed,
                            child: Text('Most missed first'),
                          ),
                        ],
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.sort,
                                size: 18, color: SprakTheme.inkSoft),
                            const SizedBox(width: 6),
                            Text(
                              _sortMode == _SortMode.added
                                  ? 'Sort: As added'
                                  : 'Sort: Most missed',
                              style: TextStyle(
                                  color: SprakTheme.inkSoft, fontSize: 13),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              // --- Card list ---
              Expanded(
                child: deck.cards.isEmpty
                    ? Center(
                        child: Text('No cards in this set yet.',
                            style: TextStyle(color: SprakTheme.inkSoft)),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                        itemCount: deck.cards.length,
                        separatorBuilder: (_, i) =>
                            const SizedBox(height: 8),
                        itemBuilder: (context, i) {
                          final card = _sortedCards[i];
                          return Card(
                            child: ListTile(
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 4),
                              leading: IconButton(
                                icon: const Icon(Icons.volume_up_outlined),
                                color: SprakTheme.fjord,
                                tooltip: 'Play audio',
                                onPressed: () => TtsService().speak(
                                    card.target,
                                    ttsLocaleFor(deck.targetLanguage)),
                              ),
                              title: Text(card.target,
                                  style: SprakTheme.vocab(size: 20)),
                              subtitle: Padding(
                                padding: const EdgeInsets.only(top: 2),
                                child: Text(card.native,
                                    style: TextStyle(
                                        color: SprakTheme.inkSoft)),
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  _StatChip(
                                    icon: Icons.check,
                                    color: SprakTheme.success,
                                    count: card.timesCorrect,
                                    tooltip: 'Answered correctly '
                                        '${card.timesCorrect} times',
                                  ),
                                  const SizedBox(width: 6),
                                  _StatChip(
                                    icon: Icons.close,
                                    color: SprakTheme.danger,
                                    count: card.timesWrong,
                                    tooltip: 'Answered incorrectly '
                                        '${card.timesWrong} times',
                                  ),
                                  const SizedBox(width: 10),
                                  IconButton(
                                    icon: const Icon(Icons.delete_outline,
                                        size: 20),
                                    color: SprakTheme.inkSoft,
                                    tooltip: 'Remove card',
                                    onPressed: () async {
                                      deck.cards.removeWhere(
                                          (c) => c.id == card.id);
                                      await widget.store.save();
                                      setState(() {});
                                    },
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Small ✓/✗ counter pill shown next to each card. Muted while the count
/// is still zero.
class _StatChip extends StatelessWidget {
  final IconData icon;
  final Color color;
  final int count;
  final String tooltip;

  const _StatChip({
    required this.icon,
    required this.color,
    required this.count,
    required this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    final active = count > 0;
    final c = active ? color : SprakTheme.inkSoft;
    return Tooltip(
      message: tooltip,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: c.withValues(alpha: active ? 0.12 : 0.06),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: c),
            const SizedBox(width: 4),
            Text(
              '$count',
              style: TextStyle(
                color: c,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
