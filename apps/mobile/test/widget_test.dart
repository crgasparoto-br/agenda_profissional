import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/theme/app_theme.dart';

void main() {
  testWidgets('App theme applies brand colors', (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: const Scaffold(body: Text('Agenda Profissional')),
      ),
    );

    final material = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(material.theme?.colorScheme.primary, AppColors.primary);
    expect(find.text('Agenda Profissional'), findsOneWidget);
  });
}
