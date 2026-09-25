import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:warehouse_poc/controllers/inventory_controller.dart';
import 'package:warehouse_poc/models/audit_log.dart';
import 'package:warehouse_poc/models/inventory_item.dart';
import 'package:warehouse_poc/presentation.dart';
import 'package:warehouse_poc/services/auth_service.dart';
import 'package:warehouse_poc/theme.dart';
import 'package:warehouse_poc/views/logs_view.dart';
import 'package:warehouse_poc/views/transactions_view.dart';

import 'fake_inventory_service.dart';

const _admin = AuthSession(
  username: 'admin',
  role: 'admin',
  name: 'Development Admin',
  id: 'admin-id',
  accountId: 'AD-1',
);

AuditLog _event(String scope, String name) => AuditLog(
      id: '$scope-$name',
      eventType: 'INVENTORY_UPDATED',
      entityType: 'INVENTORY',
      entityId: name,
      actor: const AuditActor(
        id: 'actor',
        accountId: 'AD-1',
        name: 'Development Admin',
        role: 'ADMIN',
      ),
      occurredAt: DateTime.utc(2026, 9, 10),
      requestId: 'request',
      after: {'scope': scope, 'name': name},
    );

void main() {
  test('only known demo names are normalized for presentation', () {
    expect(displayName('Development Viewer'), 'Viewer');
    expect(displayName('Development Admin'), 'Admin');
    expect(displayName('Development Superadmin'), 'Superadmin');
    expect(displayName('Priya Nair'), 'Priya Nair');
  });

  testWidgets('Depot screens contain only Depot controls and audit records',
      (tester) async {
    final controller =
        InventoryController(inventoryService: FakeInventoryService());
    addTearDown(controller.dispose);
    await controller.init(role: 'admin');
    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(),
      home: Scaffold(
        body: TransactionsView(
          controller: controller,
          addTransaction: controller.addTransaction,
          session: _admin,
          fixedSection: InventorySection.depot,
        ),
      ),
    ));
    expect(find.text('DEPOT ACTIONS'), findsOneWidget);
    expect(find.text('SLEEPER'), findsNothing);
    expect(find.textContaining('SCOPE:'), findsNothing);

    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(),
      home: Scaffold(
        body: LogsView(
          logs: [
            _event('DEPOT', 'Depot Rail'),
            _event('FACTORY', 'Sleeper Rail')
          ],
          transactions: const [],
          factories: const [],
          session: _admin,
          fixedSection: InventorySection.depot,
          editTransaction: (
              {required logId,
              required updatedItems,
              required user,
              reason}) async {},
        ),
      ),
    ));
    expect(find.text('DEPOT AUDIT'), findsOneWidget);
    expect(find.text('Depot Rail'), findsOneWidget);
    expect(find.text('Sleeper Rail'), findsNothing);
    expect(find.text('All'), findsNothing);
    expect(find.text('Sleeper'), findsNothing);
    expect(find.text('Admin'), findsOneWidget);
    expect(find.text('Development Admin'), findsNothing);
  });

  testWidgets('Sleeper screens contain only Factory controls and audit records',
      (tester) async {
    final controller =
        InventoryController(inventoryService: FakeInventoryService());
    addTearDown(controller.dispose);
    await controller.init(role: 'admin');
    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(),
      home: Scaffold(
        body: TransactionsView(
          controller: controller,
          addTransaction: controller.addTransaction,
          session: _admin,
          fixedSection: InventorySection.sleeper,
        ),
      ),
    ));
    expect(find.text('SLEEPER ACTIONS'), findsOneWidget);
    expect(find.text('DEPOT'), findsNothing);
    expect(find.text('SELECT FACTORY'), findsOneWidget);

    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(),
      home: Scaffold(
        body: LogsView(
          logs: [
            _event('DEPOT', 'Depot Rail'),
            _event('FACTORY', 'Sleeper Rail')
          ],
          transactions: const [],
          factories: const [],
          session: _admin,
          fixedSection: InventorySection.sleeper,
          editTransaction: (
              {required logId,
              required updatedItems,
              required user,
              reason}) async {},
        ),
      ),
    ));
    expect(find.text('SLEEPER AUDIT'), findsOneWidget);
    expect(find.text('Sleeper Rail'), findsOneWidget);
    expect(find.text('Depot Rail'), findsNothing);
    expect(find.text('All'), findsNothing);
    expect(find.text('Depot'), findsNothing);
  });
}
