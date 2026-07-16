import 'package:flutter/material.dart';

import '../models.dart';
import '../theme.dart';

Color masteryColor(Mastery m) => switch (m) {
      Mastery.newCard => SprakTheme.inkSoft,
      Mastery.learning => const Color(0xFFF5B84E), // amber
      Mastery.strong => SprakTheme.success,
      Mastery.fading => SprakTheme.magenta,
    };

String masteryLabel(Mastery m) => switch (m) {
      Mastery.newCard => 'New',
      Mastery.learning => 'Learning',
      Mastery.strong => 'Strong',
      Mastery.fading => 'Fading',
    };

/// Tooltip text for one card's retention state.
String masteryTooltip(CardItem card) {
  final m = card.mastery;
  if (m == Mastery.newCard) return 'New — not studied yet';
  final days = DateTime.now().difference(card.lastReviewedAt!).inDays;
  final when = days == 0
      ? 'today'
      : days == 1
          ? 'yesterday'
          : '$days days ago';
  return '${masteryLabel(m)} — streak ${card.streak}, last studied $when';
}

/// Order the mastery buckets are shown in everywhere.
const masteryOrder = [
  Mastery.strong,
  Mastery.learning,
  Mastery.fading,
  Mastery.newCard,
];

/// Thin stacked bar showing a deck's mastery mix.
class MasteryBar extends StatelessWidget {
  final Deck deck;
  final double height;
  const MasteryBar(this.deck, {super.key, this.height = 6});

  @override
  Widget build(BuildContext context) {
    if (deck.cards.isEmpty) return const SizedBox.shrink();
    final counts = deck.masteryCounts;
    return Tooltip(
      message: [
        for (final m in masteryOrder)
          if (counts[m]! > 0)
            '${counts[m]} ${masteryLabel(m).toLowerCase()}',
      ].join('  ·  '),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(999),
        child: SizedBox(
          height: height,
          child: Row(
            children: [
              for (final m in masteryOrder)
                if (counts[m]! > 0)
                  Expanded(
                    flex: counts[m]!,
                    child: Container(
                      color: masteryColor(m).withValues(
                          alpha: m == Mastery.newCard ? 0.35 : 0.85),
                    ),
                  ),
            ],
          ),
        ),
      ),
    );
  }
}

/// "Retention 87%" with an explanatory tooltip; an em-dash before any
/// re-encounters exist to measure.
class RetentionLabel extends StatelessWidget {
  final Deck deck;
  final double fontSize;
  const RetentionLabel(this.deck, {super.key, this.fontSize = 13});

  @override
  Widget build(BuildContext context) {
    final r = deck.retention;
    final color = r == null
        ? SprakTheme.inkSoft
        : r >= 0.85
            ? SprakTheme.success
            : r >= 0.7
                ? const Color(0xFFF5B84E)
                : SprakTheme.danger;
    return Tooltip(
      message: 'Of the cards you had already studied, the share answered '
          'correctly on the first try when you met them again '
          '(last 30 days).',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Retention ',
              style: TextStyle(color: SprakTheme.inkSoft, fontSize: fontSize)),
          Text(
            r == null ? '—' : '${(r * 100).round()}%',
            style: TextStyle(
                color: color,
                fontSize: fontSize,
                fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}
