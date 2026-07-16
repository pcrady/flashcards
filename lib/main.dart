import 'package:flutter/material.dart';

import 'screens/deck_list_screen.dart';
import 'storage.dart';
import 'theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const SprakApp());
}

class SprakApp extends StatefulWidget {
  const SprakApp({super.key});

  @override
  State<SprakApp> createState() => _SprakAppState();
}

class _SprakAppState extends State<SprakApp> {
  final DeckStore store = DeckStore();

  @override
  void initState() {
    super.initState();
    store.load();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'språk',
      debugShowCheckedModeBanner: false,
      theme: SprakTheme.dark(),
      // Make all text in the app selectable (for copying words). The
      // Overlay hosts SelectionArea's handles/context menu — the builder
      // sits above the Navigator, so there isn't one yet.
      builder: (context, child) => Overlay(
        initialEntries: [
          OverlayEntry(
            builder: (_) => SelectionArea(
              child: child ?? const SizedBox.shrink(),
            ),
          ),
        ],
      ),
      home: DeckListScreen(store: store),
    );
  }
}
