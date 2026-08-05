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
      // NOTE: no app-wide SelectionArea. A SelectableRegion installs a
      // translucent tap-and-pan recognizer over everything beneath it and
      // grabs primary focus on every mouse-down, so wrapping the whole app
      // made buttons swallow clicks (a 2px drag beats the button's tap) and
      // killed the quiz's keyboard shortcuts. Selection is opted into
      // around read-only text instead — see [SelectableText] usages.
      home: DeckListScreen(store: store),
    );
  }
}
