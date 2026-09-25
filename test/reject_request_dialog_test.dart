import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:warehouse_poc/theme.dart';
import 'package:warehouse_poc/widgets/reject_request_dialog.dart';

void main() {
  Future<void> pumpLauncher(
    WidgetTester tester,
    Future<String?> Function(String? reason) reject,
  ) async {
    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(),
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () => showRejectRequestDialog(
            context,
            onReject: reject,
          ),
          child: const Text('Open'),
        ),
      ),
    ));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
  }

  testWidgets('cancel closes safely without using a disposed controller',
      (tester) async {
    await pumpLauncher(tester, (_) async => null);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(find.text('Reject Request'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('success trims reason, blocks double submit, and closes once',
      (tester) async {
    final completion = Completer<String?>();
    var calls = 0;
    String? receivedReason;
    await pumpLauncher(tester, (reason) {
      calls++;
      receivedReason = reason;
      return completion.future;
    });
    await tester.enterText(
      find.byKey(const ValueKey('rejection-reason-field')),
      '  damaged item  ',
    );

    final reject = find.byKey(const ValueKey('confirm-rejection'));
    await tester.tap(reject);
    await tester.tap(reject, warnIfMissed: false);
    await tester.pump();

    expect(calls, 1);
    expect(receivedReason, 'damaged item');
    expect(find.text('Rejecting...'), findsOneWidget);

    completion.complete(null);
    await tester.pumpAndSettle();

    expect(find.text('Reject Request'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('failure preserves reason and restores Reject action',
      (tester) async {
    await pumpLauncher(tester, (_) async => 'Could not reject the request.');
    final field = find.byKey(const ValueKey('rejection-reason-field'));
    await tester.enterText(field, 'Keep this reason');

    await tester.tap(find.byKey(const ValueKey('confirm-rejection')));
    await tester.pumpAndSettle();

    expect(find.text('Reject Request'), findsOneWidget);
    expect(find.text('Reject'), findsOneWidget);
    expect(find.text('Could not reject the request.'), findsOneWidget);
    expect(
        tester.widget<TextField>(field).controller!.text, 'Keep this reason');
    expect(tester.takeException(), isNull);
  });

  for (final size in [const Size(1200, 800), const Size(320, 568)]) {
    testWidgets('dialog fits ${size.width.toInt()}px without overflow',
        (tester) async {
      await tester.binding.setSurfaceSize(size);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await pumpLauncher(tester, (_) async => null);

      await tester.enterText(
        find.byKey(const ValueKey('rejection-reason-field')),
        List.filled(40, 'long reason').join(' '),
      );
      await tester.pump();

      expect(find.text('Reject Request'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
