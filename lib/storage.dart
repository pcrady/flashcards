import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'models.dart';

/// Loads and persists decks and folders as a JSON file in the app support
/// directory. The file is either a bare list of decks (legacy) or a map
/// {"folders": [...], "decks": [...]}.
class DeckStore extends ChangeNotifier {
  final List<Deck> decks = [];
  final List<Folder> folders = [];
  bool loaded = false;

  Future<File> _file() async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}/decks.json');
  }

  Future<void> load() async {
    try {
      final file = await _file();
      if (await file.exists()) {
        final data = jsonDecode(await file.readAsString());
        decks.clear();
        folders.clear();
        if (data is List) {
          decks.addAll(
              data.map((d) => Deck.fromJson(d as Map<String, dynamic>)));
        } else if (data is Map<String, dynamic>) {
          folders.addAll((data['folders'] as List<dynamic>? ?? [])
              .map((f) => Folder.fromJson(f as Map<String, dynamic>)));
          decks.addAll((data['decks'] as List<dynamic>? ?? [])
              .map((d) => Deck.fromJson(d as Map<String, dynamic>)));
        }
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
      await file.writeAsString(jsonEncode({
        'folders': folders.map((f) => f.toJson()).toList(),
        'decks': decks.map((d) => d.toJson()).toList(),
      }));
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

  Future<void> addFolder(Folder folder) async {
    folders.add(folder);
    await save();
  }

  /// Deletes the folder only — its decks move back to the home screen.
  Future<void> deleteFolder(Folder folder) async {
    for (final d in decks) {
      if (d.folderId == folder.id) d.folderId = null;
    }
    folders.removeWhere((f) => f.id == folder.id);
    await save();
  }
}
