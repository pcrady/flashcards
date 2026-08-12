import 'package:flutter/material.dart';

import '../models.dart';
import '../screens/quiz_screen.dart';
import '../storage.dart';
import '../theme.dart';
import 'tag_chips.dart';

/// Asks which tags to study and how (whole deck / continue / focus on
/// mistakes), how to answer (multiple choice / typing / both), and which
/// side to be quizzed on (front / back / both), then opens the quiz.
/// Resuming skips the follow-up questions — the choices are saved in the
/// session, whose card set is already fixed, so the tag filter is ignored
/// there.
///
/// [initialTags] seeds the tag filter, so a deck list already narrowed on
/// screen studies the same slice without picking the tags twice.
Future<void> startLearning(
  BuildContext context,
  DeckStore store,
  Deck deck, {
  List<String> initialTags = const [],
}) async {
  if (deck.cards.isEmpty) return;

  var tags = deck.keepKnownTags(initialTags);
  final session = deck.session;
  final mode = await showDialog<QuizMode>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) {
        final pool = deck.cardsWithAnyTag(tags);
        final canStart = pool.isNotEmpty;
        return AlertDialog(
          title: Text('Study “${deck.name}”'),
          content: SizedBox(
            width: 460,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (deck.tags.isNotEmpty) ...[
                  TagFilterBar(
                    deck: deck,
                    selected: tags,
                    label: 'Study only',
                    onChanged: (next) => setState(() => tags = next),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    canStart
                        ? '${pool.length} of ${deck.cards.length} '
                            '${deck.cards.length == 1 ? "card" : "cards"} '
                            'selected.'
                        : 'No cards carry those tags.',
                    style: TextStyle(
                      color: canStart
                          ? SprakTheme.inkSoft
                          : Theme.of(context).colorScheme.error,
                      fontSize: 12.5,
                    ),
                  ),
                  const SizedBox(height: 14),
                ],
                _ModeTile(
                  icon: Icons.shuffle,
                  title: tags.isEmpty ? 'Whole deck' : 'Every selected card',
                  subtitle: 'Shuffled into groups of six.',
                  enabled: canStart,
                  onTap: () => Navigator.pop(context, QuizMode.whole),
                ),
                const SizedBox(height: 10),
                _ModeTile(
                  icon: Icons.play_circle_outline,
                  title: 'Pick up where you left off',
                  subtitle: session != null
                      ? 'Continue from group ${session.groupIndex + 1} of '
                          '${session.groups.length} — the saved session '
                          'keeps its own cards.'
                      : 'No session in progress.',
                  enabled: session != null,
                  onTap: () => Navigator.pop(context, QuizMode.resume),
                ),
                const SizedBox(height: 10),
                _ModeTile(
                  icon: Icons.local_fire_department_outlined,
                  title: 'Focus on mistakes',
                  subtitle:
                      'Drill just the hardest slice — the words you miss '
                      'most and the ones you’ve barely practiced.',
                  enabled: canStart,
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
        );
      },
    ),
  );

  if (mode == null || !context.mounted) return;

  // "Focus on mistakes" studies only a slice of the deck — the hardest
  // cards — so ask how big a slice.
  var mistakeFraction = 1.0;
  if (mode == QuizMode.mistakes) {
    final fraction = await showDialog<double>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('How much to focus on?'),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Study just your hardest cards — the ones you miss most '
                'often (by wrong-to-correct ratio), along with any you’ve '
                'practiced fewer than 30 times. Pick how big a slice.',
                style: TextStyle(color: SprakTheme.inkSoft, fontSize: 13),
              ),
              const SizedBox(height: 18),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (final pct in [10, 20, 30, 40, 50, 60, 70, 80, 90])
                    OutlinedButton(
                      onPressed: () => Navigator.pop(context, pct / 100),
                      child: Text('Top $pct%'),
                    ),
                ],
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
    if (fraction == null || !context.mounted) return;
    mistakeFraction = fraction;
  }

  QuizStyle? style;
  var grading = GradingMode.exact;
  var direction = QuizDirection.both;
  if (mode == QuizMode.resume) {
    style = session?.style ?? QuizStyle.typing;
    grading = session?.grading ?? GradingMode.exact;
    direction = session?.direction ?? QuizDirection.both;
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
                subtitle: 'Type every answer.',
                onTap: () => Navigator.pop(context, QuizStyle.typing),
              ),
              const SizedBox(height: 10),
              _ModeTile(
                icon: Icons.all_inclusive,
                title: 'Both',
                subtitle: 'Each card must clear multiple choice AND '
                    'typing.',
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

    final pickedDirection = await showDialog<QuizDirection>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Which side do you want to be quizzed on?'),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _ModeTile(
                icon: Icons.arrow_forward,
                title: '${deck.targetLabel} → ${deck.nativeLabel}',
                subtitle: 'See the ${deck.targetLabel} side, answer with '
                    'the ${deck.nativeLabel} side.',
                onTap: () => Navigator.pop(context, QuizDirection.front),
              ),
              const SizedBox(height: 10),
              _ModeTile(
                icon: Icons.arrow_back,
                title: '${deck.nativeLabel} → ${deck.targetLabel}',
                subtitle: 'See the ${deck.nativeLabel} side, answer with '
                    'the ${deck.targetLabel} side.',
                onTap: () => Navigator.pop(context, QuizDirection.back),
              ),
              const SizedBox(height: 10),
              _ModeTile(
                icon: Icons.swap_horiz,
                title: 'Both directions',
                subtitle: 'Each card is asked both ways.',
                onTap: () => Navigator.pop(context, QuizDirection.both),
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
    if (pickedDirection == null || !context.mounted) return;
    direction = pickedDirection;

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
          grading: grading,
          direction: direction,
          mistakeFraction: mistakeFraction,
          tags: tags),
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
