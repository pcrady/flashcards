import 'dart:math';

import 'package:flutter/material.dart';

import '../models.dart';
import '../services/tts_service.dart';
import '../storage.dart';
import '../theme.dart';
import '../widgets/chat_box.dart';

enum _Phase { asking, answered }

/// Quiz workspace: shows a prompt in one language, checks the typed answer
/// against the other. An AI tutor conversation box sits underneath.
class QuizScreen extends StatefulWidget {
  final DeckStore store;
  final Deck deck;
  const QuizScreen({super.key, required this.store, required this.deck});

  @override
  State<QuizScreen> createState() => _QuizScreenState();
}

class _QuizScreenState extends State<QuizScreen> {
  final _answerController = TextEditingController();
  final _answerFocus = FocusNode();
  final _random = Random();

  late List<CardItem> _queue;
  int _index = 0;
  bool _askInTarget = false; // prompt shown in target language?
  _Phase _phase = _Phase.asking;
  bool? _lastCorrect;
  int _correctCount = 0;
  int _wrongCount = 0;

  Deck get deck => widget.deck;
  CardItem get card => _queue[_index];
  String get prompt => _askInTarget ? card.target : card.native;
  String get expected => _askInTarget ? card.native : card.target;

  @override
  void initState() {
    super.initState();
    _queue = List.of(deck.cards)..shuffle(_random);
    _rollDirection();
  }

  @override
  void dispose() {
    _answerController.dispose();
    _answerFocus.dispose();
    TtsService().stop();
    super.dispose();
  }

  void _rollDirection() {
    _askInTarget = _random.nextBool();
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
    // Always let the learner hear the target-language side.
    TtsService().speak(card.target, ttsLocaleFor(deck.targetLanguage));
  }

  void _next() {
    setState(() {
      _index = (_index + 1) % _queue.length;
      if (_index == 0) _queue.shuffle(_random);
      _rollDirection();
      _phase = _Phase.asking;
      _lastCorrect = null;
      _answerController.clear();
    });
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
          ],
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
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
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
                              icon: const Icon(Icons.volume_up_outlined,
                                  size: 30),
                              color: SprakTheme.fjord,
                              tooltip: 'Play audio',
                              onPressed: () => TtsService().speak(card.target,
                                  ttsLocaleFor(deck.targetLanguage)),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 30),
                      TextField(
                        controller: _answerController,
                        focusNode: _answerFocus,
                        autofocus: true,
                        enabled: _phase == _Phase.asking,
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 22),
                        decoration: InputDecoration(
                          hintText: _askInTarget
                              ? deck.nativeLanguage
                              : deck.targetLanguage,
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 18),
                        ),
                        onSubmitted: (_) =>
                            _phase == _Phase.asking ? _check() : _next(),
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
                                _lastCorrect! ? 'Correct!' : 'Not quite.',
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
                          autofocus: true,
                          onPressed: _next,
                          icon: const Icon(Icons.arrow_forward, size: 18),
                          label: const Text('Next'),
                        ),
                      ],
                    ],
                  ),
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
              currentContextBuilder: () =>
                  '"${card.target}" (${deck.targetLanguage}) = '
                  '"${card.native}" (${deck.nativeLanguage})',
            ),
          ),
        ],
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
