import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:warehouse_poc/models/audit_log.dart';
import 'package:warehouse_poc/models/inventory_item.dart';
import 'package:warehouse_poc/services/auth_service.dart';
import 'package:warehouse_poc/theme.dart';
import 'package:warehouse_poc/views/logs_view.dart';

const _admin = AuthSession(
  username: 'admin',
  role: 'admin',
  name: 'Development Admin',
  id: 'admin-id',
  accountId: 'AD-1',
);

const _superadmin = AuthSession(
  username: 'superadmin',
  role: 'superadmin',
  name: 'Development Superadmin',
  id: 'superadmin-id',
  accountId: 'SA-1',
);

AuditLog _event(String scope) => AuditLog(
      id: '$scope-log',
      eventType: 'FACTORY_MATERIAL_UPDATED',
      entityType: 'FACTORY_MATERIAL',
      entityId: 'MAT-1',
      actor: const AuditActor(
        id: 'actor-id',
        accountId: 'AD-1',
        name: 'Development Admin',
        role: 'ADMIN',
      ),
      occurredAt: DateTime.utc(2026, 9, 10, 11, 53),
      requestId: 'request-id',
      before: {
        'scope': scope,
        'name': 'Screws',
        'factoryNameSnapshot': 'Bengaluru Sleeper Plant',
        'total': 20,
        'biIssued': 0,
        'available': 20,
        'version': 1,
      },
      after: {
        'scope': scope,
        'name': 'Screws',
        'factoryNameSnapshot': 'Bengaluru Sleeper Plant',
        'total': 20,
        'biIssued': 5,
        'available': 15,
        'version': 2,
      },
    );

Widget _logs(AuthSession session, InventorySection section) => MaterialApp(
      theme: buildTheme(),
      home: Scaffold(
        body: LogsView(
          logs: [
            _event(section == InventorySection.sleeper ? 'FACTORY' : 'DEPOT')
          ],
          transactions: const [],
          factories: const [],
          session: session,
          fixedSection: section,
          editTransaction: ({
            required logId,
            required updatedItems,
            required user,
            reason,
          }) async {},
        ),
      ),
    );

void _expectReadableSummary() {
  expect(find.text('Screws'), findsOneWidget);
  expect(find.text('Factory: Bengaluru Sleeper Plant'), findsOneWidget);
  expect(find.text('BI Issued: 0 → 5'), findsOneWidget);
  expect(find.text('Available: 20 → 15'), findsOneWidget);
  expect(find.textContaining('BEFORE: {'), findsNothing);
  expect(find.textContaining('AFTER: {'), findsNothing);
  expect(find.textContaining('"before"'), findsNothing);
  expect(find.textContaining('"after"'), findsNothing);
  expect(find.textContaining('"version"'), findsNothing);
  expect(find.textContaining('{'), findsNothing);
}

void main() {
  testWidgets('admin Depot audit never renders raw snapshots', (tester) async {
    await tester.pumpWidget(_logs(_admin, InventorySection.depot));
    _expectReadableSummary();
  });

  testWidgets('admin Sleeper audit never renders raw snapshots',
      (tester) async {
    await tester.pumpWidget(_logs(_admin, InventorySection.sleeper));
    _expectReadableSummary();
  });

  testWidgets('superadmin Depot audit never renders raw snapshots',
      (tester) async {
    await tester.pumpWidget(_logs(_superadmin, InventorySection.depot));
    _expectReadableSummary();
  });

  testWidgets('superadmin Sleeper audit never renders raw snapshots',
      (tester) async {
    await tester.pumpWidget(_logs(_superadmin, InventorySection.sleeper));
    _expectReadableSummary();
  });
}
