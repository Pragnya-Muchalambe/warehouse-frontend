import 'dart:convert';
import 'dart:typed_data';

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
  for (final section in InventorySection.values) {
    for (final session in [_admin, _superadmin]) {
      testWidgets(
          '${session.role} ${section.name} audit renders newest entries first',
          (tester) async {
        final scope = section == InventorySection.depot ? 'DEPOT' : 'FACTORY';
        AuditLog log(String id, String eventType, DateTime occurredAt) =>
            AuditLog(
              id: id,
              eventType: eventType,
              entityType: 'INVENTORY',
              entityId: 'material-$id',
              actor: const AuditActor(
                id: 'admin-id',
                accountId: 'AD-1',
                name: 'Admin User',
                role: 'ADMIN',
              ),
              occurredAt: occurredAt,
              requestId: 'request-$id',
              after: {'scope': scope, 'name': id},
            );
        final oldest = log('Oldest', 'OLDEST_EVENT', DateTime.utc(2026, 9, 1));
        final newest = log('Newest', 'NEWEST_EVENT', DateTime.utc(2026, 9, 3));
        final middle = log('Middle', 'MIDDLE_EVENT', DateTime.utc(2026, 9, 2));

        await tester.pumpWidget(_logsFor(
          logs: [oldest, newest, middle],
          section: section,
          session: session,
        ));

        final newestY = tester.getTopLeft(find.text('NEWEST EVENT')).dy;
        final middleY = tester.getTopLeft(find.text('MIDDLE EVENT')).dy;
        final oldestY = tester.getTopLeft(find.text('OLDEST EVENT')).dy;
        expect(newestY, lessThan(middleY));
        expect(middleY, lessThan(oldestY));
      });
    }
  }

  testWidgets('audit ordering uses ID as an equal-timestamp tie-breaker',
      (tester) async {
    AuditLog log(String id, String eventType) => AuditLog(
          id: id,
          eventType: eventType,
          entityType: 'INVENTORY',
          entityId: 'material-$id',
          actor: const AuditActor(
            id: 'admin-id',
            accountId: 'AD-1',
            name: 'Admin User',
            role: 'ADMIN',
          ),
          occurredAt: DateTime.utc(2026, 9, 3),
          requestId: 'request-$id',
          after: {'scope': 'DEPOT', 'name': id},
        );
    await tester.pumpWidget(_logsFor(logs: [
      log('b', 'SECOND_EQUAL_EVENT'),
      log('a', 'FIRST_EQUAL_EVENT'),
    ]));

    expect(
      tester.getTopLeft(find.text('FIRST EQUAL EVENT')).dy,
      lessThan(tester.getTopLeft(find.text('SECOND EQUAL EVENT')).dy),
    );
  });

  testWidgets('request decision audit deduplicates normalized status changes',
      (tester) async {
    for (final change in const [
      ('REQUEST_ACCEPTED', 'PENDING', 'ACCEPTED'),
      ('REQUEST_REJECTED', 'PENDING', 'REJECTED'),
      ('REQUEST_UNDONE', 'ACCEPTED', 'PENDING'),
    ]) {
      final log = AuditLog(
        id: change.$1,
        eventType: change.$1,
        entityType: 'REQUEST',
        entityId: 'request-id',
        actor: const AuditActor(
          id: 'admin-id',
          accountId: 'AD-1',
          name: 'Admin User',
          role: 'ADMIN',
        ),
        occurredAt: DateTime.utc(2026, 9, 10),
        requestId: 'operation-id',
        before: {'scope': 'DEPOT', 'status': change.$2},
        after: {'scope': 'DEPOT', 'status': change.$3},
      );
      await tester.pumpWidget(_logsFor(logs: [log]));
      expect(
        find.text('Status: ${change.$2} → ${change.$3}'),
        findsOneWidget,
      );
    }
  });

  testWidgets('audit entity label does not append a generic snapshot UUID',
      (tester) async {
    const snapshotUuid = '550e8400-e29b-41d4-a716-446655440000';
    final log = _inventoryUpdatedLog(after: const {
      'scope': 'DEPOT',
      'name': 'Rail Pad',
      'id': snapshotUuid,
    });

    await tester.pumpWidget(_logs(log, _admin));

    expect(find.text('Rail Pad'), findsOneWidget);
    expect(find.textContaining(snapshotUuid), findsNothing);
  });

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

  testWidgets('audit resolves transaction attachments and downloads by file ID',
      (tester) async {
    final audit = AuditLog(
      id: 'audit-transaction',
      eventType: 'TRANSACTION_CREATED',
      entityType: 'TRANSACTION',
      entityId: 'transaction-id',
      actor: const AuditActor(
        id: 'admin-id',
        accountId: 'AD-1',
        name: 'Admin User',
        role: 'ADMIN',
      ),
      occurredAt: DateTime.utc(2026, 9, 10),
      requestId: 'request-id',
      after: const {'scope': 'DEPOT', 'type': 'INCOMING'},
    );
    final loaded = <String>[];
    final downloaded = <String>[];
    final png = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
    );

    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(),
      home: Scaffold(
        body: LogsView(
          logs: [audit],
          transactions: const [],
          factories: const [],
          session: _admin,
          editTransaction: ({
            required logId,
            required updatedItems,
            required user,
            reason,
          }) async {},
          loadTransaction: (id) async {
            loaded.add(id);
            return TransactionLog(
              id: id,
              timestamp: DateTime.utc(2026, 9, 10),
              type: LogType.incoming,
              user: 'Admin',
              section: InventorySection.depot,
              items: const [
                CartItem(id: 'T-1', name: 'Material', quantityChange: 1),
              ],
              bill: 'bill.png',
              billFileId: 'bill-id',
              proofs: const [
                TransactionAttachment(
                  fileName: 'proof-1.png',
                  fileId: 'proof-1-id',
                  contentType: 'image/png',
                ),
                TransactionAttachment(
                  fileName: 'proof-2.png',
                  fileId: 'proof-2-id',
                  contentType: 'image/png',
                ),
              ],
            );
          },
          downloadFile: (id) async {
            downloaded.add(id);
            return Uint8List.fromList(png);
          },
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(loaded, ['transaction-id']);
    expect(find.textContaining('View Bill'), findsOneWidget);
    expect(find.textContaining('View Proof 1'), findsOneWidget);
    expect(find.textContaining('View Proof 2'), findsOneWidget);

    await tester.tap(find.textContaining('View Bill'));
    await tester.pumpAndSettle();
    expect(downloaded, ['bill-id']);
    expect(find.byType(Image), findsWidgets);
  });

  testWidgets('audit only shows attachment sections for applicable events',
      (tester) async {
    final transaction = TransactionLog(
      id: 'transaction-no-proof',
      timestamp: DateTime.utc(2026, 9, 10),
      type: LogType.incoming,
      user: 'Admin',
      section: InventorySection.depot,
      items: const [],
      bill: 'bill.pdf',
      billFileId: 'bill-id',
    );
    final transactionAudit = _transactionAudit(transaction.id);
    await tester.pumpWidget(_logsFor(
      logs: [transactionAudit],
      transactions: [transaction],
    ));
    expect(find.text('BILL'), findsOneWidget);
    expect(find.textContaining('View Bill'), findsOneWidget);
    expect(find.text('PROOFS (0)'), findsOneWidget);
    expect(find.text('NO PROOF ATTACHED'), findsOneWidget);

    final requestWithBill = _requestAudit(
      id: 'request-with-bill',
      billFile: const AuditFileMetadata(
        id: 'request-bill-id',
        purpose: 'BILL',
        fileName: 'request-bill.pdf',
        contentType: 'application/pdf',
      ),
    );
    await tester.pumpWidget(_logsFor(logs: [requestWithBill]));
    expect(find.text('BILL'), findsOneWidget);
    expect(find.textContaining('View Bill'), findsOneWidget);
    expect(find.textContaining('PROOF'), findsNothing);

    await tester.pumpWidget(_logsFor(
      logs: [_requestAudit(id: 'request-without-bill')],
    ));
    expect(find.text('BILL'), findsNothing);
    expect(find.textContaining('Bill: Not available'), findsNothing);
    expect(find.textContaining('PROOF'), findsNothing);
    expect(find.textContaining('No proof attached'), findsNothing);
  });

  testWidgets('audit hydrates attachments when logs arrive after mount',
      (tester) async {
    final key = GlobalKey<_LogsHarnessState>();
    final loaded = <String>[];
    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(),
      home: Scaffold(
        body: _LogsHarness(
          key: key,
          loadTransaction: (id) async {
            loaded.add(id);
            return TransactionLog(
              id: id,
              timestamp: DateTime.utc(2026, 9, 10),
              type: LogType.incoming,
              user: 'Admin',
              section: InventorySection.depot,
              items: const [
                CartItem(id: 'T-1', name: 'Material', quantityChange: 1),
              ],
              bill: 'bill.pdf',
              billFileId: 'bill-id',
              proofs: const [
                TransactionAttachment(
                  fileName: 'proof.png',
                  fileId: 'proof-id',
                  contentType: 'image/png',
                ),
              ],
            );
          },
        ),
      ),
    ));
    expect(loaded, isEmpty);

    key.currentState!.showTransactionLog();
    await tester.pumpAndSettle();

    expect(loaded, ['late-transaction']);
    expect(find.textContaining('View Bill'), findsOneWidget);
    expect(find.textContaining('View Proof 1'), findsOneWidget);

    key.currentState!.rebuildWithSameLog();
    await tester.pumpAndSettle();
    expect(loaded, ['late-transaction']);
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

    expect(find.text('Rail Clip'), findsOneWidget);
    expect(find.textContaining('Rail Clip (T-6902)'), findsNothing);
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

Widget _logsFor({
  required List<AuditLog> logs,
  List<TransactionLog> transactions = const [],
  InventorySection section = InventorySection.depot,
  AuthSession session = _admin,
}) =>
    MaterialApp(
      theme: buildTheme(),
      home: Scaffold(
        body: LogsView(
          logs: logs,
          transactions: transactions,
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

AuditLog _transactionAudit(String transactionId) => AuditLog(
      id: 'audit-$transactionId',
      eventType: 'TRANSACTION_CREATED',
      entityType: 'TRANSACTION',
      entityId: transactionId,
      actor: const AuditActor(
        id: 'admin-id',
        accountId: 'AD-1',
        name: 'Admin User',
        role: 'ADMIN',
      ),
      occurredAt: DateTime.utc(2026, 9, 10),
      requestId: 'request-id',
      after: const {'scope': 'DEPOT', 'type': 'INCOMING'},
    );

AuditLog _requestAudit({
  required String id,
  AuditFileMetadata? billFile,
}) =>
    AuditLog(
      id: id,
      eventType: 'REQUEST_ACCEPTED',
      entityType: 'REQUEST',
      entityId: id,
      actor: const AuditActor(
        id: 'admin-id',
        accountId: 'AD-1',
        name: 'Admin User',
        role: 'ADMIN',
      ),
      occurredAt: DateTime.utc(2026, 9, 10),
      requestId: 'operation-id',
      before: const {'scope': 'DEPOT', 'status': 'PENDING'},
      after: const {'scope': 'DEPOT', 'status': 'ACCEPTED'},
      billFile: billFile,
    );

class _LogsHarness extends StatefulWidget {
  const _LogsHarness({
    super.key,
    required this.loadTransaction,
  });

  final Future<TransactionLog> Function(String id) loadTransaction;

  @override
  State<_LogsHarness> createState() => _LogsHarnessState();
}

class _LogsHarnessState extends State<_LogsHarness> {
  List<AuditLog> logs = const [];

  void showTransactionLog() {
    setState(() {
      logs = [
        AuditLog(
          id: 'late-audit',
          eventType: 'TRANSACTION_CREATED',
          entityType: 'TRANSACTION',
          entityId: 'late-transaction',
          actor: const AuditActor(
            id: 'admin-id',
            accountId: 'AD-1',
            name: 'Admin User',
            role: 'ADMIN',
          ),
          occurredAt: DateTime.utc(2026, 9, 10),
          requestId: 'request-id',
          after: const {'scope': 'DEPOT', 'type': 'INCOMING'},
        ),
      ];
    });
  }

  void rebuildWithSameLog() => setState(() => logs = List.of(logs));

  @override
  Widget build(BuildContext context) {
    return LogsView(
      logs: logs,
      transactions: const [],
      factories: const [],
      session: _admin,
      editTransaction: ({
        required logId,
        required updatedItems,
        required user,
        reason,
      }) async {},
      loadTransaction: widget.loadTransaction,
      downloadFile: (_) async => Uint8List(0),
    );
  }
}
