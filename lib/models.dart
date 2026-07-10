import 'package:uuid/uuid.dart';

const _uuid = Uuid();

class Language {
  final String name;
  final String ttsLocale;
  final String flag;
  const Language(this.name, this.ttsLocale, this.flag);
}

const List<Language> kLanguages = [
  Language('English', 'en-US', '🇬🇧'),
  Language('Russian', 'ru-RU', '🇷🇺'),
  Language('Spanish', 'es-ES', '🇪🇸'),
  Language('French', 'fr-FR', '🇫🇷'),
  Language('German', 'de-DE', '🇩🇪'),
  Language('Italian', 'it-IT', '🇮🇹'),
  Language('Portuguese', 'pt-BR', '🇧🇷'),
  Language('Swedish', 'sv-SE', '🇸🇪'),
  Language('Norwegian', 'nb-NO', '🇳🇴'),
  Language('Danish', 'da-DK', '🇩🇰'),
  Language('Dutch', 'nl-NL', '🇳🇱'),
  Language('Polish', 'pl-PL', '🇵🇱'),
  Language('Ukrainian', 'uk-UA', '🇺🇦'),
  Language('Japanese', 'ja-JP', '🇯🇵'),
  Language('Korean', 'ko-KR', '🇰🇷'),
  Language('Chinese (Mandarin)', 'zh-CN', '🇨🇳'),
  Language('Arabic', 'ar-SA', '🇸🇦'),
  Language('Hindi', 'hi-IN', '🇮🇳'),
  Language('Turkish', 'tr-TR', '🇹🇷'),
  Language('Greek', 'el-GR', '🇬🇷'),
];

String ttsLocaleFor(String languageName) {
  for (final l in kLanguages) {
    if (l.name == languageName) return l.ttsLocale;
  }
  return 'en-US';
}

String flagFor(String languageName) {
  for (final l in kLanguages) {
    if (l.name == languageName) return l.flag;
  }
  return '🌍';
}

class CardItem {
  final String id;
  String native;
  String target;
  int timesCorrect;
  int timesWrong;

  CardItem({
    String? id,
    required this.native,
    required this.target,
    this.timesCorrect = 0,
    this.timesWrong = 0,
  }) : id = id ?? _uuid.v4();

  Map<String, dynamic> toJson() => {
        'id': id,
        'native': native,
        'target': target,
        'timesCorrect': timesCorrect,
        'timesWrong': timesWrong,
      };

  factory CardItem.fromJson(Map<String, dynamic> json) => CardItem(
        id: json['id'] as String?,
        native: json['native'] as String? ?? '',
        target: json['target'] as String? ?? '',
        timesCorrect: json['timesCorrect'] as int? ?? 0,
        timesWrong: json['timesWrong'] as int? ?? 0,
      );
}

/// A card asked in one direction, referenced by ID for persistence.
class QuizTaskRef {
  final String cardId;
  final bool askInTarget;
  QuizTaskRef(this.cardId, this.askInTarget);

  Map<String, dynamic> toJson() =>
      {'cardId': cardId, 'askInTarget': askInTarget};

  factory QuizTaskRef.fromJson(Map<String, dynamic> json) => QuizTaskRef(
        json['cardId'] as String,
        json['askInTarget'] as bool? ?? true,
      );
}

/// A saved mid-study session, so the learner can pick up where they
/// left off.
class QuizSession {
  final List<List<String>> groups; // card IDs per group
  final int groupIndex;
  final List<QuizTaskRef> remaining;

  QuizSession({
    required this.groups,
    required this.groupIndex,
    required this.remaining,
  });

  Map<String, dynamic> toJson() => {
        'groups': groups,
        'groupIndex': groupIndex,
        'remaining': remaining.map((t) => t.toJson()).toList(),
      };

  factory QuizSession.fromJson(Map<String, dynamic> json) => QuizSession(
        groups: [
          for (final g in json['groups'] as List<dynamic>? ?? [])
            [for (final id in g as List<dynamic>) id as String],
        ],
        groupIndex: json['groupIndex'] as int? ?? 0,
        remaining: [
          for (final t in json['remaining'] as List<dynamic>? ?? [])
            QuizTaskRef.fromJson(t as Map<String, dynamic>),
        ],
      );
}

class Deck {
  final String id;
  String name;

  /// The language being learned (e.g. Russian).
  String targetLanguage;

  /// The language the user already speaks (e.g. English).
  String nativeLanguage;
  final List<CardItem> cards;

  /// In-progress study session, if the learner left mid-deck.
  QuizSession? session;

  Deck({
    String? id,
    required this.name,
    required this.targetLanguage,
    required this.nativeLanguage,
    List<CardItem>? cards,
    this.session,
  })  : id = id ?? _uuid.v4(),
        cards = cards ?? [];

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'targetLanguage': targetLanguage,
        'nativeLanguage': nativeLanguage,
        'cards': cards.map((c) => c.toJson()).toList(),
        if (session != null) 'session': session!.toJson(),
      };

  factory Deck.fromJson(Map<String, dynamic> json) => Deck(
        id: json['id'] as String?,
        name: json['name'] as String? ?? 'Untitled',
        targetLanguage: json['targetLanguage'] as String? ?? 'Russian',
        nativeLanguage: json['nativeLanguage'] as String? ?? 'English',
        cards: (json['cards'] as List<dynamic>? ?? [])
            .map((c) => CardItem.fromJson(c as Map<String, dynamic>))
            .toList(),
        session: json['session'] != null
            ? QuizSession.fromJson(json['session'] as Map<String, dynamic>)
            : null,
      );
}
