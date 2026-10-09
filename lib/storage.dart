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

  /// The write in progress, and whether another one is already queued
  /// behind it. Writes are chained rather than fired off in parallel, so
  /// two of them can never interleave in the file, and everything asked
  /// for while one is running collapses into a single follow-up write of
  /// the latest state — a burst of edits costs one write, not one each.
  Future<void> _writing = Future<void>.value();
  bool _writeQueued = false;

  /// Persists the current state and tells listeners about it. Listeners
  /// are notified straight away, so the UI never waits on the disk; the
  /// returned future completes when the write has landed.
  Future<void> save() {
    notifyListeners();
    // A queued write has not taken its snapshot yet, so it will pick up
    // this change too.
    if (_writeQueued) return _writing;
    _writeQueued = true;
    _writing = _writing.then((_) {
      // Snapshot now, on this turn of the loop: from here on a save has
      // to queue a fresh write of its own.
      _writeQueued = false;
      return _write();
    });
    return _writing;
  }

  Future<void> _write() async {
    try {
      final payload = jsonEncode({
        'folders': folders.map((f) => f.toJson()).toList(),
        'decks': decks.map((d) => d.toJson()).toList(),
      });
      final file = await _file();
      // Written beside the real file and moved into place, so a crash or
      // a full disk part-way through leaves the previous save intact
      // instead of truncating every deck.
      final temp = File('${file.path}.tmp');
      await temp.writeAsString(payload, flush: true);
      await temp.rename(file.path);
    } catch (e) {
      // Swallowed rather than rethrown: a failed write must not break the
      // chain, or no later save would ever run.
      debugPrint('Failed to save decks: $e');
    }
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
