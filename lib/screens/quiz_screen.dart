import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models.dart';
import '../services/claude_service.dart';
import '../services/keyboard_layout_service.dart';
import '../services/llm_service.dart';
import '../services/tts_service.dart';
import '../storage.dart';
import '../theme.dart';
import '../widgets/card_note.dart';
import '../widgets/chat_box.dart';
import '../widgets/edit_card_dialog.dart';
import '../widgets/tex_text.dart';

enum _Phase { asking, answered, groupCleared, deckCleared }

/// How a study session starts.
enum QuizMode {
  /// Whole deck, fully shuffled.
  whole,

  /// Restore the saved session and pick up where the learner left off.
  resume,

  /// Whole deck, ordered so the most-missed cards come first.
  mistakes,
}

/// Cards per study group unless the learner picks another size.
const int kDefaultGroupSize = 6;

/// Group sizes the learner can pick from.
const List<int> kGroupSizeOptions = [3, 4, 5, 6, 8, 10, 12, 15, 20];

/// SharedPreferences key remembering the learner's preferred group size.
const String kGroupSizePref = 'group_size';

/// Below this many total attempts (wrong + correct) a card's ratio isn't
/// trustworthy, so "focus on mistakes" assumes the learner doesn't know it
/// yet and ranks it above cards that have enough history.
const int _kMistakeMinAttempts = 30;

/// One quiz task: a card asked in a specific direction, answered either by
/// typing or by picking from multiple choice.
typedef _Task = ({CardItem card, bool askInTarget, bool isChoice});

/// Quiz workspace. Cards are shuffled and dealt in groups (six by
/// default, changeable from the app bar mid-session); every
/// card must clear all its tasks (which tasks depends on the quiz style)
/// before the next group starts, and missed tasks go back into the group's
/// rotation. Clearing the whole deck ends with a celebration. An AI tutor
/// conversation box sits underneath.
class QuizScreen extends StatefulWidget {
  final DeckStore store;
  final Deck deck;
  final QuizMode mode;
  final QuizStyle style;
  final GradingMode grading;
  final QuizDirection direction;

  /// For [QuizMode.mistakes]: the fraction of the deck to study, taken from
  /// the hardest cards first (e.g. 0.1 = the worst 10%). Ignored by other
  /// modes.
  final double mistakeFraction;

  /// Study only cards carrying at least one of these tags. Empty studies
  /// the whole deck. A resumed session keeps the cards it was saved with,
  /// so this does not apply to [QuizMode.resume].
  final List<String> tags;

  /// Cards per study group for a fresh session. A resumed session keeps
  /// the groups it was saved with until the learner picks a new size.
  final int groupSize;

  const QuizScreen({
    super.key,
    required this.store,
    required this.deck,
    this.mode = QuizMode.whole,
    this.style = QuizStyle.typing,
    this.grading = GradingMode.exact,
    this.direction = QuizDirection.both,
    this.mistakeFraction = 1.0,
    this.tags = const [],
    this.groupSize = kDefaultGroupSize,
  });

  @override
  State<QuizScreen> createState() => _QuizScreenState();
}

class _QuizScreenState extends State<QuizScreen> {
  final _answerController = TextEditingController();
  final _answerFocus = FocusNode();
  final _random = Random();

  /// Live OS keyboard layout (e.g. "U.S.", "Russian"), shown under the
  /// answer field. One stream for the screen's lifetime.
  final _keyboardLayout = KeyboardLayoutService.layoutName();

  /// The input source active when the quiz opened, restored on exit so
  /// auto-switching doesn't leak into the rest of the system.
  String? _originalLayoutId;

  /// Tutor chat panel: dock position (moved via the buttons in its
  /// header), plus its size per orientation — resizable via the drag
  /// handle along its edge. All remembered across sessions.
  static const _chatHeightPref = 'chat_height';
  static const _chatWidthPref = 'chat_width';
  static const _chatPositionPref = 'chat_position';
  static const _chatMinHeight = 140.0;
  static const _chatMinWidth = 280.0;
  double _chatHeight = 280;
  double _chatWidth = 380;
  ChatPosition _chatPosition = ChatPosition.bottom;

  late List<List<CardItem>> _groups;
  int _groupIndex = 0;
  late int _groupSize;

  /// Tasks in the current group not yet answered correctly. Each card
  /// appears twice: once per direction.
  late List<_Task> _remaining;

  /// The group's task order as first dealt, so strict mode can replay it
  /// unchanged after a miss. Null when a resumed session lost it.
  List<_Task>? _groupOrder;

  /// Strict mode: how many full passes of the group are already cleared.
  /// Each group must be cleared [_strictPasses] times, reshuffled each time.
  static const _strictPasses = 3;
  int _strictPass = 0;

  _Phase _phase = _Phase.asking;
  bool? _lastCorrect;
  int _correctCount = 0;
  int _wrongCount = 0;

  /// Tasks already answered this session — only the FIRST attempt at a
  /// task lands in the card's review history, so within-group retries
  /// don't inflate retention.
  final Set<String> _attempted = {};

  /// Whether the current task's outcome was written to the review
  /// history, so an "I was right" override can amend the same entry.
  bool _reviewLogged = false;

  late QuizStyle _style;
  late GradingMode _gradingMode;
  late QuizDirection _direction;

  /// True while an AI grade is in flight; the answer field is frozen and
  /// re-checks are ignored.
  bool _aiChecking = false;
  String? _gradeError;

  /// Options for the current multiple-choice task, and which one the
  /// learner picked.
  List<String> _choices = const [];
  int? _selectedChoice;
  final _choiceFocus = FocusNode();

  /// Keyboard focus for the group/deck-cleared screens, so Enter advances
  /// there too after the chat panel has held focus.
  final _clearedFocus = FocusNode();

  /// Whether the target-language side is read aloud on its own — when a
  /// question shows it, and after every answer. The speaker button next to
  /// the prompt still plays on demand either way. Remembered across
  /// sessions, and only offered for language decks.
  static const _autoSpeakPref = 'auto_speak';
  bool _autoSpeak = true;

  /// Strict mode: a miss sends the learner back to the start of the
  /// group, with every task in it to be cleared again. Remembered across
  /// sessions.
  static const _strictPref = 'strict_mode';
  bool _strict = false;

  /// Guards the first question: the saved toggle arrives a frame or two
  /// after the quiz opens, so nothing is spoken until its value is known.
  bool _autoSpeakLoaded = false;

  Deck get deck => widget.deck;
  List<CardItem> get _group => _groups[_groupIndex];
  _Task get _task => _remaining.first;
  CardItem get card => _task.card;
  bool get _askInTarget => _task.askInTarget;
  bool get _isChoice => _task.isChoice;
  String get prompt => _askInTarget ? card.target : card.native;
  String get expected => _askInTarget ? card.native : card.target;

  /// Tasks each card must clear: multiple choice and/or typing, in one or
  /// both directions. Style "both" adds one choice task on top of typing.
  int get _tasksPerCard {
    final directions = _direction == QuizDirection.both ? 2 : 1;
    return _style == QuizStyle.both ? directions + 1 : directions;
  }

  @override
  void initState() {
    super.initState();
    KeyboardLayoutService.currentId().then((id) => _originalLayoutId = id);
    SharedPreferences.getInstance().then((prefs) {
      if (!mounted) return;
      setState(() {
        _chatHeight = prefs.getDouble(_chatHeightPref) ?? _chatHeight;
        _chatWidth = prefs.getDouble(_chatWidthPref) ?? _chatWidth;
        _chatPosition =
            ChatPosition.fromId(prefs.getString(_chatPositionPref));
        _autoSpeak = prefs.getBool(_autoSpeakPref) ?? _autoSpeak;
        _strict = prefs.getBool(_strictPref) ?? _strict;
        _autoSpeakLoaded = true;
      });
      // The first question was already on screen before the toggle loaded.
      _maybeSpeakPrompt();
    });
    _style = widget.style;
    _groupSize = widget.groupSize;
    _gradingMode = widget.grading;
    _direction = widget.direction;
    final session = deck.session;
    if (widget.mode != QuizMode.resume ||
        session == null ||
        !_restore(session)) {
      _buildGroups(
          widget.mode == QuizMode.mistakes ? _mistakeOrdered() : _shuffled());
    }
    _beginTask();
  }

  @override
  void dispose() {
    _answerController.dispose();
    _answerFocus.dispose();
    _choiceFocus.dispose();
    _clearedFocus.dispose();
    TtsService().stop();
    final original = _originalLayoutId;
    if (original != null) KeyboardLayoutService.selectById(original);
    super.dispose();
  }

  /// Prepares whatever the freshly active task needs: choice options for
  /// multiple choice, the right OS keyboard for typing.
  void _beginTask() {
    if (_remaining.isEmpty) return;
    if (_isChoice) {
      _choices = _buildChoices();
    } else {
      _syncKeyboard();
    }
    _maybeSpeakPrompt();
  }

  /// Reads the question aloud when auto-play is on. Only the
  /// target-language side is spoken — a native-side question would be
  /// giving away the answer it is asking for.
  ///
  /// When there is nothing to read, whatever is still being said is cut
  /// off: moving on to the next card leaves the last one's word and note
  /// mid-sentence, and the learner has moved on.
  void _maybeSpeakPrompt() {
    if (!_autoSpeak ||
        !_autoSpeakLoaded ||
        !deck.isLanguage ||
        _phase != _Phase.asking ||
        _remaining.isEmpty ||
        !_askInTarget) {
      TtsService().stop();
      return;
    }
    TtsService().speak(card.target, ttsLocaleFor(deck.targetLanguage));
  }

  static final _mathDelimiters = RegExp(r'\$\$?');
  static final _whitespace = RegExp(r'\s+');

  /// The note [_noteUtterancesCache] was built from, so an edit to the
  /// card being asked rebuilds it. Null until the first note is read.
  String? _notesSource;
  List<Utterance> _noteUtterancesCache = const [];

  /// The current card's note as speech: only the target-language words
  /// inside it, since the explanation around them is in a language the
  /// learner already has. Empty when the note quotes nothing. The `$…$`
  /// LaTeX delimiters are dropped first, so a note that annotates with
  /// math isn't read as "dollar".
  ///
  /// Read on every build of the answered card, so the result is kept
  /// until the note itself changes.
  List<Utterance> get _noteUtterances {
    final notes = card.notes;
    if (_notesSource != notes) {
      _notesSource = notes;
      _noteUtterancesCache = targetRuns(
        notes
            .replaceAll(_mathDelimiters, ' ')
            .replaceAll(_whitespace, ' ')
            .trim(),
        targetLocale: ttsLocaleFor(deck.targetLanguage),
        nativeLocale: ttsLocaleFor(deck.nativeLanguage),
      );
    }
    return _noteUtterancesCache;
  }

  /// Plays the note on demand, the way the speaker beside the question
  /// plays the word. Only offered on language decks, where the app speaks
  /// at all.
  void _speakNotes() {
    TtsService().speakAll(_noteUtterances);
    _focusTask();
  }

  void _setStrict(bool value) {
    setState(() => _strict = value);
    SharedPreferences.getInstance()
        .then((prefs) => prefs.setBool(_strictPref, value));
    _focusTask();
  }

  void _setAutoSpeak(bool value) {
    setState(() => _autoSpeak = value);
    if (value) {
      _maybeSpeakPrompt();
    } else {
      TtsService().stop();
    }
    SharedPreferences.getInstance()
        .then((prefs) => prefs.setBool(_autoSpeakPref, value));
    // The toggle lives in the app bar, so clicking it takes focus out of
    // the quiz; hand it straight back.
    _focusTask();
  }

  /// Focuses the answer surface of whatever is on screen, so Enter (and
  /// 1–8 for multiple choice) keeps working without reaching for the
  /// mouse. Also how the quiz takes focus back after the tutor chat's
  /// input has held it.
  void _focusTask() {
    if (_phase == _Phase.groupCleared || _phase == _Phase.deckCleared) {
      _clearedFocus.requestFocus();
      return;
    }
    if (_remaining.isEmpty) return;
    (_isChoice ? _choiceFocus : _answerFocus).requestFocus();
  }

  /// The correct answer plus distractors pulled from the rest of the deck
  /// (same side), shuffled. Language decks show 4 options; math/general
  /// decks show 8. Distractors come from the cards being studied first, so
  /// a tag-filtered session keeps its options in-category, with the rest of
  /// the deck backfilling when that is not enough to fill the grid.
  List<String> _buildChoices() {
    final optionCount = deck.isLanguage ? 4 : 8;
    final correct = expected;
    final seen = {_normalize(correct)};
    List<String> optionsFrom(Iterable<CardItem> cards) {
      final out = <String>[];
      for (final c in cards) {
        final option = _askInTarget ? c.native : c.target;
        if (seen.add(_normalize(option))) out.add(option);
      }
      return out..shuffle(_random);
    }

    final studied = optionsFrom(_pool);
    // Already-seen options are skipped, so this only adds cards outside
    // the filter.
    final rest = optionsFrom(deck.cards);
    final choices = [correct, ...studied.take(optionCount - 1)];
    if (choices.length < optionCount) {
      choices.addAll(rest.take(optionCount - choices.length));
    }
    return choices..shuffle(_random);
  }

  /// Switches the OS keyboard to the language the answer should be typed
  /// in. Fire-and-forget: when no matching layout is installed nothing
  /// changes, and the indicator keeps showing the real layout.
  void _syncKeyboard() {
    if (!deck.isLanguage) return;
    if (_remaining.isEmpty) return;
    final language = _askInTarget ? deck.nativeLanguage : deck.targetLanguage;
    KeyboardLayoutService.selectForLanguage(
        ttsLocaleFor(language).split('-').first);
  }

  /// Cleared tasks across all groups so far.
  int get _tasksDone {
    var done = 0;
    for (var g = 0; g < _groupIndex; g++) {
      done += _groups[g].length * _tasksPerCard;
    }
    return done + _group.length * _tasksPerCard - _remaining.length;
  }

  int get _tasksTotal {
    var total = 0;
    for (final g in _groups) {
      total += g.length * _tasksPerCard;
    }
    return total;
  }

  double get _deckProgress =>
      _tasksTotal == 0 ? 0 : _tasksDone / _tasksTotal;

  /// The tags actually narrowing this session — none when resuming (the
  /// saved session carries its own cards) or when the filter matched no
  /// card and was dropped.
  List<String> get _studiedTags {
    if (widget.mode == QuizMode.resume || widget.tags.isEmpty) return const [];
    // Read on every build, so it asks whether any card matches rather than
    // building the filtered list just to look at its length.
    final matched = deck.cards.any((c) => widget.tags.any(c.tags.contains));
    return matched ? widget.tags : const [];
  }

  /// The cards this session studies: the whole deck, or just the ones
  /// carrying a filtered tag. Never empty — a filter that matches nothing
  /// falls back to the deck rather than opening an empty quiz.
  List<CardItem> get _pool {
    final filtered = deck.cardsWithAnyTag(widget.tags);
    return filtered.isEmpty ? List.of(deck.cards) : filtered;
  }

  List<CardItem> _shuffled() => _pool..shuffle(_random);

  /// A card's wrong-to-correct ratio — higher means missed more often
  /// relative to how often it was right. Zero correct answers count as a
  /// denominator of one so an all-wrong card still ranks by its miss count
  /// instead of dividing by zero.
  double _mistakeRatio(CardItem c) =>
      c.timesWrong / (c.timesCorrect == 0 ? 1 : c.timesCorrect);

  /// The hardest cards for "focus on mistakes", worst-first, then trimmed to
  /// [QuizScreen.mistakeFraction] of the deck. Cards attempted fewer than
  /// [_kMistakeMinAttempts] times are assumed unknown and rank above cards
  /// with enough history; within each tier the wrong:correct ratio decides,
  /// ties broken randomly (shuffled before the sort).
  List<CardItem> _mistakeOrdered() {
    final all = _pool..shuffle(_random);
    all.sort((a, b) {
      final aUnknown = a.timesWrong + a.timesCorrect < _kMistakeMinAttempts;
      final bUnknown = b.timesWrong + b.timesCorrect < _kMistakeMinAttempts;
      if (aUnknown != bUnknown) return aUnknown ? -1 : 1;
      return _mistakeRatio(b).compareTo(_mistakeRatio(a));
    });
    final keep = max(1, (all.length * widget.mistakeFraction).round());
    return all.take(keep).toList();
  }

  /// Splits [cards] into consecutive groups of [_groupSize].
  List<List<CardItem>> _chunk(List<CardItem> cards) => [
        for (var i = 0; i < cards.length; i += _groupSize)
          cards.sublist(i, min(i + _groupSize, cards.length)),
      ];

  /// Partitions [ordered] into groups of [_groupSize] and starts the first
  /// one.
  void _buildGroups(List<CardItem> ordered) {
    _groups = _chunk(ordered);
    _groupIndex = 0;
    _startGroup();
    _persistSession();
  }

  /// Re-deals the groups not yet cleared at a new size, keeping their card
  /// order. The current group restarts from scratch at the new size; on
  /// the group-cleared screen only the groups after it are re-dealt.
  void _setGroupSize(int size) {
    SharedPreferences.getInstance()
        .then((prefs) => prefs.setInt(kGroupSizePref, size));
    if (size == _groupSize) {
      _focusTask();
      return;
    }
    final cleared = _phase == _Phase.groupCleared;
    final keep = cleared ? _groupIndex + 1 : _groupIndex;
    final rest = [for (final g in _groups.skip(keep)) ...g];
    setState(() {
      _groupSize = size;
      _groups = [..._groups.take(keep), ..._chunk(rest)];
      if (!cleared) {
        _startGroup();
        _phase = _Phase.asking;
        _lastCorrect = null;
        _selectedChoice = null;
        _gradeError = null;
        _answerController.clear();
        _beginTask();
      }
    });
    _persistSession();
    widget.store.save();
    _focusTask();
  }

  /// Rebuilds quiz state from a saved session; false if it is no longer
  /// usable (e.g. its cards were deleted).
  bool _restore(QuizSession session) {
    final byId = {for (final c in deck.cards) c.id: c};
    final groups = [
      for (final g in session.groups)
        [
          for (final id in g)
            if (byId[id] != null) byId[id]!,
        ],
    ]..removeWhere((g) => g.isEmpty);
    if (groups.isEmpty) return false;

    final groupIndex = session.groupIndex.clamp(0, groups.length - 1);
    final remaining = <_Task>[
      for (final t in session.remaining)
        if (byId[t.cardId] != null)
          (
            card: byId[t.cardId]!,
            askInTarget: t.askInTarget,
            isChoice: t.isChoice,
          ),
    ];
    if (remaining.isEmpty) return false;

    _groups = groups;
    _groupIndex = groupIndex;
    _remaining = remaining;
    _style = session.style;
    _gradingMode = session.grading;
    _direction = session.direction;
    return true;
  }

  /// Writes the current position into the deck so it survives leaving the
  /// screen (persisted by the next store.save()).
  void _persistSession({bool clear = false}) {
    deck.session = clear
        ? null
        : QuizSession(
            groups: [
              for (final g in _groups) [for (final c in g) c.id],
            ],
            groupIndex: _groupIndex,
            remaining: [
              for (final t in _remaining)
                QuizTaskRef(t.card.id, t.askInTarget, isChoice: t.isChoice),
            ],
            style: _style,
            grading: _gradingMode,
            direction: _direction,
          );
  }

  void _startGroup() {
    _strictPass = 0;
    _dealTasks();
  }

  /// Deals every task in the current group in a fresh random order.
  void _dealTasks() {
    // Which sides get asked: askInTarget=true shows the target/front side.
    final askFront = _direction != QuizDirection.back;
    final askBack = _direction != QuizDirection.front;
    _remaining = [
      for (final c in _group) ...[
        // Multiple choice: recognize the target-language word. In pure
        // multiple-choice style both directions are asked this way; in
        // style "both" the single choice task follows the chosen side.
        if (_style != QuizStyle.typing && askFront)
          (card: c, askInTarget: true, isChoice: true),
        if ((_style == QuizStyle.multipleChoice ||
                (_style == QuizStyle.both && !askFront)) &&
            askBack)
          (card: c, askInTarget: false, isChoice: true),
        if (_style != QuizStyle.multipleChoice) ...[
          if (askFront) (card: c, askInTarget: true, isChoice: false),
          if (askBack) (card: c, askInTarget: false, isChoice: false),
        ],
      ],
    ]..shuffle(_random);
    _groupOrder = List.of(_remaining);
  }

  /// Strict-mode restart: the same tasks in the same order as first dealt.
  void _restartGroup() {
    final order = _groupOrder;
    if (order == null) {
      _dealTasks();
    } else {
      _remaining = List.of(order);
    }
  }

  String _normalize(String s) => s
      .toLowerCase()
      .trim()
      .replaceAll(RegExp(r'[.,!?;:"¿¡’' "'" r']'), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .replaceAll('ё', 'е');

  Future<void> _check() async {
    if (_phase != _Phase.asking || _aiChecking) return;
    final answer = _answerController.text.trim();
    final exactMatch = _normalize(answer) == _normalize(expected);

    // Exact matches (and empty answers) never need the AI judge.
    if (exactMatch || answer.isEmpty || _gradingMode == GradingMode.exact) {
      _finishTask(exactMatch);
      // Keep focus in the (now read-only) field so Enter advances without
      // reaching for the mouse.
      _answerFocus.requestFocus();
      return;
    }

    setState(() {
      _aiChecking = true;
      _gradeError = null;
    });
    try {
      final correct = await LlmService.gradeAnswer(
        question: prompt,
        expected: expected,
        answer: answer,
        subject: deck.isLanguage ? deck.targetLanguage : deck.kind.label,
      );
      if (!mounted) return;
      _finishTask(correct);
    } on LlmException catch (e) {
      if (!mounted) return;
      // Grade strictly instead of blocking — the "My answer was right"
      // override still lets the learner correct it.
      setState(() => _gradeError = 'AI grading unavailable (${e.message}) '
          '— graded exactly instead.');
      _finishTask(false);
    } finally {
      if (mounted) setState(() => _aiChecking = false);
    }
    _answerFocus.requestFocus();
  }

  void _checkChoice(int index) {
    if (_phase != _Phase.asking || index >= _choices.length) return;
    _selectedChoice = index;
    _finishTask(_normalize(_choices[index]) == _normalize(expected));
    _choiceFocus.requestFocus();
  }

  void _finishTask(bool correct) {
    final firstAttempt =
        _attempted.add('${card.id}|$_askInTarget|$_isChoice');
    _reviewLogged = firstAttempt;
    setState(() {
      _phase = _Phase.answered;
      _lastCorrect = correct;
      if (firstAttempt) card.addReview(correct);
      if (correct) {
        _correctCount++;
        card.timesCorrect++;
      } else {
        _wrongCount++;
        card.timesWrong++;
      }
    });
    widget.store.save();
    // Let the learner hear the target-language side and then the note
    // shown with it, unless auto-play is switched off.
    if (deck.isLanguage && _autoSpeak) {
      TtsService().speakAll([
        (text: card.target, locale: ttsLocaleFor(deck.targetLanguage)),
        ..._noteUtterances,
      ]);
    }
  }

  /// "I was right" override: e.g. the answer was "I'm getting ready" and
  /// the learner typed "i am getting ready". Rewrites every trace of the
  /// wrong mark — score, card stats, review history, group rotation — so
  /// the saved state is identical to a character-for-character answer.
  void _markActuallyCorrect() {
    if (_phase != _Phase.answered || _lastCorrect != false) return;
    setState(() {
      _lastCorrect = true;
      _correctCount++;
      _wrongCount--;
      card.timesCorrect++;
      card.timesWrong--;
      if (_reviewLogged && card.reviews.isNotEmpty) {
        final last = card.reviews.last;
        card.reviews[card.reviews.length - 1] = CardReview(last.at, true);
      }
    });
    widget.store.save();
    _focusTask();
  }

  /// Edits the card being asked right now (e.g. to fix a typo spotted
  /// mid-quiz). The question, expected answer, and any on-screen choice
  /// option update in place; stats and group rotation are untouched.
  Future<void> _editCurrentCard() async {
    final edited = card;
    final oldExpected = expected;
    final result = await showEditCardDialog(
      context,
      card: edited,
      deck: deck,
    );
    if (!mounted) return;
    if (result == null) {
      // Nothing changed on the card, but the dialog may have added a tag
      // to the deck.
      await widget.store.save();
      _focusTask();
      return;
    }
    setState(() {
      edited.native = result.native;
      edited.target = result.target;
      edited.notes = result.notes;
      edited.tags = result.tags;
      // The correct option's text changed with the card — swap it so
      // picking (or highlighting) the right answer still works.
      if (_isChoice) {
        final i = _choices
            .indexWhere((c) => _normalize(c) == _normalize(oldExpected));
        if (i != -1) _choices[i] = expected;
      }
    });
    await widget.store.save();
    _focusTask();
  }

  void _next() {
    if (_phase == _Phase.groupCleared) {
      _advanceGroup();
      return;
    }
    if (_phase != _Phase.answered) return;

    if (_lastCorrect == true) {
      _remaining.removeAt(0); // this direction mastered
    } else if (_strict) {
      _restartGroup(); // strict: a miss replays the group in order
    } else {
      _remaining.add(_remaining.removeAt(0)); // retry later in the group
    }

    if (_remaining.isEmpty && _strict && _strictPass + 1 < _strictPasses) {
      _strictPass++; // strict: clear the group again, reshuffled
      _dealTasks();
    }

    if (_remaining.isEmpty) {
      final deckDone = _groupIndex + 1 >= _groups.length;
      // A finished deck clears the saved session; mid-deck the session
      // points at the next group.
      if (deckDone) {
        _persistSession(clear: true);
      }
      widget.store.save();
      // The cleared screen replaces the card that was being read.
      TtsService().stop();
      setState(() {
        _phase = deckDone ? _Phase.deckCleared : _Phase.groupCleared;
        _lastCorrect = null;
        _selectedChoice = null;
        _answerController.clear();
      });
      _focusTask();
      return;
    }

    _persistSession();
    widget.store.save();
    setState(() {
      _phase = _Phase.asking;
      _lastCorrect = null;
      _selectedChoice = null;
      _gradeError = null;
      _answerController.clear();
      _beginTask();
    });
    _focusTask();
  }

  void _advanceGroup() {
    setState(() {
      _groupIndex++;
      _startGroup();
      _phase = _Phase.asking;
      _lastCorrect = null;
      _selectedChoice = null;
      _answerController.clear();
      _beginTask();
    });
    _persistSession();
    widget.store.save();
    _focusTask();
  }

  void _studyAgain() {
    _attempted.clear();
    setState(() {
      _buildGroups(_shuffled());
      _phase = _Phase.asking;
      _lastCorrect = null;
      _selectedChoice = null;
      _correctCount = 0;
      _wrongCount = 0;
      _answerController.clear();
      _beginTask();
    });
    widget.store.save();
    _focusTask();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Text(deck.emblem, style: const TextStyle(fontSize: 22)),
            const SizedBox(width: 10),
            // The name gives way first when the bar runs out of room.
            Flexible(
              child: Text(deck.name, overflow: TextOverflow.ellipsis),
            ),
            const SizedBox(width: 14),
            Text(
              'Group ${_groupIndex + 1} of ${_groups.length}'
              '${_strict ? '  ·  Pass ${_strictPass + 1}/$_strictPasses' : ''}'
              '  ·  $_tasksDone of $_tasksTotal',
              style: TextStyle(color: SprakTheme.inkSoft, fontSize: 13),
            ),
            // The tags this session was narrowed to, so a partial deck
            // never looks like the whole one.
            if (_studiedTags.isNotEmpty) ...[
              const SizedBox(width: 14),
              Icon(Icons.filter_alt_outlined,
                  size: 15, color: SprakTheme.inkSoft),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  _studiedTags.join(', '),
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: SprakTheme.fjord,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ],
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(5),
          child: TweenAnimationBuilder<double>(
            tween: Tween(end: _deckProgress),
            duration: const Duration(milliseconds: 350),
            curve: Curves.easeOutCubic,
            builder: (context, value, _) => LinearProgressIndicator(
              value: value,
              minHeight: 5,
              backgroundColor: SprakTheme.panel,
              color: SprakTheme.fjord,
            ),
          ),
        ),
        actions: [
          if (_phase != _Phase.deckCleared)
            PopupMenuButton<int>(
              tooltip: 'Words per group: $_groupSize',
              initialValue: _groupSize,
              onSelected: _setGroupSize,
              itemBuilder: (context) => [
                for (final n in kGroupSizeOptions)
                  PopupMenuItem(value: n, child: Text('$n per group')),
              ],
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.grid_view,
                        size: 18, color: SprakTheme.inkSoft),
                    const SizedBox(width: 4),
                    Text('$_groupSize',
                        style: TextStyle(
                            color: SprakTheme.inkSoft,
                            fontWeight: FontWeight.w700)),
                  ],
                ),
              ),
            ),
          IconButton(
            icon: Icon(_strict ? Icons.lock : Icons.lock_open_outlined,
                size: 20),
            color: _strict ? SprakTheme.fjord : SprakTheme.inkSoft,
            tooltip: _strict
                ? 'Strict mode: a miss restarts the group (on)'
                : 'Strict mode: a miss restarts the group (off)',
            onPressed: () => _setStrict(!_strict),
          ),
          if (deck.isLanguage) ...[
            IconButton(
              // Filled while on, so it reads as engaged next to the
              // outlined play-on-demand speaker under it.
              icon: Icon(
                  _autoSpeak ? Icons.volume_up : Icons.volume_off_outlined,
                  size: 20),
              color: _autoSpeak ? SprakTheme.fjord : SprakTheme.inkSoft,
              tooltip: _autoSpeak
                  ? 'Read words aloud automatically: on'
                  : 'Read words aloud automatically: off',
              onPressed: () => _setAutoSpeak(!_autoSpeak),
            ),
            const SizedBox(width: 4),
          ],
          if (_phase == _Phase.asking || _phase == _Phase.answered) ...[
            IconButton(
              icon: const Icon(Icons.edit_outlined, size: 20),
              tooltip: 'Edit this card',
              // Frozen while an AI grade is in flight — editing would
              // change the expected answer mid-check.
              onPressed: _aiChecking ? null : _editCurrentCard,
            ),
            const SizedBox(width: 4),
          ],
          _ScorePill(
              icon: Icons.check,
              color: SprakTheme.success,
              count: _correctCount),
          const SizedBox(width: 8),
          _ScorePill(
              icon: Icons.close,
              color: Theme.of(context).colorScheme.error,
              count: _wrongCount),
          const SizedBox(width: 20),
        ],
      ),
      body: _buildBody(context),
    );
  }

  /// Quiz workspace plus the tutor chat, docked left, right, or at the
  /// bottom, separated by a resize handle.
  Widget _buildBody(BuildContext context) {
    // Scrollable so tall content (8-option grids, long answers) never
    // overflows when the window or quiz pane is short.
    final quizArea = Expanded(
      // Typing in the tutor chat moves keyboard focus into its text field,
      // which leaves the quiz's shortcuts (1–8, Enter) dead until something
      // asks for focus back. Any click in the quiz pane is that signal.
      // A Listener rather than a GestureDetector: it observes the pointer
      // without entering the gesture arena, so it can't steal the click
      // from the button or choice tile that was actually pressed.
      child: Listener(
        onPointerDown: (_) => _focusTask(),
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: switch (_phase) {
                _Phase.deckCleared => _buildDeckCleared(),
                _Phase.groupCleared => _buildGroupCleared(),
                _ => _buildQuestion(context),
              },
            ),
          ),
        ),
      ),
    );
    final chat = ChatBox(
      position: _chatPosition,
      onPositionChanged: _setChatPosition,
      targetLanguage: deck.targetLanguage,
      nativeLanguage: deck.nativeLanguage,
      subject: deck.isLanguage ? null : deck.kind.label,
      currentContextBuilder: () =>
          (_phase == _Phase.groupCleared || _phase == _Phase.deckCleared)
              ? 'reviewing completed cards'
              : '"${card.target}" (${deck.targetLanguage}) = '
                  '"${card.native}" (${deck.nativeLanguage})',
    );

    switch (_chatPosition) {
      case ChatPosition.bottom:
        return Column(children: [
          quizArea,
          _buildResizeHandle(context),
          SizedBox(
            height: _chatHeight.clamp(_chatMinHeight, _maxChatHeight(context)),
            child: chat,
          ),
        ]);
      case ChatPosition.left:
        return Row(children: [
          SizedBox(
            width: _chatWidth.clamp(_chatMinWidth, _maxChatWidth(context)),
            child: chat,
          ),
          _buildResizeHandle(context),
          quizArea,
        ]);
      case ChatPosition.right:
        return Row(children: [
          quizArea,
          _buildResizeHandle(context),
          SizedBox(
            width: _chatWidth.clamp(_chatMinWidth, _maxChatWidth(context)),
            child: chat,
          ),
        ]);
    }
  }

  void _setChatPosition(ChatPosition position) {
    setState(() => _chatPosition = position);
    SharedPreferences.getInstance()
        .then((prefs) => prefs.setString(_chatPositionPref, position.id));
  }

  Future<void> _saveChatSize() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_chatHeightPref, _chatHeight);
    await prefs.setDouble(_chatWidthPref, _chatWidth);
  }

  /// Thin draggable bar between quiz and chat that resizes the chat panel
  /// (perpendicular to the docked edge — it does not move the panel).
  Widget _buildResizeHandle(BuildContext context) {
    final bottom = _chatPosition == ChatPosition.bottom;
    return MouseRegion(
      cursor: bottom
          ? SystemMouseCursors.resizeRow
          : SystemMouseCursors.resizeColumn,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onVerticalDragUpdate: !bottom
            ? null
            : (details) => setState(() {
                  _chatHeight = (_chatHeight - details.delta.dy)
                      .clamp(_chatMinHeight, _maxChatHeight(context));
                }),
        onHorizontalDragUpdate: bottom
            ? null
            : (details) => setState(() {
                  final delta = _chatPosition == ChatPosition.left
                      ? details.delta.dx
                      : -details.delta.dx;
                  _chatWidth = (_chatWidth + delta)
                      .clamp(_chatMinWidth, _maxChatWidth(context));
                }),
        onVerticalDragEnd: !bottom ? null : (_) => _saveChatSize(),
        onHorizontalDragEnd: bottom ? null : (_) => _saveChatSize(),
        child: Container(
          height: bottom ? 11 : null,
          width: bottom ? null : 11,
          decoration: BoxDecoration(
            border: bottom
                ? Border(top: BorderSide(color: SprakTheme.line))
                : Border(left: BorderSide(color: SprakTheme.line)),
          ),
          child: Center(
            child: Container(
              width: bottom ? 36 : 4,
              height: bottom ? 4 : 36,
              decoration: BoxDecoration(
                color: SprakTheme.line,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// The chat can take at most 60% of the window width when docked to a
  /// side, so the quiz workspace always stays usable.
  double _maxChatWidth(BuildContext context) =>
      max(_chatMinWidth, MediaQuery.sizeOf(context).width * 0.6);

  /// The chat can take at most 70% of the window, so the quiz workspace
  /// always stays usable.
  double _maxChatHeight(BuildContext context) =>
      max(_chatMinHeight, MediaQuery.sizeOf(context).height * 0.7);

  /// Dots showing how many tasks in the current group are mastered.
  Widget _buildGroupDots() {
    final total = _group.length * _tasksPerCard;
    final clearedCount = total - _remaining.length;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < total; i++)
          Container(
            width: 9,
            height: 9,
            margin: const EdgeInsets.symmetric(horizontal: 3),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: i < clearedCount ? SprakTheme.success : null,
              border: i < clearedCount
                  ? null
                  : Border.all(color: SprakTheme.line, width: 1.5),
            ),
          ),
      ],
    );
  }

  Widget _buildQuestion(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildGroupDots(),
        const SizedBox(height: 20),
        Text(
          deck.isLanguage
              ? (_askInTarget
                  ? 'What does this mean in ${deck.nativeLanguage}?'
                  : 'How do you say this in ${deck.targetLanguage}?')
              : (_askInTarget
                  ? 'What is the answer?'
                  : 'What question has this answer?'),
          textAlign: TextAlign.center,
          style: TextStyle(
            color: SprakTheme.inkSoft,
            fontSize: 15,
            letterSpacing: 0.3,
          ),
        ),
        const SizedBox(height: 14),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Flexible(
              child: TexText(
                prompt,
                textAlign: TextAlign.center,
                style: SprakTheme.vocab(size: 44),
                selectable: true,
              ),
            ),
            if (_askInTarget && deck.isLanguage) ...[
              const SizedBox(width: 12),
              IconButton(
                icon: const Icon(Icons.volume_up_outlined, size: 30),
                color: SprakTheme.fjord,
                tooltip: 'Play audio',
                onPressed: () => TtsService()
                    .speak(card.target, ttsLocaleFor(deck.targetLanguage)),
              ),
            ],
            // Editing where the learner is already looking — a typo in the
            // card is usually spotted while reading the question, not while
            // scanning the app bar (which carries the same action).
            const SizedBox(width: 4),
            IconButton(
              icon: const Icon(Icons.edit_outlined, size: 22),
              color: SprakTheme.inkSoft,
              tooltip: 'Edit this card',
              // Frozen while an AI grade is in flight — editing would
              // change the expected answer mid-check.
              onPressed: _aiChecking ? null : _editCurrentCard,
            ),
          ],
        ),
        const SizedBox(height: 30),
        if (_isChoice)
          _buildChoiceOptions(context)
        else ...[
          TextField(
            controller: _answerController,
            focusNode: _answerFocus,
            autofocus: true,
            readOnly: _phase != _Phase.asking || _aiChecking,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 22),
            decoration: InputDecoration(
              hintText: deck.isLanguage
                  ? (_askInTarget ? deck.nativeLanguage : deck.targetLanguage)
                  : 'Your answer',
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
            ),
            // Keep focus on submit — the default behavior unfocuses the
            // field, which swallows rapid Enter presses.
            onEditingComplete: () {},
            onSubmitted: (_) => _phase == _Phase.asking ? _check() : _next(),
          ),
          if (deck.isLanguage)
            StreamBuilder<String?>(
              stream: _keyboardLayout,
              builder: (context, snapshot) {
              final layout = snapshot.data;
              if (layout == null) return const SizedBox.shrink();
              return Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.keyboard_alt_outlined,
                        size: 16, color: SprakTheme.inkSoft),
                    const SizedBox(width: 6),
                    Text(
                      'Keyboard: $layout',
                      style: TextStyle(
                          color: SprakTheme.inkSoft, fontSize: 12.5),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
        const SizedBox(height: 20),
        if (_phase == _Phase.asking)
          _isChoice
              ? const SizedBox.shrink()
              : FilledButton(
                  onPressed: _aiChecking ? null : _check,
                  child: _aiChecking
                      ? const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2),
                            ),
                            SizedBox(width: 10),
                            Text('Checking…'),
                          ],
                        )
                      : const Text('Check'),
                )
        else ...[
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: _lastCorrect!
                  ? SprakTheme.success.withValues(alpha: 0.10)
                  : Theme.of(context)
                      .colorScheme
                      .error
                      .withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: _lastCorrect!
                    ? SprakTheme.success.withValues(alpha: 0.4)
                    : Theme.of(context)
                        .colorScheme
                        .error
                        .withValues(alpha: 0.35),
              ),
            ),
            child: Column(
              children: [
                Text(
                  _lastCorrect!
                      ? 'Correct!'
                      : 'Not quite — it will come back around.',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                    color: _lastCorrect!
                        ? SprakTheme.success
                        : Theme.of(context).colorScheme.error,
                  ),
                ),
                const SizedBox(height: 6),
                if (_lastCorrect!)
                  TexText('$prompt  →  $expected',
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 17),
                      selectable: true)
                else ...[
                  // Missed — make the correct answer the star of the card.
                  const SizedBox(height: 4),
                  TexText(expected,
                      textAlign: TextAlign.center,
                      style: SprakTheme.vocab(size: 28),
                      selectable: true),
                  const SizedBox(height: 4),
                  TexText(prompt,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          color: SprakTheme.inkSoft, fontSize: 14),
                      selectable: true),
                ],
                if (card.notes.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  CardNote(
                    card.notes,
                    fontSize: 14,
                    onSpeak: deck.isLanguage && _noteUtterances.isNotEmpty
                        ? _speakNotes
                        : null,
                  ),
                ],
                if (!_lastCorrect! && !_isChoice) ...[
                  const SizedBox(height: 6),
                  TextButton.icon(
                    onPressed: _markActuallyCorrect,
                    icon: const Icon(Icons.check_circle_outline, size: 16),
                    style: TextButton.styleFrom(
                      foregroundColor: SprakTheme.success,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 8),
                      textStyle: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w700),
                    ),
                    label: const Text('My answer was right — count it'),
                  ),
                ],
              ],
            ),
          ),
          if (_gradeError != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                _gradeError!,
                textAlign: TextAlign.center,
                style: TextStyle(color: SprakTheme.inkSoft, fontSize: 12),
              ),
            ),
          const SizedBox(height: 14),
          FilledButton.icon(
            onPressed: _next,
            icon: const Icon(Icons.arrow_forward, size: 18),
            label: const Text('Next  ⏎'),
          ),
        ],
      ],
    );
  }

  /// The four multiple-choice tiles. Selectable by click or the 1–4 keys;
  /// after answering, the correct option turns green and a wrong pick red.
  Widget _buildChoiceOptions(BuildContext context) {
    const digits = [
      LogicalKeyboardKey.digit1,
      LogicalKeyboardKey.digit2,
      LogicalKeyboardKey.digit3,
      LogicalKeyboardKey.digit4,
      LogicalKeyboardKey.digit5,
      LogicalKeyboardKey.digit6,
      LogicalKeyboardKey.digit7,
      LogicalKeyboardKey.digit8,
    ];
    return CallbackShortcuts(
      bindings: {
        for (var i = 0; i < _choices.length && i < digits.length; i++)
          SingleActivator(digits[i]): () => _checkChoice(i),
        const SingleActivator(LogicalKeyboardKey.enter): _next,
        const SingleActivator(LogicalKeyboardKey.numpadEnter): _next,
      },
      child: Focus(
        focusNode: _choiceFocus,
        autofocus: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildChoiceGrid(context),
            if (_phase == _Phase.asking)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(
                  'Press 1–${_choices.length} to answer',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: SprakTheme.inkSoft, fontSize: 12),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// Up to 4 options stack vertically; more (math/general decks show 8)
  /// go into two columns so they all fit on screen. Numbering reads
  /// left-to-right, matching the 1–8 shortcuts.
  Widget _buildChoiceGrid(BuildContext context) {
    if (_choices.length <= 4) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < _choices.length; i++) ...[
            if (i > 0) const SizedBox(height: 8),
            _buildChoiceTile(context, i),
          ],
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var row = 0; row * 2 < _choices.length; row++) ...[
          if (row > 0) const SizedBox(height: 8),
          // IntrinsicHeight + stretch: both tiles in a row take the
          // taller one's height instead of shrinking to their own text.
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: _buildChoiceTile(context, row * 2)),
                const SizedBox(width: 8),
                Expanded(
                  child: row * 2 + 1 < _choices.length
                      ? _buildChoiceTile(context, row * 2 + 1)
                      : const SizedBox.shrink(),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildChoiceTile(BuildContext context, int i) {
    final answered = _phase != _Phase.asking;
    final isCorrect = _normalize(_choices[i]) == _normalize(expected);
    final isPicked = _selectedChoice == i;

    Color? accent;
    if (answered && isCorrect) {
      accent = SprakTheme.success;
    } else if (answered && isPicked) {
      accent = Theme.of(context).colorScheme.error;
    }

    return Material(
      color:
          accent != null ? accent.withValues(alpha: 0.10) : SprakTheme.panel,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: answered ? null : () => _checkChoice(i),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          // Centers the content when the tile is stretched to match a
          // taller neighbor in the two-column grid.
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
                color: accent?.withValues(alpha: 0.5) ?? SprakTheme.line),
          ),
          child: Row(
            children: [
              Container(
                width: 24,
                height: 24,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color:
                      (accent ?? SprakTheme.fjord).withValues(alpha: 0.15),
                ),
                child: Text(
                  '${i + 1}',
                  style: TextStyle(
                      color: accent ?? SprakTheme.fjord,
                      fontSize: 12,
                      fontWeight: FontWeight.w800),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child:
                    TexText(_choices[i], style: SprakTheme.vocab(size: 18)),
              ),
              if (answered && isCorrect)
                Icon(Icons.check, size: 18, color: SprakTheme.success)
              else if (answered && isPicked)
                Icon(Icons.close,
                    size: 18, color: Theme.of(context).colorScheme.error),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGroupCleared() {
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.enter): _next,
        const SingleActivator(LogicalKeyboardKey.numpadEnter): _next,
      },
      child: Focus(
        focusNode: _clearedFocus,
        autofocus: true,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('🎉', style: TextStyle(fontSize: 52)),
            const SizedBox(height: 12),
            Text('Group cleared!',
                style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 8),
            Text(
              'Every task for all ${_group.length} cards answered '
              'correctly.',
              textAlign: TextAlign.center,
              style: TextStyle(color: SprakTheme.inkSoft),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _next,
              icon: const Icon(Icons.arrow_forward, size: 18),
              label: const Text('Next group  ⏎'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDeckCleared() {
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.enter): _studyAgain,
        const SingleActivator(LogicalKeyboardKey.numpadEnter): _studyAgain,
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            Navigator.of(context).pop(),
      },
      child: Focus(
        focusNode: _clearedFocus,
        autofocus: true,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('🎊 🏆 🎊', style: TextStyle(fontSize: 56)),
            const SizedBox(height: 16),
            ShaderMask(
              shaderCallback: (bounds) =>
                  SprakTheme.aurora.createShader(bounds),
              blendMode: BlendMode.srcIn,
              child: Text(
                'Deck complete!',
                style: SprakTheme.vocab(size: 40).copyWith(
                    color: Colors.white, fontWeight: FontWeight.w700),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'Every card in “${deck.name}” cleared — ${deck.cards.length} '
              'cards, ${deck.cards.length * _tasksPerCard} answers.',
              textAlign: TextAlign.center,
              style: TextStyle(color: SprakTheme.inkSoft, fontSize: 15),
            ),
            const SizedBox(height: 28),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                FilledButton.icon(
                  onPressed: _studyAgain,
                  icon: const Icon(Icons.replay, size: 18),
                  label: const Text('Study again  ⏎'),
                ),
                const SizedBox(width: 12),
                OutlinedButton.icon(
                  onPressed: () => Navigator.of(context).pop(),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: SprakTheme.ink,
                    side: BorderSide(color: SprakTheme.line),
                    shape: const StadiumBorder(),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 22, vertical: 16),
                  ),
                  icon: const Icon(Icons.home_outlined, size: 18),
                  label: const Text('Back to sets'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ScorePill extends StatelessWidget {
  final IconData icon;
  final Color color;
  final int count;
  const _ScorePill(
      {required this.icon, required this.color, required this.count});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          Text('$count',
              style: TextStyle(
                  color: color, fontWeight: FontWeight.w800, fontSize: 14)),
        ],
      ),
    );
  }
}
