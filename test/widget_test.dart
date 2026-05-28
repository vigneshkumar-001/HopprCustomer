import 'package:flutter_test/flutter_test.dart';

import 'package:hopper/main.dart';
import 'package:hopper/Presentation/Authentication/screens/splash_screens.dart';

void main() {
  testWidgets('App boots to splash screen', (WidgetTester tester) async {
    await tester.pumpWidget(const MyApp());
    await tester.pump();
    expect(find.byType(SplashScreens), findsOneWidget);
  });
}
