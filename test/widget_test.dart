import 'package:flutter_test/flutter_test.dart';
import 'package:sprak/main.dart';

void main() {
  testWidgets('App renders the deck list', (WidgetTester tester) async {
    await tester.pumpWidget(const SprakApp());
    expect(find.text('Språk'), findsOneWidget);
  });
}
