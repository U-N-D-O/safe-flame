import 'package:flutter_test/flutter_test.dart';
import 'package:safe_flame/main.dart';

void main() {
  testWidgets('Safe Flame renders', (tester) async {
    await tester.pumpWidget(const SafeFlameApp());

    expect(find.byType(SafeFlameHome), findsOneWidget);
  });
}
