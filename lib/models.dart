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

/// One first-attempt answer to a card, kept as the card's review history
/// so retention can be measured over time.
class CardReview {
  final DateTime at;
  final bool correct;
  CardReview(this.at, this.correct);

  Map<String, dynamic> toJson() =>
      {'at': at.millisecondsSinceEpoch, 'correct': correct};

  factory CardReview.fromJson(Map<String, dynamic> json) => CardReview(
        DateTime.fromMillisecondsSinceEpoch(json['at'] as int? ?? 0),
        json['correct'] as bool? ?? false,
      );
}

/// How well a card is currently retained, derived from its review history.
enum Mastery { newCard, learning, strong, fading }

class CardItem {
  final String id;
  String native;
  String target;
  int timesCorrect;
  int timesWrong;

  /// Labels picked from the deck's tag list (e.g. "verb", "adjective").
  /// A card can carry any number of them.
  List<String> tags;

  /// Free-form note about the card — a nuance of meaning, an example
  /// sentence, a mnemonic. Shown when the card is reviewed, never asked
  /// for as an answer. Empty when the card has none.
  String notes;

  /// First-attempt outcomes, oldest first (retries within a study group
  /// are not recorded).
  final List<CardReview> reviews;

  CardItem({
    String? id,
    required this.native,
    required this.target,
    this.timesCorrect = 0,
    this.timesWrong = 0,
    this.notes = '',
    List<String>? tags,
    List<CardReview>? reviews,
  })  : id = id ?? _uuid.v4(),
        tags = tags ?? [],
        reviews = reviews ?? [];

  /// Reviews less than this far apart belong to one sitting (e.g. both
  /// directions of a card asked in the same session).
  static const _sittingGap = Duration(hours: 12);

  /// Consecutive fully-correct sittings at the end of the history. A
  /// sitting counts only if every first attempt in it was correct, so in
  /// both-directions mode a card must be answered right on both sides to
  /// earn +1; one wrong side resets the streak.
  int get streak {
    var s = 0;
    var i = reviews.length - 1;
    while (i >= 0) {
      var start = i;
      while (start > 0 &&
          reviews[start].at.difference(reviews[start - 1].at) < _sittingGap) {
        start--;
      }
      for (var j = start; j <= i; j++) {
        if (!reviews[j].correct) return s;
      }
      s++;
      i = start - 1;
    }
    return s;
  }

  DateTime? get lastReviewedAt =>
      reviews.isEmpty ? null : reviews.last.at;

  /// New: never studied. Learning: fewer than three fully-correct
  /// sittings in a row. Strong: on a streak and seen recently. Fading:
  /// was strong but untouched for 14+ days — presumed decaying.
  Mastery get mastery {
    if (reviews.isEmpty) return Mastery.newCard;
    if (streak < 3) return Mastery.learning;
    final idle = DateTime.now().difference(reviews.last.at);
    return idle.inDays >= 14 ? Mastery.fading : Mastery.strong;
  }

  /// Records a first-attempt outcome, capping the history length.
  void addReview(bool correct) {
    reviews.add(CardReview(DateTime.now(), correct));
    if (reviews.length > 200) {
      reviews.removeRange(0, reviews.length - 200);
    }
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'native': native,
        'target': target,
        'timesCorrect': timesCorrect,
        'timesWrong': timesWrong,
        if (notes.isNotEmpty) 'notes': notes,
        if (tags.isNotEmpty) 'tags': tags,
        if (reviews.isNotEmpty)
          'reviews': reviews.map((r) => r.toJson()).toList(),
      };

  factory CardItem.fromJson(Map<String, dynamic> json) => CardItem(
        id: json['id'] as String?,
        native: json['native'] as String? ?? '',
        target: json['target'] as String? ?? '',
        timesCorrect: json['timesCorrect'] as int? ?? 0,
        timesWrong: json['timesWrong'] as int? ?? 0,
        notes: json['notes'] as String? ?? '',
        tags: [
          for (final t in json['tags'] as List<dynamic>? ?? []) t as String,
        ],
        reviews: [
          for (final r in json['reviews'] as List<dynamic>? ?? [])
            CardReview.fromJson(r as Map<String, dynamic>),
        ],
      );
}

/// How the learner answers during a quiz.
enum QuizStyle {
  /// Pick the right answer out of four options.
  multipleChoice('choice'),

  /// Type every answer, in both directions.
  typing('typing'),

  /// Multiple choice plus typing in both directions — all must be cleared.
  both('both');

  final String id;
  const QuizStyle(this.id);

  static QuizStyle fromId(String? id) => QuizStyle.values.firstWhere(
        (s) => s.id == id,
        orElse: () => QuizStyle.typing,
      );
}

/// Which side of a card is shown as the prompt during a quiz.
enum QuizDirection {
  /// Show the target/front side; answer with the native/back side.
  front('front'),

  /// Show the native/back side; answer with the target/front side.
  back('back'),

  /// Ask each card in both directions.
  both('both');

  final String id;
  const QuizDirection(this.id);

  static QuizDirection fromId(String? id) => QuizDirection.values.firstWhere(
        (d) => d.id == id,
        orElse: () => QuizDirection.both,
      );
}

/// How typed answers are evaluated during a quiz.
enum GradingMode {
  /// Character-for-character comparison (after the usual normalization).
  exact('exact'),

  /// An LLM judges whether the answer is equivalent to the expected one.
  ai('ai');

  final String id;
  const GradingMode(this.id);

  static GradingMode fromId(String? id) => GradingMode.values.firstWhere(
        (g) => g.id == id,
        orElse: () => GradingMode.exact,
      );
}

/// A card asked in one direction, referenced by ID for persistence.
class QuizTaskRef {
  final String cardId;
  final bool askInTarget;

  /// True for a multiple-choice task, false for typed.
  final bool isChoice;
  QuizTaskRef(this.cardId, this.askInTarget, {this.isChoice = false});

  Map<String, dynamic> toJson() =>
      {'cardId': cardId, 'askInTarget': askInTarget, 'isChoice': isChoice};

  factory QuizTaskRef.fromJson(Map<String, dynamic> json) => QuizTaskRef(
        json['cardId'] as String,
        json['askInTarget'] as bool? ?? true,
        isChoice: json['isChoice'] as bool? ?? false,
      );
}

/// A saved mid-study session, so the learner can pick up where they
/// left off.
class QuizSession {
  final List<List<String>> groups; // card IDs per group
  final int groupIndex;
  final List<QuizTaskRef> remaining;
  final QuizStyle style;
  final GradingMode grading;
  final QuizDirection direction;

  QuizSession({
    required this.groups,
    required this.groupIndex,
    required this.remaining,
    this.style = QuizStyle.typing,
    this.grading = GradingMode.exact,
    this.direction = QuizDirection.both,
  });

  Map<String, dynamic> toJson() => {
        'groups': groups,
        'groupIndex': groupIndex,
        'remaining': remaining.map((t) => t.toJson()).toList(),
        'style': style.id,
        'grading': grading.id,
        'direction': direction.id,
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
        style: QuizStyle.fromId(json['style'] as String?),
        grading: GradingMode.fromId(json['grading'] as String?),
        direction: QuizDirection.fromId(json['direction'] as String?),
      );
}

/// A named group of decks shown as a folder on the home screen.
class Folder {
  final String id;
  String name;
  Folder({String? id, required this.name}) : id = id ?? _uuid.v4();

  Map<String, dynamic> toJson() => {'id': id, 'name': name};

  factory Folder.fromJson(Map<String, dynamic> json) => Folder(
        id: json['id'] as String?,
        name: json['name'] as String? ?? 'Untitled',
      );
}

/// What a deck teaches. Language decks translate between two languages;
/// math and general decks pair a question with an answer.
enum DeckKind {
  language('language', 'Language'),
  math('math', 'Math'),
  general('general', 'General');

  final String id;
  final String label;
  const DeckKind(this.id, this.label);

  static DeckKind fromId(String? id) => DeckKind.values.firstWhere(
        (k) => k.id == id,
        orElse: () => DeckKind.language,
      );
}

class Deck {
  final String id;
  String name;

  /// ID of the folder this deck lives in, or null for the home screen.
  String? folderId;

  DeckKind kind;

  /// The language being learned (e.g. Russian). Unused for non-language
  /// decks, where the "target" side of a card is the question.
  String targetLanguage;

  /// The language the user already speaks (e.g. English). Unused for
  /// non-language decks, where the "native" side is the answer.
  String nativeLanguage;
  final List<CardItem> cards;

  /// The tags cards in this deck may carry, in the order they were
  /// created. Tags are per-deck — a card can only use one listed here.
  final List<String> tags;

  bool get isLanguage => kind == DeckKind.language;

  /// Label for a card's target side ("Russian" / "Front").
  String get targetLabel => isLanguage ? targetLanguage : 'Front';

  /// Label for a card's native side ("English" / "Back").
  String get nativeLabel => isLanguage ? nativeLanguage : 'Back';

  /// Emoji shown on deck tiles and title bars.
  String get emblem => switch (kind) {
        DeckKind.language => flagFor(targetLanguage),
        DeckKind.math => '📐',
        DeckKind.general => '💡',
      };

  /// In-progress study session, if the learner left mid-deck.
  QuizSession? session;

  /// True retention over the last 30 days: of first attempts on cards the
  /// learner had already studied in an earlier sitting (12h+ before), the
  /// share answered correctly. Null until there are re-encounters.
  double? get retention {
    var seen = 0, correct = 0;
    final cutoff = DateTime.now().subtract(const Duration(days: 30));
    for (final card in cards) {
      if (card.reviews.length < 2) continue;
      final firstAt = card.reviews.first.at;
      for (final r in card.reviews.skip(1)) {
        if (r.at.isBefore(cutoff)) continue;
        // Same-sitting tasks (e.g. the other direction minutes later)
        // aren't evidence of retention — require a later sitting.
        if (r.at.difference(firstAt) < const Duration(hours: 12)) continue;
        seen++;
        if (r.correct) correct++;
      }
    }
    return seen == 0 ? null : correct / seen;
  }

  // NUL-separated so the two sides can't bleed into each other
  // (e.g. "a b"/"c" vs "a"/"b c").
  static String _dupKey(CardItem c) =>
      '${c.native.trim().toLowerCase()}\u0000${c.target.trim().toLowerCase()}';

  /// Cards that appear more than once — same native and target text after
  /// trimming and lowercasing. Each inner list is one set of duplicates,
  /// in deck order.
  List<List<CardItem>> findDuplicateCards() {
    final groups = <String, List<CardItem>>{};
    for (final c in cards) {
      groups.putIfAbsent(_dupKey(c), () => []).add(c);
    }
    return [
      for (final g in groups.values)
        if (g.length > 1) g,
    ];
  }

  /// Whether the deck already holds a card with this native/target pair,
  /// ignoring case and surrounding whitespace. [excluding] skips one card
  /// (e.g. the card currently being edited).
  bool containsCard(String native, String target, {CardItem? excluding}) {
    final key = '${native.trim().toLowerCase()}'
        '\u0000${target.trim().toLowerCase()}';
    return cards.any((c) => c != excluding && _dupKey(c) == key);
  }

  static String _tagKey(String name) => name.trim().toLowerCase();

  /// The deck's tag matching [name] ignoring case and surrounding space,
  /// or null if it has none.
  String? findTag(String name) {
    final key = _tagKey(name);
    for (final t in tags) {
      if (_tagKey(t) == key) return t;
    }
    return null;
  }

  /// Adds [name] to the deck's tag list unless an equivalent tag already
  /// exists. Returns the canonical name to store on cards — the existing
  /// tag when there was one — or null if [name] was blank.
  String? addTag(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return null;
    final existing = findTag(trimmed);
    if (existing != null) return existing;
    tags.add(trimmed);
    return trimmed;
  }

  /// Renames a tag on the deck and on every card carrying it. Merges into
  /// [to] if the deck already has that tag.
  void renameTag(String from, String to) {
    final trimmed = to.trim();
    final old = findTag(from);
    if (old == null || trimmed.isEmpty || old == trimmed) return;
    final clash = findTag(trimmed);
    if (clash != null && clash != old) {
      // Merging: drop the old name and make sure its cards get the kept one.
      tags.remove(old);
      for (final c in cards) {
        if (c.tags.remove(old) && !c.tags.contains(clash)) c.tags.add(clash);
      }
      return;
    }
    tags[tags.indexOf(old)] = trimmed;
    for (final c in cards) {
      final i = c.tags.indexOf(old);
      if (i != -1) c.tags[i] = trimmed;
    }
  }

  /// Drops a tag from the deck and from every card carrying it.
  void removeTag(String name) {
    final tag = findTag(name);
    if (tag == null) return;
    tags.remove(tag);
    for (final c in cards) {
      c.tags.remove(tag);
    }
  }

  /// The cards a tag filter selects: every card when [tags] is empty,
  /// otherwise the cards carrying at least one of them (any, not all).
  /// Deck order is preserved.
  List<CardItem> cardsWithAnyTag(List<String> tags) {
    if (tags.isEmpty) return List.of(cards);
    return cards.where((c) => tags.any(c.tags.contains)).toList();
  }

  /// [tags] with anything the deck no longer defines dropped — a filter
  /// must never outlive a renamed or deleted tag.
  List<String> keepKnownTags(List<String> tags) =>
      [for (final t in tags) if (this.tags.contains(t)) t];

  /// How many cards carry [name].
  int tagUseCount(String name) {
    final tag = findTag(name);
    if (tag == null) return 0;
    return cards.where((c) => c.tags.contains(tag)).length;
  }

  Map<Mastery, int> get masteryCounts {
    final counts = {for (final m in Mastery.values) m: 0};
    for (final c in cards) {
      counts[c.mastery] = counts[c.mastery]! + 1;
    }
    return counts;
  }

  Deck({
    String? id,
    required this.name,
    required this.targetLanguage,
    required this.nativeLanguage,
    this.kind = DeckKind.language,
    List<CardItem>? cards,
    List<String>? tags,
    this.session,
    this.folderId,
  })  : id = id ?? _uuid.v4(),
        cards = cards ?? [],
        tags = tags ?? [];

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'kind': kind.id,
        'targetLanguage': targetLanguage,
        'nativeLanguage': nativeLanguage,
        'cards': cards.map((c) => c.toJson()).toList(),
        if (tags.isNotEmpty) 'tags': tags,
        if (session != null) 'session': session!.toJson(),
        if (folderId != null) 'folderId': folderId,
      };

  factory Deck.fromJson(Map<String, dynamic> json) {
    final deck = Deck(
      id: json['id'] as String?,
      name: json['name'] as String? ?? 'Untitled',
      kind: DeckKind.fromId(json['kind'] as String?),
      targetLanguage: json['targetLanguage'] as String? ?? 'Russian',
      nativeLanguage: json['nativeLanguage'] as String? ?? 'English',
      cards: (json['cards'] as List<dynamic>? ?? [])
          .map((c) => CardItem.fromJson(c as Map<String, dynamic>))
          .toList(),
      tags: [
        for (final t in json['tags'] as List<dynamic>? ?? []) t as String,
      ],
      session: json['session'] != null
          ? QuizSession.fromJson(json['session'] as Map<String, dynamic>)
          : null,
      folderId: json['folderId'] as String?,
    );
    // Cards are the source of truth if the two ever disagree, so a tag
    // saved on a card always stays pickable.
    for (final c in deck.cards) {
      for (final t in c.tags) {
        deck.addTag(t);
      }
    }
    return deck;
  }
}
