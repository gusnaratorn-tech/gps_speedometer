import 'package:flutter_test/flutter_test.dart';
import 'package:gps_speedometer/main.dart';

void main() {
  testWidgets('SpeedometerApp smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const SpeedometerApp());
    expect(find.text('SPEEDOMETER'), findsOneWidget);
  });
}
