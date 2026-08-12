import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sprak/main.dart';
import 'package:sprak/theme.dart';

void main() {
  tearDown(() => SprakTheme.skin.value = SprakSkin.aurora);

  testWidgets('the app bar button flips the whole app to the hacker skin',
      (tester) async {
    await tester.pumpWidget(const SprakApp());
    await tester.pump();

    ThemeData themeOf(WidgetTester t) =>
        Theme.of(t.element(find.byType(Scaffold).first));

    expect(themeOf(tester).scaffoldBackgroundColor, SprakPalette.aurora.bg);
    expect(find.byType(CrtOverlay), findsOneWidget);

    await tester.tap(find.byType(SkinToggleButton));
    // Long enough for MaterialApp's theme crossfade to land.
    await tester.pump(const Duration(milliseconds: 400));

    expect(SprakTheme.skin.value, SprakSkin.hacker);
    expect(themeOf(tester).scaffoldBackgroundColor, SprakPalette.hacker.bg);
    expect(SprakTheme.fjord, SprakPalette.hacker.fjord);

    // Toggling back restores the original look.
    await tester.tap(find.byType(SkinToggleButton));
    await tester.pump(const Duration(milliseconds: 400));
    expect(themeOf(tester).scaffoldBackgroundColor, SprakPalette.aurora.bg);
  });
}
