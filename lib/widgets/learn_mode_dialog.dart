import 'package:flutter/material.dart';

import '../models.dart';
import '../screens/quiz_screen.dart';
import '../storage.dart';
import '../theme.dart';

/// Asks how to study (whole deck / continue / focus on mistakes) and how
/// to answer (multiple choice / typing / both), then opens the quiz.
/// Resuming skips the second question — the style is saved in the session.
Future<void> startLearning(
    BuildContext context, DeckStore store, Deck deck) async {
  if (deck.cards.isEmpty) return;

  final session = deck.session;
  final mode = await showDialog<QuizMode>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('Study “${deck.name}”'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _ModeTile(
              icon: Icons.shuffle,
              title: 'Whole deck',
              subtitle: 'Every card, shuffled into groups of six.',
              onTap: () => Navigator.pop(context, QuizMode.whole),
            ),
            const SizedBox(height: 10),
            _ModeTile(
              icon: Icons.play_circle_outline,
              title: 'Pick up where you left off',
              subtitle: session != null
                  ? 'Continue from group ${session.groupIndex + 1} of '
                      '${session.groups.length}.'
                  : 'No session in progress.',
              enabled: session != null,
              onTap: () => Navigator.pop(context, QuizMode.resume),
            ),
            const SizedBox(height: 10),
            _ModeTile(
              icon: Icons.local_fire_department_outlined,
              title: 'Focus on mistakes',
              subtitle:
                  'The words and phrases you miss most often come first.',
              onTap: () => Navigator.pop(context, QuizMode.mistakes),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
      ],
    ),
  );

  if (mode == null || !context.mounted) return;

  QuizStyle? style;
  var grading = GradingMode.exact;
  if (mode == QuizMode.resume) {
    style = session?.style ?? QuizStyle.typing;
    grading = session?.grading ?? GradingMode.exact;
  } else {
    style = await showDialog<QuizStyle>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('How do you want to answer?'),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _ModeTile(
                icon: Icons.checklist,
                title: 'Multiple choice',
                subtitle: 'Pick the right answer out of '
                    '${deck.isLanguage ? "four" : "eight"} options.',
                onTap: () =>
                    Navigator.pop(context, QuizStyle.multipleChoice),
              ),
              const SizedBox(height: 10),
              _ModeTile(
                icon: Icons.keyboard_alt_outlined,
                title: 'Typing',
                subtitle: 'Type every answer, in both directions.',
                onTap: () => Navigator.pop(context, QuizStyle.typing),
              ),
              const SizedBox(height: 10),
              _ModeTile(
                icon: Icons.all_inclusive,
                title: 'Both',
                subtitle: 'Each card must clear multiple choice AND '
                    'typing in both directions.',
                onTap: () => Navigator.pop(context, QuizStyle.both),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
    if (style == null || !context.mounted) return;

    // Typed answers in math/general decks can be judged by AI, since
    // equivalent notation ("0.5" vs "1/2") shouldn't count as wrong.
    if (!deck.isLanguage && style != QuizStyle.multipleChoice) {
      final picked = await showDialog<GradingMode>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('How should typed answers be graded?'),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _ModeTile(
                  icon: Icons.auto_awesome,
                  title: 'AI grading',
                  subtitle: 'An AI accepts equivalent answers — different '
                      'notation or wording still counts.',
                  onTap: () => Navigator.pop(context, GradingMode.ai),
                ),
                const SizedBox(height: 10),
                _ModeTile(
                  icon: Icons.spellcheck,
                  title: 'Exact match',
                  subtitle: 'Character-for-character comparison (ignoring '
                      'case and punctuation).',
                  onTap: () => Navigator.pop(context, GradingMode.exact),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
          ],
        ),
      );
      if (picked == null || !context.mounted) return;
      grading = picked;
    }
  }

  Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => QuizScreen(
          store: store,
          deck: deck,
          mode: mode,
          style: style!,
          grading: grading),
    ),
  );
}

class _ModeTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool enabled;
  final VoidCallback onTap;

  const _ModeTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    final color = enabled ? SprakTheme.ink : SprakTheme.inkSoft;
    return Material(
      color: SprakTheme.panel,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: enabled ? onTap : null,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: SprakTheme.line),
          ),
          child: Row(
            children: [
              Icon(icon,
                  size: 26,
                  color: enabled ? SprakTheme.fjord : SprakTheme.inkSoft),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: TextStyle(
                            color: color,
                            fontWeight: FontWeight.w800,
                            fontSize: 15)),
                    const SizedBox(height: 2),
                    Text(subtitle,
                        style: TextStyle(
                            color: SprakTheme.inkSoft, fontSize: 12.5)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
