import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_xlog_example/main.dart';

void main() {
  testWidgets('renders xlog example controls', (WidgetTester tester) async {
    await tester.pumpWidget(const XLogExampleApp());

    expect(find.text('flutter_xlog example'), findsOneWidget);
    expect(find.text('Status: Not initialized'), findsOneWidget);
    expect(find.text('Initialize xlog'), findsOneWidget);
    expect(find.text('Write sample logs'), findsOneWidget);
    expect(find.text('Flush logs'), findsOneWidget);
    expect(find.text('Close xlog'), findsOneWidget);
    expect(tester.widget<FilledButton>(find.byType(FilledButton).first).enabled, isTrue);
  });
}
