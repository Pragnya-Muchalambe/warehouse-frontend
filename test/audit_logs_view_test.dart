import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:warehouse_poc/controllers/inventory_controller.dart';
import 'package:warehouse_poc/models/audit_log.dart';
import 'package:warehouse_poc/models/inventory_item.dart';
import 'package:warehouse_poc/models/transaction_log.dart';
import 'package:warehouse_poc/services/auth_service.dart';
import 'package:warehouse_poc/theme.dart';
import 'package:warehouse_poc/views/logs_view.dart';
import 'package:warehouse_poc/views/viewer_shell.dart';

import 'fake_inventory_service.dart';

const _admin = AuthSession(
  username: 'admin',
  role: 'admin',
  name: 'Admin User',
  id: 'admin-id',
  accountId: 'AD-1',
);

const _superadmin = AuthSession(
  username: 'superadmin',
  role: 'superadmin',
  name: 'Superadmin User',
  id: 'superadmin-id',
  accountId: 'SA-1',
);

const _viewer = AuthSession(
  username: 'viewer',
  role: 'viewer',
  name: 'Viewer User',
  id: 'viewer-id',
  accountId: 'VW-1',
);

AuditLog _inventoryUpdatedLog(
    {Map<String, dynamic>? before, Map<String, dynamic>? after}) {
  return AuditLog(
    id: 'audit-id',
    eventType: 'INVENTORY_UPDATED',
    entityType: 'INVENTORY',
    entityId: 'T-6902',
    actor: const AuditActor(
      id: 'actor-id',
      accountId: 'AD-1',
      name: 'Admin User',
      role: 'ADMIN',
    ),
    occurredAt: DateTime.utc(2026, 9, 10, 10),
    requestId: 'request-identifier',
    reason: 'Counted stock',
    before: before == null ? null : {'scope': 'DEPOT', ...before},
    after: after == null ? null : {'scope': 'DEPOT', ...after},
  );
}

Widget _logs(AuditLog log, AuthSession session) => MaterialApp(
      theme: buildTheme(),
      home: Scaffold(
        body: LogsView(
          logs: [log],
          transactions: const [],
          factories: const [],
          session: session,
          editTransaction: ({
            required logId,
            required updatedItems,
            required user,
            reason,
          }) async {},
        ),
      ),
    );

void main() {
  testWidgets('audit shows every transaction material and quantity',
      (tester) async {
    final transaction = TransactionLog(
      id: 'transaction-id',
      timestamp: DateTime.utc(2026, 9, 10),
      type: LogType.incoming,
      user: 'admin',
      section: InventorySection.depot,
      items: const [
        CartItem(id: 'T-5836', name: 'Switch for Trap', quantityChange: 9),
        CartItem(id: 'R-100', name: 'Rail Clip', quantityChange: 4),
      ],
    );
    final audit = AuditLog(
      id: 'audit-transaction',
      eventType: 'TRANSACTION_CREATED',
      entityType: 'TRANSACTION',
      entityId: transaction.id,
      actor: const AuditActor(
        id: 'admin-id',
        accountId: 'AD-1',
        name: 'Admin User',
        role: 'ADMIN',
      ),
      occurredAt: transaction.timestamp,
      requestId: 'request-id',
      after: const {
        'scope': 'DEPOT',
        'type': 'INCOMING',
        'items': [{}, {}]
      },
    );

    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(),
      home: Scaffold(
        body: LogsView(
          logs: [audit],
          transactions: [transaction],
          factories: const [],
          session: _admin,
          editTransaction: ({
            required logId,
            required updatedItems,
            required user,
            reason,
          }) async {},
        ),
      ),
    ));

    await tester.scrollUntilVisible(
      find.text('PL/MATERIAL NO.: T-5836'),
      100,
      scrollable: find.byType(Scrollable).first,
    );

    expect(find.text('1. Switch for Trap'), findsOneWidget);
    expect(find.text('PL/MATERIAL NO.: T-5836'), findsOneWidget);
    expect(find.text('QUANTITY: 9'), findsOneWidget);
    expect(find.text('2. Rail Clip'), findsOneWidget);
    expect(find.text('QUANTITY: 4'), findsOneWidget);
  });

  testWidgets('admin sees concise inventory activity without raw snapshots',
      (tester) async {
    await tester.pumpWidget(_logs(
      _inventoryUpdatedLog(
        before: {
          'name': 'Rail Clip',
          'id': 'T-6902',
          'quantity': 70,
          'biIssued': 0,
          'available': 70,
          'status': 'AVAILABLE',
          'version': 1,
        },
        after: {
          'name': 'Rail Clip',
          'id': 'T-6902',
          'quantity': 80,
          'biIssued': 10,
          'available': 70,
          'status': 'AVAILABLE',
          'version': 2,
        },
      ),
      _admin,
    ));

    expect(find.text('Rail Clip (T-6902)'), findsOneWidget);
    expect(find.text('Total: 70 → 80'), findsOneWidget);
    expect(find.text('BI Issued: 0 → 10'), findsOneWidget);
    expect(find.text('Available: 70'), findsOneWidget);
    expect(find.textContaining('"before"'), findsNothing);
    expect(find.textContaining('"after"'), findsNothing);
    expect(find.textContaining('"version"'), findsNothing);
    expect(find.textContaining('{'), findsNothing);
  });

  testWidgets('superadmin sees readable activity when snapshots are partial',
      (tester) async {
    await tester.pumpWidget(_logs(
      _inventoryUpdatedLog(
          after: {'name': 'Rail Clip', 'status': 'UNAVAILABLE'}),
      _superadmin,
    ));

    expect(find.text('Rail Clip'), findsOneWidget);
    expect(find.text('Status: UNAVAILABLE'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('viewer shell has no audit navigation', (tester) async {
    final service = FakeInventoryService();
    final controller = InventoryController(inventoryService: service);
    addTearDown(controller.dispose);
    await controller.init(role: 'viewer');

    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(),
      home: ViewerShell(
        session: _viewer,
        inventoryController: controller,
        onLogout: () {},
      ),
    ));

    expect(service.loadAuditLogsCalls, 0);
    expect(find.text('AUDIT'), findsNothing);
    expect(find.text('AUDIT LOGS'), findsNothing);
  });
}
