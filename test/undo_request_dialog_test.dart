import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:warehouse_poc/theme.dart';
import 'package:warehouse_poc/widgets/undo_request_dialog.dart';

void main() {
  Future<void> pumpLauncher(
    WidgetTester tester,
    ValueChanged<String?> onReasonChanged,
  ) async {
    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(),
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () => showUndoRequestDialog(
            context,
            materialName: 'Rail sleeper',
            quantity: 12,
            currentDecision: 'Accepted',
            onReasonChanged: onReasonChanged,
          ),
          child: const Text('Open'),
        ),
      ),
    ));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
  }

  testWidgets('cancel closes safely without returning a reason',
      (tester) async {
    var calls = 0;
    await pumpLauncher(tester, (_) => calls++);
    await tester.enterText(
      find.byKey(const ValueKey('undo-reason-field')),
      'not submitted',
    );

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(calls, 0);
    expect(find.text('Undo Request Decision'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('confirmation trims and returns the reason once', (tester) async {
    final reasons = <String?>[];
    await pumpLauncher(tester, reasons.add);
    await tester.enterText(
      find.byKey(const ValueKey('undo-reason-field')),
      '  wrong decision  ',
    );

    await tester.tap(find.byKey(const ValueKey('confirm-undo-request')));
    await tester.pumpAndSettle();

    expect(reasons, ['wrong decision']);
    expect(find.text('Undo Request Decision'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('dialog fits a narrow Android-sized surface', (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 568));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await pumpLauncher(tester, (_) {});
    await tester.enterText(
      find.byKey(const ValueKey('undo-reason-field')),
      List.filled(40, 'long reason').join(' '),
    );
    await tester.pump();

    expect(find.text('Undo Request Decision'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
