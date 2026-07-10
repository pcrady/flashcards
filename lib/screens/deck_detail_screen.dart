import 'dart:async';

import 'package:flutter/material.dart';

import '../models.dart';
import '../services/claude_service.dart';
import '../services/llm_service.dart';
import '../services/tts_service.dart';
import '../storage.dart';
import '../theme.dart';
import '../widgets/ai_deck_edit_dialog.dart';
import '../widgets/rename_deck_dialog.dart';
import 'quiz_screen.dart';

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

class _DeckDetailScreenState extends State<DeckDetailScreen> {
  final _nativeController = TextEditingController();
  final _targetController = TextEditingController();
  final _nativeFocus = FocusNode();
  final _targetFocus = FocusNode();

  Timer? _debounce;
  bool _translating = false;
  String? _translateError;
  int _requestSeq = 0;

  Deck get deck => widget.deck;

  @override
  void initState() {
    super.initState();
    _nativeController.addListener(() => _onTyped(fromNative: true));
    _targetController.addListener(() => _onTyped(fromNative: false));
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _nativeController.dispose();
    _targetController.dispose();
    _nativeFocus.dispose();
    _targetFocus.dispose();
    super.dispose();
  }

  void _onTyped({required bool fromNative}) {
    // Only react to typing in the focused field, so programmatic fills of
    // the other field don't trigger a translation loop.
    final focused = fromNative ? _nativeFocus.hasFocus : _targetFocus.hasFocus;
    if (!focused) return;

    _debounce?.cancel();
    final text = (fromNative ? _nativeController : _targetController).text;
    if (text.trim().length < 2) return;

    _debounce = Timer(const Duration(milliseconds: 900), () {
      _translate(fromNative: fromNative);
    });
  }

  Future<void> _translate({required bool fromNative}) async {
    final source = fromNative ? _nativeController : _targetController;
    final dest = fromNative ? _targetController : _nativeController;
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
      dest.text = result;
    } on LlmException catch (e) {
      if (!mounted || seq != _requestSeq) return;
      setState(() => _translateError = e.message);
    } finally {
      if (mounted && seq == _requestSeq) {
        setState(() => _translating = false);
      }
    }
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
    setState(() => _translateError = null);
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
                : () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) =>
                            QuizScreen(store: widget.store, deck: deck),
                      ),
                    ),
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
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Add a word or phrase',
                            style: Theme.of(context).textTheme.titleLarge),
                        const SizedBox(height: 4),
                        Text(
                          'Type in either language — the other side is '
                          'translated automatically.',
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
                                onSubmitted: (_) => _addCard(),
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
                                onSubmitted: (_) => _addCard(),
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
                          final card = deck.cards[i];
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
                              trailing: IconButton(
                                icon: const Icon(Icons.delete_outline,
                                    size: 20),
                                color: SprakTheme.inkSoft,
                                tooltip: 'Remove card',
                                onPressed: () async {
                                  deck.cards.removeAt(i);
                                  await widget.store.save();
                                  setState(() {});
                                },
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
