import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models.dart';
import '../services/claude_service.dart';
import '../services/llm_service.dart';
import '../services/tts_service.dart';
import '../storage.dart';
import '../theme.dart';
import '../widgets/ai_deck_edit_dialog.dart';
import '../widgets/edit_card_dialog.dart';
import '../widgets/learn_mode_dialog.dart';
import '../widgets/mastery.dart';
import '../widgets/rename_deck_dialog.dart';
import '../widgets/tex_text.dart';

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
  final _baseFormFocus = FocusNode();
  final _translationFocus = FocusNode();

  bool _translating = false;
  String? _translateError;
  int _requestSeq = 0;

  /// Pending suggestions, shown as dropdowns the user must pick (click, or
  /// ↓ then Enter) before they land in the text boxes: when the typed word
  /// was inflected, its basic dictionary form appears under the field the
  /// user typed in, and the translation under the other field.
  String? _baseFormSuggestion;
  String? _translationSuggestion;
  bool _suggestionForTarget = true;

  /// Guards the controller listeners while a suggestion is being written
  /// into a field programmatically, so it doesn't clear the other one.
  bool _applyingSuggestion = false;

  /// Last seen text per field, so the controller listeners (which also
  /// fire on selection/focus changes) can tell real edits apart.
  String _lastNativeText = '';
  String _lastTargetText = '';

  bool get _hasSuggestion =>
      _baseFormSuggestion != null || _translationSuggestion != null;

  /// The field the user typed the word into (the one a dictionary-form
  /// suggestion applies to).
  TextEditingController get _sourceController =>
      _suggestionForTarget ? _nativeController : _targetController;
  TextEditingController get _destController =>
      _suggestionForTarget ? _targetController : _nativeController;
  FocusNode get _sourceFocus =>
      _suggestionForTarget ? _nativeFocus : _targetFocus;

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
    _baseFormFocus.dispose();
    _translationFocus.dispose();
    super.dispose();
  }

  void _onTyped({required bool fromNative}) {
    // The controller also notifies on selection/focus changes — only a
    // real text change counts as typing.
    final text =
        (fromNative ? _nativeController : _targetController).text;
    final changed = fromNative
        ? text != _lastNativeText
        : text != _lastTargetText;
    if (fromNative) {
      _lastNativeText = text;
    } else {
      _lastTargetText = text;
    }
    if (!changed || _applyingSuggestion) return;
    // Only react to typing in the focused field, so programmatic fills of
    // the other field don't dismiss things unexpectedly.
    final focused = fromNative ? _nativeFocus.hasFocus : _targetFocus.hasFocus;
    if (!focused) return;

    // Typing invalidates pending suggestions.
    if (_hasSuggestion) {
      setState(() {
        _baseFormSuggestion = null;
        _translationSuggestion = null;
      });
    }
  }

  /// Enter in a text field: accept a pending suggestion; otherwise
  /// translate when the other side is still empty; otherwise add the card.
  void _onSubmit({required bool fromNative}) {
    if (_translating) {
      // Ignore the Enter but make sure the field keeps focus so the next
      // press still lands here.
      (fromNative ? _nativeFocus : _targetFocus).requestFocus();
      return;
    }
    if (_hasSuggestion) {
      _acceptSuggestions();
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
      final String? baseForm;
      final String suggestion;
      if (deck.isLanguage) {
        final result = await LlmService.suggestCard(
          text: text,
          from: fromNative ? deck.nativeLanguage : deck.targetLanguage,
          to: fromNative ? deck.targetLanguage : deck.nativeLanguage,
        );
        baseForm = result.baseForm;
        suggestion = result.translation;
      } else {
        // Native side holds the answer, target side the question.
        baseForm = null;
        suggestion = await LlmService.completeCard(
          text: text,
          fromQuestion: !fromNative,
          subject: deck.kind.label,
        );
      }
      if (!mounted || seq != _requestSeq) return;
      setState(() {
        _baseFormSuggestion = baseForm;
        _translationSuggestion = suggestion;
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

  void _fill(TextEditingController dest, String text) {
    _applyingSuggestion = true;
    dest.text = text;
    _applyingSuggestion = false;
  }

  /// Enter accepts everything pending: the dictionary form replaces what
  /// the user typed and the translation fills the other box.
  void _acceptSuggestions() {
    final base = _baseFormSuggestion;
    final translation = _translationSuggestion;
    if (base == null && translation == null) return;
    setState(() {
      _baseFormSuggestion = null;
      _translationSuggestion = null;
    });
    if (base != null) _fill(_sourceController, base);
    if (translation != null) _fill(_destController, translation);
    // Return focus to the field the user was typing in, so Enter adds
    // the card straight away.
    _sourceFocus.requestFocus();
  }

  void _acceptBaseForm() {
    final base = _baseFormSuggestion;
    if (base == null) return;
    setState(() => _baseFormSuggestion = null);
    _fill(_sourceController, base);
    _sourceFocus.requestFocus();
  }

  void _acceptTranslation() {
    final translation = _translationSuggestion;
    if (translation == null) return;
    setState(() => _translationSuggestion = null);
    _fill(_destController, translation);
    _sourceFocus.requestFocus();
  }

  void _dismissSuggestions() {
    if (!_hasSuggestion) return;
    setState(() {
      _baseFormSuggestion = null;
      _translationSuggestion = null;
    });
    _sourceFocus.requestFocus();
  }

  /// Intercepts ↓ / Esc anywhere in the add-card panel so the suggestion
  /// dropdowns are keyboard-reachable from the text fields.
  KeyEventResult _handlePanelKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent || !_hasSuggestion) {
      return KeyEventResult.ignored;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      (_baseFormSuggestion != null ? _baseFormFocus : _translationFocus)
          .requestFocus();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      _dismissSuggestions();
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
      _baseFormSuggestion = null;
      _translationSuggestion = null;
    });
    _nativeFocus.requestFocus();
  }

  Future<void> _editCard(CardItem card) async {
    final result = await showEditCardDialog(
      context,
      card: card,
      nativeLanguage: deck.nativeLabel,
      targetLanguage: deck.targetLabel,
    );
    if (result == null) return;
    card.native = result.native;
    card.target = result.target;
    await widget.store.save();
    if (mounted) setState(() {});
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

  /// The suggestion dropdown(s) that belong under one of the two text
  /// fields: the dictionary form goes under the field the user typed in,
  /// the translation under the other one.
  List<Widget> _suggestionsUnder({required bool isNative}) {
    final typedHere = isNative == _suggestionForTarget;
    final suggestion =
        typedHere ? _baseFormSuggestion : _translationSuggestion;
    if (suggestion == null) return const [];
    return [
      Padding(
        padding: const EdgeInsets.only(top: 8),
        child: _SuggestionBox(
          label: typedHere
              ? 'Dictionary form'
              : (isNative ? deck.nativeLabel : deck.targetLabel),
          value: suggestion,
          icon: typedHere
              ? Icons.menu_book_outlined
              : Icons.subdirectory_arrow_right,
          focusNode: typedHere ? _baseFormFocus : _translationFocus,
          onTap: typedHere ? _acceptBaseForm : _acceptTranslation,
        ),
      ),
    ];
  }

  /// Colored-dot legend for the mastery bar, non-empty buckets only.
  Widget _buildMasteryLegend() {
    final counts = deck.masteryCounts;
    return Wrap(
      spacing: 14,
      runSpacing: 4,
      children: [
        for (final m in masteryOrder)
          if (counts[m]! > 0)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: masteryColor(m),
                  ),
                ),
                const SizedBox(width: 5),
                Text(
                  '${counts[m]} ${masteryLabel(m).toLowerCase()}',
                  style: TextStyle(color: SprakTheme.inkSoft, fontSize: 12),
                ),
              ],
            ),
      ],
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
                Text(deck.emblem, style: const TextStyle(fontSize: 22)),
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
                          deck.isLanguage
                              ? 'Type in either language and press Enter to '
                                  'translate. If you typed an inflected '
                                  'form, the dictionary form is suggested '
                                  'under your field. Enter accepts the '
                                  'suggestions, and once more adds the card.'
                              : 'Type either side and press Enter to have '
                                  'AI fill in the other. Use \$…\$ for '
                                  'LaTeX. Enter accepts the suggestion, and '
                                  'once more adds the card.',
                          style: TextStyle(
                              color: SprakTheme.inkSoft, fontSize: 13),
                        ),
                        const SizedBox(height: 16),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.stretch,
                                children: [
                                  TextField(
                                    controller: _nativeController,
                                    focusNode: _nativeFocus,
                                    decoration: InputDecoration(
                                      labelText: deck.nativeLabel,
                                    ),
                                    // Keep focus on submit — the default
                                    // behavior unfocuses the field, which
                                    // swallows rapid Enter presses.
                                    onEditingComplete: () {},
                                    onSubmitted: (_) =>
                                        _onSubmit(fromNative: true),
                                  ),
                                  ..._suggestionsUnder(isNative: true),
                                ],
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
                              child: Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.stretch,
                                children: [
                                  TextField(
                                    controller: _targetController,
                                    focusNode: _targetFocus,
                                    decoration: InputDecoration(
                                      labelText: deck.targetLabel,
                                    ),
                                    onEditingComplete: () {},
                                    onSubmitted: (_) =>
                                        _onSubmit(fromNative: false),
                                  ),
                                  ..._suggestionsUnder(isNative: false),
                                ],
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
              ),
              // --- Retention stats ---
              if (deck.cards.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 10),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            MasteryBar(deck, height: 7),
                            const SizedBox(height: 6),
                            _buildMasteryLegend(),
                          ],
                        ),
                      ),
                      const SizedBox(width: 20),
                      RetentionLabel(deck),
                    ],
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
                              leading: deck.isLanguage
                                  ? IconButton(
                                      icon: const Icon(
                                          Icons.volume_up_outlined),
                                      color: SprakTheme.fjord,
                                      tooltip: 'Play audio',
                                      onPressed: () => TtsService().speak(
                                          card.target,
                                          ttsLocaleFor(
                                              deck.targetLanguage)),
                                    )
                                  : null,
                              title: TexText(card.target,
                                  style: SprakTheme.vocab(size: 20)),
                              subtitle: Padding(
                                padding: const EdgeInsets.only(top: 2),
                                child: TexText(card.native,
                                    style: TextStyle(
                                        color: SprakTheme.inkSoft)),
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Tooltip(
                                    message: masteryTooltip(card),
                                    child: Container(
                                      width: 9,
                                      height: 9,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: masteryColor(card.mastery),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
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
                                    icon: const Icon(Icons.edit_outlined,
                                        size: 20),
                                    color: SprakTheme.inkSoft,
                                    tooltip: 'Edit card',
                                    onPressed: () => _editCard(card),
                                  ),
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

/// One clickable suggestion dropdown shown under a text field in the
/// add-card panel.
class _SuggestionBox extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final FocusNode focusNode;
  final VoidCallback onTap;

  const _SuggestionBox({
    required this.label,
    required this.value,
    required this.icon,
    required this.focusNode,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: SprakTheme.panel,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        focusNode: focusNode,
        borderRadius: BorderRadius.circular(12),
        focusColor: SprakTheme.fjord.withValues(alpha: 0.15),
        onTap: onTap,
        child: Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: SprakTheme.line),
          ),
          child: Row(
            children: [
              Icon(icon, size: 18, color: SprakTheme.fjord),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                          color: SprakTheme.inkSoft,
                          fontSize: 11,
                          letterSpacing: 0.5),
                    ),
                    TexText(value, style: SprakTheme.vocab(size: 17)),
                  ],
                ),
              ),
              Text(
                '⏎ to insert',
                style:
                    TextStyle(color: SprakTheme.inkSoft, fontSize: 12),
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
