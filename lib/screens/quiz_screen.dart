import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models.dart';
import '../services/tts_service.dart';
import '../storage.dart';
import '../theme.dart';
import '../widgets/chat_box.dart';

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

const int _kGroupSize = 6;

/// One quiz task: a card asked in a specific direction.
typedef _Task = ({CardItem card, bool askInTarget});

/// Quiz workspace. Cards are shuffled and dealt in groups of six; every card
/// must be answered correctly in BOTH directions before the next group
/// starts, and missed tasks go back into the group's rotation. Clearing the
/// whole deck ends with a celebration. An AI tutor conversation box sits
/// underneath.
class QuizScreen extends StatefulWidget {
  final DeckStore store;
  final Deck deck;
  final QuizMode mode;
  const QuizScreen({
    super.key,
    required this.store,
    required this.deck,
    this.mode = QuizMode.whole,
  });

  @override
  State<QuizScreen> createState() => _QuizScreenState();
}

class _QuizScreenState extends State<QuizScreen> {
  final _answerController = TextEditingController();
  final _answerFocus = FocusNode();
  final _random = Random();

  late List<List<CardItem>> _groups;
  int _groupIndex = 0;

  /// Tasks in the current group not yet answered correctly. Each card
  /// appears twice: once per direction.
  late List<_Task> _remaining;

  _Phase _phase = _Phase.asking;
  bool? _lastCorrect;
  int _correctCount = 0;
  int _wrongCount = 0;

  Deck get deck => widget.deck;
  List<CardItem> get _group => _groups[_groupIndex];
  _Task get _task => _remaining.first;
  CardItem get card => _task.card;
  bool get _askInTarget => _task.askInTarget;
  String get prompt => _askInTarget ? card.target : card.native;
  String get expected => _askInTarget ? card.native : card.target;

  @override
  void initState() {
    super.initState();
    final session = deck.session;
    if (widget.mode == QuizMode.resume &&
        session != null &&
        _restore(session)) {
      return;
    }
    _buildGroups(
        widget.mode == QuizMode.mistakes ? _mistakeOrdered() : _shuffled());
  }

  @override
  void dispose() {
    _answerController.dispose();
    _answerFocus.dispose();
    TtsService().stop();
    super.dispose();
  }

  /// Cleared tasks (card × direction) across all groups so far.
  int get _tasksDone {
    var done = 0;
    for (var g = 0; g < _groupIndex; g++) {
      done += _groups[g].length * 2;
    }
    return done + _group.length * 2 - _remaining.length;
  }

  int get _tasksTotal {
    var total = 0;
    for (final g in _groups) {
      total += g.length * 2;
    }
    return total;
  }

  double get _deckProgress =>
      _tasksTotal == 0 ? 0 : _tasksDone / _tasksTotal;

  List<CardItem> _shuffled() => List.of(deck.cards)..shuffle(_random);

  /// Deck ordered worst-first: most misses, ties broken by fewest correct
  /// answers (shuffled first so equal cards land in random order).
  List<CardItem> _mistakeOrdered() {
    final all = List.of(deck.cards)..shuffle(_random);
    all.sort((a, b) {
      final byWrong = b.timesWrong.compareTo(a.timesWrong);
      if (byWrong != 0) return byWrong;
      return a.timesCorrect.compareTo(b.timesCorrect);
    });
    return all;
  }

  /// Partitions [ordered] into groups of six and starts the first one.
  void _buildGroups(List<CardItem> ordered) {
    _groups = [
      for (var i = 0; i < ordered.length; i += _kGroupSize)
        ordered.sublist(i, min(i + _kGroupSize, ordered.length)),
    ];
    _groupIndex = 0;
    _startGroup();
    _persistSession();
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
          (card: byId[t.cardId]!, askInTarget: t.askInTarget),
    ];
    if (remaining.isEmpty) return false;

    _groups = groups;
    _groupIndex = groupIndex;
    _remaining = remaining;
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
                QuizTaskRef(t.card.id, t.askInTarget),
            ],
          );
  }

  void _startGroup() {
    _remaining = [
      for (final c in _group) ...[
        (card: c, askInTarget: true),
        (card: c, askInTarget: false),
      ],
    ]..shuffle(_random);
  }

  String _normalize(String s) => s
      .toLowerCase()
      .trim()
      .replaceAll(RegExp(r'[.,!?;:"¿¡’' "'" r']'), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .replaceAll('ё', 'е');

  void _check() {
    if (_phase != _Phase.asking) return;
    final correct = _normalize(_answerController.text) == _normalize(expected);
    setState(() {
      _phase = _Phase.answered;
      _lastCorrect = correct;
      if (correct) {
        _correctCount++;
        card.timesCorrect++;
      } else {
        _wrongCount++;
        card.timesWrong++;
      }
    });
    widget.store.save();
    // Keep focus in the (now read-only) field so Enter advances without
    // reaching for the mouse.
    _answerFocus.requestFocus();
    // Always let the learner hear the target-language side.
    TtsService().speak(card.target, ttsLocaleFor(deck.targetLanguage));
  }

  void _next() {
    if (_phase == _Phase.groupCleared) {
      _advanceGroup();
      return;
    }
    if (_phase != _Phase.answered) return;

    if (_lastCorrect == true) {
      _remaining.removeAt(0); // this direction mastered
    } else {
      _remaining.add(_remaining.removeAt(0)); // retry later in the group
    }

    if (_remaining.isEmpty) {
      final deckDone = _groupIndex + 1 >= _groups.length;
      // A finished deck clears the saved session; mid-deck the session
      // points at the next group.
      if (deckDone) {
        _persistSession(clear: true);
      }
      widget.store.save();
      setState(() {
        _phase = deckDone ? _Phase.deckCleared : _Phase.groupCleared;
        _lastCorrect = null;
        _answerController.clear();
      });
      return;
    }

    _persistSession();
    widget.store.save();
    setState(() {
      _phase = _Phase.asking;
      _lastCorrect = null;
      _answerController.clear();
    });
    _answerFocus.requestFocus();
  }

  void _advanceGroup() {
    setState(() {
      _groupIndex++;
      _startGroup();
      _phase = _Phase.asking;
      _lastCorrect = null;
      _answerController.clear();
    });
    _persistSession();
    widget.store.save();
    _answerFocus.requestFocus();
  }

  void _studyAgain() {
    setState(() {
      _buildGroups(_shuffled());
      _phase = _Phase.asking;
      _lastCorrect = null;
      _correctCount = 0;
      _wrongCount = 0;
      _answerController.clear();
    });
    widget.store.save();
    _answerFocus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Text(flagFor(deck.targetLanguage),
                style: const TextStyle(fontSize: 22)),
            const SizedBox(width: 10),
            Text(deck.name),
            const SizedBox(width: 14),
            Text(
              'Group ${_groupIndex + 1} of ${_groups.length}'
              '  ·  $_tasksDone of $_tasksTotal',
              style: TextStyle(color: SprakTheme.inkSoft, fontSize: 13),
            ),
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
      body: Column(
        children: [
          // --- Quiz workspace ---
          Expanded(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: switch (_phase) {
                    _Phase.deckCleared => _buildDeckCleared(),
                    _Phase.groupCleared => _buildGroupCleared(),
                    _ => _buildQuestion(context),
                  },
                ),
              ),
            ),
          ),
          const Divider(height: 1),
          // --- AI tutor conversation box ---
          SizedBox(
            height: 280,
            child: ChatBox(
              targetLanguage: deck.targetLanguage,
              nativeLanguage: deck.nativeLanguage,
              currentContextBuilder: () => (_phase == _Phase.groupCleared ||
                      _phase == _Phase.deckCleared)
                  ? 'reviewing completed cards'
                  : '"${card.target}" (${deck.targetLanguage}) = '
                      '"${card.native}" (${deck.nativeLanguage})',
            ),
          ),
        ],
      ),
    );
  }

  /// Dots showing how many tasks (card × direction) in the current group
  /// are mastered.
  Widget _buildGroupDots() {
    final total = _group.length * 2;
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
          _askInTarget
              ? 'What does this mean in ${deck.nativeLanguage}?'
              : 'How do you say this in ${deck.targetLanguage}?',
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
              child: Text(
                prompt,
                textAlign: TextAlign.center,
                style: SprakTheme.vocab(size: 44),
              ),
            ),
            if (_askInTarget) ...[
              const SizedBox(width: 12),
              IconButton(
                icon: const Icon(Icons.volume_up_outlined, size: 30),
                color: SprakTheme.fjord,
                tooltip: 'Play audio',
                onPressed: () => TtsService()
                    .speak(card.target, ttsLocaleFor(deck.targetLanguage)),
              ),
            ],
          ],
        ),
        const SizedBox(height: 30),
        TextField(
          controller: _answerController,
          focusNode: _answerFocus,
          autofocus: true,
          readOnly: _phase != _Phase.asking,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 22),
          decoration: InputDecoration(
            hintText: _askInTarget ? deck.nativeLanguage : deck.targetLanguage,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
          ),
          onSubmitted: (_) => _phase == _Phase.asking ? _check() : _next(),
        ),
        const SizedBox(height: 20),
        if (_phase == _Phase.asking)
          FilledButton(
            onPressed: _check,
            child: const Text('Check'),
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
                Text('$prompt  →  $expected',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 17)),
              ],
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

  Widget _buildGroupCleared() {
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.enter): _next,
        const SingleActivator(LogicalKeyboardKey.numpadEnter): _next,
      },
      child: Focus(
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
              'All ${_group.length} cards answered correctly in both '
              'languages.',
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
              'Every card in “${deck.name}” cleared in both languages — '
              '${deck.cards.length} cards, ${deck.cards.length * 2} answers.',
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
                    side: const BorderSide(color: SprakTheme.line),
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
