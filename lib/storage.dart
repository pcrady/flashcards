import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'models.dart';

/// Loads and persists decks as a JSON file in the app support directory.
class DeckStore extends ChangeNotifier {
  final List<Deck> decks = [];
  bool loaded = false;

  Future<File> _file() async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}/decks.json');
  }

  Future<void> load() async {
    try {
      final file = await _file();
      if (await file.exists()) {
        final data = jsonDecode(await file.readAsString()) as List<dynamic>;
        decks
          ..clear()
          ..addAll(
              data.map((d) => Deck.fromJson(d as Map<String, dynamic>)));
      }
    } catch (e) {
      debugPrint('Failed to load decks: $e');
    }
    loaded = true;
    notifyListeners();
  }

  Future<void> save() async {
    try {
      final file = await _file();
      await file
          .writeAsString(jsonEncode(decks.map((d) => d.toJson()).toList()));
    } catch (e) {
      debugPrint('Failed to save decks: $e');
    }
    notifyListeners();
  }

  Future<void> addDeck(Deck deck) async {
    decks.add(deck);
    await save();
  }

  Future<void> deleteDeck(Deck deck) async {
    decks.removeWhere((d) => d.id == deck.id);
    await save();
  }
}
