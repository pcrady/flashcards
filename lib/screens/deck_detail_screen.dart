import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models.dart';
import '../services/claude_service.dart';
import '../services/llm_service.dart';
import '../services/tts_service.dart';
import '../storage.dart';
import '../theme.dart';
import '../widgets/ai_deck_edit_dialog.dart';
import '../widgets/card_note.dart';
import '../widgets/edit_card_dialog.dart';
import '../widgets/learn_mode_dialog.dart';
import '../widgets/manage_tags_dialog.dart';
import '../widgets/mastery.dart';
import '../widgets/rename_deck_dialog.dart';
import '../widgets/tag_chips.dart';
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

/// The tags a model proposed for a card being added, reduced to what is
/// worth showing: blanks and repeats go, a tag the deck already defines
/// takes the deck's own spelling, and anything [alreadyApplied] to the card
/// is dropped. Tags the deck has never seen are kept — accepting them adds
/// them to the deck.
List<String> pendingCardTags(
  Deck deck,
  List<String> suggested,
  List<String> alreadyApplied,
) {
  final pending = <String>[];
  for (final raw in suggested) {
    final name = deck.findTag(raw) ?? raw.trim();
    if (name.isEmpty || alreadyApplied.contains(name)) continue;
    if (pending.any((t) => t.toLowerCase() == name.toLowerCase())) continue;
    pending.add(name);
  }
  return pending;
}

/// The carried-over tags the model reported as wrong for the card being
/// added, kept to the ones actually on it (in the card's own spelling) and
/// never to one the model also proposed.
List<String> staleCardTags(
  List<String> flagged,
  List<String> suggested,
  List<String> applied,
) {
  final stale = <String>[];
  for (final raw in flagged) {
    final name = raw.trim();
    final match = applied.firstWhere(
      (t) => t.toLowerCase() == name.toLowerCase(),
      orElse: () => '',
    );
    if (match.isEmpty || stale.contains(match)) continue;
    if (suggested.any((t) => t.toLowerCase() == match.toLowerCase())) continue;
    stale.add(match);
  }
  return stale;
}

/// Puts [suggested] on the card being added, registering any tag new to
/// [deck] in its tag list (so it becomes pickable for later cards too), and
/// takes [stale] off it — the tags held over from the previous card that do
/// not fit this one. The deck keeps defining a stale tag; only this card
/// loses it. Returns the card's resulting tag list; [deck] is modified in
/// place.
List<String> applySuggestedTags(
  Deck deck,
  List<String> suggested,
  List<String> applied, {
  List<String> stale = const [],
}) {
  final next = [
    for (final t in applied)
      if (!stale.any((s) => s.toLowerCase() == t.toLowerCase())) t,
  ];
  for (final raw in suggested) {
    final name = deck.addTag(raw);
    if (name != null && !next.contains(name)) next.add(name);
  }
  return next;
}

class _DeckDetailScreenState extends State<DeckDetailScreen> {
  _SortMode _sortMode = _SortMode.added;
  final _nativeController = TextEditingController();
  final _targetController = TextEditingController();
  final _notesController = TextEditingController();
  final _nativeFocus = FocusNode();
  final _targetFocus = FocusNode();
  final _baseFormFocus = FocusNode();
  final _translationFocus = FocusNode();
  final _tagsFocus = FocusNode();
  final _searchController = TextEditingController();
  final _searchFocus = FocusNode();

  bool _translating = false;
  String? _translateError;
  int _requestSeq = 0;

  /// Tags applied to the next card added. Kept between adds, since cards
  /// of the same kind are usually entered in a run.
  List<String> _newCardTags = [];

  /// Tags the card list is narrowed to. Empty means every card; with tags
  /// picked, a card shows if it carries any of them. Also seeds the study
  /// dialog's filter, so "show me just the verbs" carries into a session.
  List<String> _filterTags = [];

  /// Pending suggestions, shown as dropdowns the user must pick (click, or
  /// ↓ then Enter) before they land in the text boxes: when the typed word
  /// was inflected, its basic dictionary form appears under the field the
  /// user typed in, and the translation under the other field.
  String? _baseFormSuggestion;
  String? _translationSuggestion;
  bool _suggestionForTarget = true;

  /// Tags the model proposed for the card being typed, not yet applied.
  /// Some may not be in the deck's tag list — accepting adds them to it.
  List<String> _tagSuggestions = [];

  /// Tags already on the card being typed that the model judged wrong for
  /// it — leftovers from the previous add (see [_newCardTags]). Accepting
  /// the suggestion takes them off the card.
  List<String> _staleTags = [];

  /// Guards the controller listeners while a suggestion is being written
  /// into a field programmatically, so it doesn't clear the other one.
  bool _applyingSuggestion = false;

  /// Last seen text per field, so the controller listeners (which also
  /// fire on selection/focus changes) can tell real edits apart.
  String _lastNativeText = '';
  String _lastTargetText = '';

  bool get _hasSuggestion =>
      _baseFormSuggestion != null ||
      _translationSuggestion != null ||
      _tagSuggestions.isNotEmpty ||
      _staleTags.isNotEmpty;

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
    _searchController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _nativeController.dispose();
    _targetController.dispose();
    _notesController.dispose();
    _nativeFocus.dispose();
    _targetFocus.dispose();
    _baseFormFocus.dispose();
    _translationFocus.dispose();
    _tagsFocus.dispose();
    _searchController.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  /// Focuses (and selects the contents of) the search field, for the
  /// Cmd/Ctrl+F shortcut.
  void _focusSearch() {
    _searchFocus.requestFocus();
    _searchController.selection = TextSelection(
      baseOffset: 0,
      extentOffset: _searchController.text.length,
    );
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
        _tagSuggestions = [];
        _staleTags = [];
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
      final CardSuggestion result;
      if (deck.isLanguage) {
        result = await LlmService.suggestCard(
          text: text,
          from: fromNative ? deck.nativeLanguage : deck.targetLanguage,
          to: fromNative ? deck.targetLanguage : deck.nativeLanguage,
          existingTags: deck.tags,
          appliedTags: _newCardTags,
        );
      } else {
        // Native side holds the answer, target side the question.
        result = await LlmService.completeCard(
          text: text,
          fromQuestion: !fromNative,
          subject: deck.kind.label,
          existingTags: deck.tags,
          appliedTags: _newCardTags,
        );
      }
      if (!mounted || seq != _requestSeq) return;
      setState(() {
        _baseFormSuggestion = result.baseForm;
        _translationSuggestion = result.otherSide;
        _tagSuggestions = pendingCardTags(deck, result.tags, _newCardTags);
        _staleTags =
            staleCardTags(result.removeTags, result.tags, _newCardTags);
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
  /// the user typed, the translation fills the other box, and the proposed
  /// tags are applied to the card.
  void _acceptSuggestions() {
    final base = _baseFormSuggestion;
    final translation = _translationSuggestion;
    if (!_hasSuggestion) return;
    setState(() {
      _baseFormSuggestion = null;
      _translationSuggestion = null;
    });
    if (base != null) _fill(_sourceController, base);
    if (translation != null) _fill(_destController, translation);
    _acceptTags();
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

  /// Applies the suggested tags to the card being added, adding the ones
  /// the deck does not define yet to its tag list, and drops the ones held
  /// over from the previous card that do not fit this one.
  Future<void> _acceptTags() async {
    if (_tagSuggestions.isEmpty && _staleTags.isEmpty) return;
    final applied = applySuggestedTags(
      deck,
      _tagSuggestions,
      _newCardTags,
      stale: _staleTags,
    );
    setState(() {
      _tagSuggestions = [];
      _staleTags = [];
      _newCardTags = applied;
    });
    _sourceFocus.requestFocus();
    // The deck's own tag list may have grown, so persist it.
    await widget.store.save();
  }

  void _dismissSuggestions() {
    if (!_hasSuggestion) return;
    setState(() {
      _baseFormSuggestion = null;
      _translationSuggestion = null;
      _tagSuggestions = [];
      _staleTags = [];
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
      (_baseFormSuggestion != null
              ? _baseFormFocus
              : _translationSuggestion != null
                  ? _translationFocus
                  : _tagsFocus)
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

    deck.cards.add(
      CardItem(
        native: native,
        target: target,
        notes: _notesController.text.trim(),
        tags: List.of(_newCardTags),
      ),
    );
    await widget.store.save();
    _requestSeq++; // invalidate any in-flight translation
    _nativeController.clear();
    _targetController.clear();
    _notesController.clear();
    setState(() {
      _translateError = null;
      _baseFormSuggestion = null;
      _translationSuggestion = null;
      _tagSuggestions = [];
      _staleTags = [];
    });
    // Back to the panel's first (left) field.
    (deck.isLanguage ? _nativeFocus : _targetFocus).requestFocus();
  }

  Future<void> _editCard(CardItem card) async {
    final result = await showEditCardDialog(context, card: card, deck: deck);
    if (result != null) {
      card.native = result.native;
      card.target = result.target;
      card.notes = result.notes;
      card.tags = result.tags;
    }
    // Even a cancelled edit can have added a tag to the deck.
    await widget.store.save();
    if (mounted) setState(() {});
  }

  Future<void> _manageTags() async {
    await showManageTagsDialog(context, deck);
    if (!mounted) return;
    // Tags the dialog renamed or deleted must not linger on the next card
    // or keep filtering the list.
    _newCardTags = deck.keepKnownTags(_newCardTags);
    _filterTags = deck.keepKnownTags(_filterTags);
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
    if (_sortMode == _SortMode.added) return deck.cards.reversed.toList();
    return List.of(deck.cards)
      ..sort((a, b) {
        final byWrong = b.timesWrong.compareTo(a.timesWrong);
        if (byWrong != 0) return byWrong;
        return a.timesCorrect.compareTo(b.timesCorrect);
      });
  }

  String _norm(String s) => s.toLowerCase().trim();

  /// IDs of cards that share the same native+target pair with at least
  /// one other card in the deck. A full scan of the deck — read it once
  /// per build, never once per row.
  Set<String> get _duplicateCardIds {
    final byPair = <String, List<String>>{};
    for (final c in deck.cards) {
      final key = '${_norm(c.native)} ${_norm(c.target)}';
      byPair.putIfAbsent(key, () => []).add(c.id);
    }
    return {
      for (final ids in byPair.values)
        if (ids.length > 1) ...ids,
    };
  }

  /// Sorted cards narrowed by the tag filter and then the search box,
  /// which is matched case-insensitively as a prefix against either side
  /// of the card. Sorts and copies the deck — read it once per build,
  /// never once per row.
  List<CardItem> get _visibleCards {
    final query = _norm(_searchController.text);
    var cards = _sortedCards;
    if (_filterTags.isNotEmpty) {
      cards = cards.where((c) => _filterTags.any(c.tags.contains)).toList();
    }
    if (query.isEmpty) return cards;
    return cards
        .where((c) =>
            _norm(c.native).startsWith(query) ||
            _norm(c.target).startsWith(query))
        .toList();
  }

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
        deck.cards.add(CardItem(
          native: a.native,
          target: a.target,
          notes: a.notes,
          tags: a.tags,
        ));
        added++;
      }
    }
    var retagged = 0;
    for (final r in plan.retags) {
      for (final c in deck.cards) {
        if (_norm(c.target) == _norm(r.target)) {
          c.tags = List.of(r.tags);
          retagged++;
        }
      }
    }
    var renoted = 0;
    for (final n in plan.noteEdits) {
      for (final c in deck.cards) {
        if (_norm(c.target) == _norm(n.target)) {
          c.notes = n.notes;
          renoted++;
        }
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
          if (retagged > 0)
            'retagged $retagged ${retagged == 1 ? "card" : "cards"}',
          if (renoted > 0)
            'updated notes on $renoted ${renoted == 1 ? "card" : "cards"}',
          if (added == 0 && removed == 0 && retagged == 0 && renoted == 0)
            'No changes applied',
        ].join(', ')),
      ),
    );
  }

  /// One side's input in the add-card panel: the text field with any
  /// suggestion dropdown(s) beneath it.
  Widget _addField({required bool isNative}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: isNative ? _nativeController : _targetController,
          focusNode: isNative ? _nativeFocus : _targetFocus,
          decoration: InputDecoration(
            labelText: isNative ? deck.nativeLabel : deck.targetLabel,
            alignLabelWithHint: true,
          ),
          minLines: 5,
          maxLines: 5,
          // Enter still submits instead of inserting a newline — see below.
          textInputAction: TextInputAction.done,
          // Keep focus on submit — the default behavior unfocuses the
          // field, which swallows rapid Enter presses.
          onEditingComplete: () {},
          onSubmitted: (_) => _onSubmit(fromNative: isNative),
        ),
        ..._suggestionsUnder(isNative: isNative),
      ],
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
  /// Shares [counts] with the bar rather than counting the deck twice.
  Widget _buildMasteryLegend(Map<Mastery, int> counts) {
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
    // Each of these walks the whole deck, and the list below would ask for
    // them again for every row it builds — so they are worked out once per
    // frame here and handed down.
    final visibleCards = _visibleCards;
    final duplicateIds = _duplicateCardIds;
    final masteryCounts = deck.masteryCounts;
    final retention = deck.retention;
    return CallbackShortcuts(
      bindings: {
        LogicalKeySet(LogicalKeyboardKey.control, LogicalKeyboardKey.keyF):
            _focusSearch,
        LogicalKeySet(LogicalKeyboardKey.meta, LogicalKeyboardKey.keyF):
            _focusSearch,
      },
      child: Scaffold(
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
            icon: const Icon(Icons.sell_outlined, size: 18),
            label: const Text('Tags'),
            onPressed: _manageTags,
          ),
          const SizedBox(width: 10),
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
                : () => startLearning(context, widget.store, deck,
                    initialTags: _filterTags),
          ),
          const SizedBox(width: 16),
        ],
      ),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1100),
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
                                  'under your field, and fitting tags below. '
                                  'Enter accepts the suggestions, and once '
                                  'more adds the card.'
                              : 'Type either side and press Enter to have '
                                  'AI fill in the other and suggest tags. '
                                  'Use \$…\$ for LaTeX. Enter accepts the '
                                  'suggestions, and once more adds the card.',
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
                                  Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      // Language decks read native →
                                      // target; other decks read Front →
                                      // Back (target → native).
                                      Expanded(
                                        child: _addField(
                                            isNative: deck.isLanguage),
                                      ),
                                      Padding(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 10, vertical: 14),
                                        child: _translating
                                            ? const SizedBox(
                                                width: 22,
                                                height: 22,
                                                child:
                                                    CircularProgressIndicator(
                                                        strokeWidth: 2.5),
                                              )
                                            : Icon(Icons.swap_horiz,
                                                color: SprakTheme.inkSoft),
                                      ),
                                      Expanded(
                                        child: _addField(
                                            isNative: !deck.isLanguage),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  // Notes sit under both sides, spanning
                                  // their full width.
                                  TextField(
                                    controller: _notesController,
                                    style: const TextStyle(fontSize: 13),
                                    decoration: InputDecoration(
                                      labelText: 'Notes (optional)',
                                      alignLabelWithHint: true,
                                      hintText: 'Meaning, usage, example '
                                          'sentence…',
                                      hintStyle: TextStyle(
                                          color: SprakTheme.inkSoft,
                                          fontSize: 13),
                                    ),
                                    minLines: 3,
                                    maxLines: 6,
                                    // Prose field: Enter adds a line
                                    // instead of adding the card.
                                    keyboardType: TextInputType.multiline,
                                    textInputAction: TextInputAction.newline,
                                  ),
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
                        const SizedBox(height: 14),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Icon(Icons.sell_outlined,
                                size: 16, color: SprakTheme.inkSoft),
                            const SizedBox(width: 8),
                            Expanded(
                              child: TagSelector(
                                deck: deck,
                                selected: _newCardTags,
                                onChanged: (next) =>
                                    setState(() => _newCardTags = next),
                                onTagCreated: () {
                                  widget.store.save();
                                  setState(() {});
                                },
                              ),
                            ),
                          ],
                        ),
                        if (_tagSuggestions.isNotEmpty ||
                            _staleTags.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 10),
                            child: _TagSuggestionBox(
                              tags: _tagSuggestions,
                              stale: _staleTags,
                              deck: deck,
                              focusNode: _tagsFocus,
                              onTap: _acceptTags,
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
                            MasteryBar(deck,
                                height: 7, counts: masteryCounts),
                            const SizedBox(height: 6),
                            _buildMasteryLegend(masteryCounts),
                          ],
                        ),
                      ),
                      const SizedBox(width: 20),
                      RetentionLabel(retention),
                    ],
                  ),
                ),
              // --- Search + sort bar ---
              if (deck.cards.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 220,
                        height: 36,
                        child: TextField(
                          controller: _searchController,
                          focusNode: _searchFocus,
                          style: const TextStyle(fontSize: 13),
                          decoration: InputDecoration(
                            isDense: true,
                            hintText: 'Search cards',
                            hintStyle: TextStyle(
                                color: SprakTheme.inkSoft, fontSize: 13),
                            prefixIcon: Icon(Icons.search,
                                size: 18, color: SprakTheme.inkSoft),
                            prefixIconConstraints: const BoxConstraints(
                                minWidth: 34, minHeight: 34),
                            suffixIcon: _searchController.text.isEmpty
                                ? null
                                : IconButton(
                                    icon: const Icon(Icons.close, size: 16),
                                    color: SprakTheme.inkSoft,
                                    onPressed: () {
                                      _searchController.clear();
                                      _searchFocus.requestFocus();
                                    },
                                  ),
                            suffixIconConstraints: const BoxConstraints(
                                minWidth: 34, minHeight: 34),
                            contentPadding: EdgeInsets.zero,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Text(
                        _searchController.text.trim().isEmpty &&
                                _filterTags.isEmpty
                            ? '${deck.cards.length} '
                                '${deck.cards.length == 1 ? "card" : "cards"}'
                            : '${visibleCards.length} of '
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
                            child: Text('Newest first'),
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
                                  ? 'Sort: Newest first'
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
              // --- Tag filter ---
              if (deck.cards.isNotEmpty && deck.tags.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 10),
                  child: TagFilterBar(
                    deck: deck,
                    selected: _filterTags,
                    onChanged: (next) => setState(() => _filterTags = next),
                  ),
                ),
              // --- Card list ---
              Expanded(
                child: deck.cards.isEmpty
                    ? Center(
                        child: Text('No cards in this set yet.',
                            style: TextStyle(color: SprakTheme.inkSoft)),
                      )
                    : visibleCards.isEmpty
                        ? Center(
                            child: Text(
                                _searchController.text.trim().isEmpty
                                    ? 'No cards carry those tags.'
                                    : 'No cards match your search.',
                                style: TextStyle(color: SprakTheme.inkSoft)),
                          )
                        : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                        itemCount: visibleCards.length,
                        separatorBuilder: (_, i) =>
                            const SizedBox(height: 8),
                        itemBuilder: (context, i) {
                          final card = visibleCards[i];
                          final isDuplicate =
                              duplicateIds.contains(card.id);
                          return Card(
                            shape: isDuplicate
                                ? RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    side: BorderSide(
                                        color: SprakTheme.warning, width: 1.5),
                                  )
                                : null,
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
                              title: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Flexible(
                                    child: TexText(card.target,
                                        style: SprakTheme.vocab(size: 20)),
                                  ),
                                  if (isDuplicate) ...[
                                    const SizedBox(width: 8),
                                    Tooltip(
                                      message: 'Another card has the same '
                                          '${deck.nativeLabel} / '
                                          '${deck.targetLabel}',
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: SprakTheme.warning
                                              .withValues(alpha: 0.15),
                                          borderRadius:
                                              BorderRadius.circular(999),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(Icons.warning_amber_rounded,
                                                size: 13,
                                                color: SprakTheme.warning),
                                            const SizedBox(width: 3),
                                            Text('Duplicate',
                                                style: TextStyle(
                                                    color: SprakTheme.warning,
                                                    fontSize: 11,
                                                    fontWeight:
                                                        FontWeight.w700)),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                              subtitle: Padding(
                                padding: const EdgeInsets.only(top: 2),
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    TexText(card.native,
                                        style: TextStyle(
                                            color: SprakTheme.inkSoft)),
                                    if (card.notes.isNotEmpty)
                                      Padding(
                                        padding:
                                            const EdgeInsets.only(top: 6),
                                        child: CardNote(card.notes),
                                      ),
                                    if (card.tags.isNotEmpty)
                                      Padding(
                                        padding:
                                            const EdgeInsets.only(top: 6),
                                        child: TagChips(card.tags),
                                      ),
                                  ],
                                ),
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

/// The tags the model proposed for the card being added, offered until the
/// user accepts them. Tags the deck does not define yet are marked "new" —
/// accepting adds them to the deck's tag list.
class _TagSuggestionBox extends StatelessWidget {
  final List<String> tags;

  /// Tags already on the card that this suggestion takes off it.
  final List<String> stale;
  final Deck deck;
  final FocusNode focusNode;
  final VoidCallback onTap;

  const _TagSuggestionBox({
    required this.tags,
    required this.deck,
    required this.focusNode,
    required this.onTap,
    this.stale = const [],
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
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: SprakTheme.line),
          ),
          child: Row(
            children: [
              Icon(Icons.auto_awesome, size: 18, color: SprakTheme.fjord),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      tags.isEmpty ? 'Tags to remove' : 'Suggested tags',
                      style: TextStyle(
                          color: SprakTheme.inkSoft,
                          fontSize: 11,
                          letterSpacing: 0.5),
                    ),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        for (final t in tags)
                          _SuggestedTagChip(
                            label: t,
                            isNew: deck.findTag(t) == null,
                          ),
                        for (final t in stale)
                          _SuggestedTagChip(label: t, removed: true),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Text(
                '⏎ to apply',
                style: TextStyle(color: SprakTheme.inkSoft, fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One proposed tag, in its own color, with a "new" marker when the deck
/// would gain it. A [removed] chip is one the card loses instead: struck
/// through and muted, so the two directions read apart at a glance.
class _SuggestedTagChip extends StatelessWidget {
  final String label;
  final bool isNew;
  final bool removed;

  const _SuggestedTagChip({
    required this.label,
    this.isNew = false,
    this.removed = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = removed ? SprakTheme.inkSoft : SprakTheme.tagColor(label);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: removed ? 0.10 : 0.16),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w700,
              decoration: removed ? TextDecoration.lineThrough : null,
              decorationColor: color,
            ),
          ),
          if (isNew) ...[
            const SizedBox(width: 5),
            Text(
              'new',
              style: TextStyle(
                color: SprakTheme.inkSoft,
                fontSize: 10,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ],
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
