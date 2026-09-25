import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:warehouse_poc/controllers/inventory_controller.dart';
import 'package:warehouse_poc/models/inventory_item.dart';
import 'package:warehouse_poc/models/transaction_log.dart';
import 'package:warehouse_poc/theme.dart';
import 'package:warehouse_poc/services/transaction_file_picker.dart';
import 'package:warehouse_poc/services/auth_service.dart';
import 'package:warehouse_poc/views/transactions_view.dart';

import 'fake_inventory_service.dart';

void main() {
  testWidgets('Bill and multiple Proof picker state is byte-backed and stable',
      (tester) async {
    final controller = InventoryController(
      inventoryService: FakeInventoryService(),
    );
    addTearDown(controller.dispose);
    const session = AuthSession(
      username: 'admin',
      role: 'admin',
      name: 'Admin',
      id: 'admin-id',
    );
    await controller.init(role: 'admin');
    var invocation = 0;
    final picker = _Picker(() {
      invocation++;
      if (invocation == 1) {
        return [
          PickedTransactionFile(
              'bill.pdf', Uint8List.fromList('%PDF-1.4'.codeUnits))
        ];
      }
      if (invocation == 2) {
        return [
          PickedTransactionFile(
              'proof.pdf', Uint8List.fromList('%PDF-1.4'.codeUnits)),
          PickedTransactionFile(
              'photo.png', Uint8List.fromList([0x89, 0x50, 0x4e, 0x47])),
        ];
      }
      return null;
    });

    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(),
      home: Scaffold(
        body: TransactionsView(
          controller: controller,
          addTransaction: controller.addTransaction,
          session: session,
          fixedSection: InventorySection.depot,
          filePicker: picker,
        ),
      ),
    ));
    await tester.tap(find.text('New Incoming'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('UPLOAD BILL'));
    await tester.pump();
    expect(find.text('bill.pdf'), findsOneWidget);
    expect(find.text('- UPLOAD A BILL'), findsNothing);
    await tester.tap(find.text('ADD PROOF'));
    await tester.pump();
    expect(find.text('PROOFS (2)'), findsOneWidget);
    expect(find.text('proof.pdf'), findsOneWidget);
    expect(find.text('photo.png'), findsOneWidget);
    await tester.tap(find.byTooltip('Replace Bill'));
    await tester.pump();
    expect(find.text('bill.pdf'), findsOneWidget);
  });

  testWidgets(
      'Transaction records render explicit zero and multiple Proof sections',
      (tester) async {
    final log = TransactionLog(
      id: 'transaction',
      timestamp: DateTime.utc(2026),
      type: LogType.incoming,
      user: 'Admin',
      items: const [CartItem(id: 'm1', name: 'Rail Pad', quantityChange: 1)],
      bill: 'invoice.pdf',
      billData: 'JVBERi0xLjQ=',
      proofs: [
        TransactionAttachment(
            fileName: 'proof-1.pdf', bytes: Uint8List.fromList([1])),
        TransactionAttachment(
            fileName: 'proof-2.png', bytes: Uint8List.fromList([2])),
      ],
    );
    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(),
      home: Scaffold(
          body: SingleChildScrollView(child: ActionRecordCard(log: log))),
    ));
    expect(find.text('BILL'), findsOneWidget);
    expect(find.text('PROOFS (2)'), findsOneWidget);
    expect(find.textContaining('proof-1.pdf'), findsOneWidget);
    expect(find.textContaining('proof-2.png'), findsOneWidget);

    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(),
      home: Scaffold(
          body: ActionRecordCard(
              log: TransactionLog(
                  id: 'empty',
                  timestamp: DateTime.utc(2026),
                  type: LogType.dispatch,
                  user: 'Admin',
                  items: const [],
                  bill: 'bill.png'))),
    ));
    expect(find.text('PROOFS (0)'), findsOneWidget);
    expect(find.text('NO PROOF ATTACHED'), findsOneWidget);
  });
}

class _Picker implements TransactionFilePicker {
  _Picker(this.next);
  final List<PickedTransactionFile>? Function() next;

  @override
  Future<List<PickedTransactionFile>?> pick(
          {required bool allowMultiple}) async =>
      next();
}
