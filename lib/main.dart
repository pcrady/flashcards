import 'package:flutter/material.dart';

import 'screens/deck_list_screen.dart';
import 'storage.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Restore the saved skin first so the app never flashes the other theme.
  await SprakTheme.loadSkin();
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
    SprakTheme.skin.addListener(_onSkinChanged);
  }

  @override
  void dispose() {
    SprakTheme.skin.removeListener(_onSkinChanged);
    super.dispose();
  }

  /// Widgets read palette colors through [SprakTheme]'s statics rather than
  /// through an InheritedWidget, so a plain setState would leave any const
  /// subtree painting the old skin. Mark every element dirty instead — this
  /// happens once per toggle, from a tap, never during a build.
  void _onSkinChanged() {
    setState(() {});
    void markDirty(Element element) {
      element.markNeedsBuild();
      element.visitChildren(markDirty);
    }

    (context as Element).visitChildren(markDirty);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'språk',
      debugShowCheckedModeBanner: false,
      theme: SprakTheme.dark(),
      builder: (context, child) => CrtOverlay(child: child ?? const SizedBox()),
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
