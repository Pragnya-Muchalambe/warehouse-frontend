import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:warehouse_poc/controllers/inventory_controller.dart';
import 'package:warehouse_poc/models/audit_log.dart';
import 'package:warehouse_poc/models/inventory_item.dart';
import 'package:warehouse_poc/models/factory.dart';
import 'package:warehouse_poc/models/viewer_request.dart';
import 'package:warehouse_poc/services/auth_service.dart';
import 'package:warehouse_poc/services/request_service.dart';
import 'package:warehouse_poc/theme.dart';
import 'package:warehouse_poc/views/admin_shell.dart';
import 'package:warehouse_poc/views/logs_view.dart';
import 'package:warehouse_poc/views/superadmin_shell.dart';
import 'package:warehouse_poc/views/viewer_shell.dart';

import 'fake_inventory_service.dart';

const _viewer = AuthSession(
  username: 'viewer',
  role: 'viewer',
  name: 'Viewer',
  id: 'viewer-id',
  accountId: 'VW-1',
);

const _admin = AuthSession(
  username: 'admin',
  role: 'admin',
  name: 'Admin',
  id: 'admin-id',
  accountId: 'AD-1',
);

const _superadmin = AuthSession(
  username: 'superadmin',
  role: 'superadmin',
  name: 'Superadmin',
  id: 'superadmin-id',
  accountId: 'SA-1',
);

Future<InventoryController> _controller(String role) async {
  final controller =
      InventoryController(inventoryService: FakeInventoryService());
  await controller.init(role: role);
  return controller;
}

class _ViewerRequests extends RequestService {
  final bool fail;
  final List<ViewerRequest> requests = [];

  _ViewerRequests({this.fail = false});

  @override
  Future<List<ViewerRequest>> loadRequests() async =>
      List.unmodifiable(requests);

  @override
  Future<List<ViewerRequest>> addBatch({
    required String viewerId,
    required String viewerName,
    required List<({String itemId, String itemName, int quantity})> items,
    String? factoryId,
    String? factoryName,
  }) async {
    if (fail) {
      throw const RequestBatchException(
        succeededItemIds: [],
        failedItems: {'mat-1': 'Unavailable'},
      );
    }
    final created = items
        .map((item) => ViewerRequest(
              id: 'created-${item.itemId}',
              viewerId: viewerId,
              viewerName: viewerName,
              itemId: item.itemId,
              itemName: item.itemName,
              quantity: item.quantity,
              createdAt: DateTime.utc(2026, 9, 13),
              section: factoryId == null ? 'Depot' : 'Sleeper',
              factoryId: factoryId,
              factoryName: factoryName,
            ))
        .toList();
    requests.insertAll(0, created);
    return created;
  }
}

Future<InventoryController> _requestController() async {
  final controller = InventoryController(
    inventoryService: FakeInventoryService(
      factories: const [
        WarehouseFactory(
          id: 'factory-1',
          name: 'Factory One',
          location: 'North',
          materials: [
            FactoryMaterial(id: 'mat-1', name: 'Rail Seat', total: 5)
          ],
        ),
      ],
    ),
  );
  await controller.init(role: 'viewer');
  return controller;
}

Future<void> _submitSleeperRequest(WidgetTester tester) async {
  await _openSleeper(tester);
  await tester.tap(find.text('REQUESTS'));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('request-factory-selector')));
  await tester.pumpAndSettle();
  await tester.tap(find.textContaining('Factory One').last);
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('request-material-selector')));
  await tester.pumpAndSettle();
  await tester.tap(find.text('RAIL SEAT'));
  await tester.pumpAndSettle();
  await tester.enterText(find.byType(TextFormField).last, '1');
  await tester.tap(find.text('ADD TO CART'));
  await tester.pumpAndSettle();
  final reviewButton = find.textContaining('REVIEW REQUEST');
  await tester.ensureVisible(reviewButton);
  await tester.tap(reviewButton);
  await tester.pumpAndSettle();
  final confirmButton = find.text('CONFIRM REQUESTS');
  await tester.ensureVisible(confirmButton);
  await tester.tap(confirmButton);
  await tester.pumpAndSettle();
}

Future<void> _openSleeper(WidgetTester tester) async {
  await tester.tap(find.byIcon(Icons.menu));
  await tester.pumpAndSettle();
  await tester.tap(find.text('SLEEPER'));
  await tester.pumpAndSettle();
}

Future<void> _openDepot(WidgetTester tester) async {
  await tester.tap(find.byIcon(Icons.menu));
  await tester.pumpAndSettle();
  await tester.tap(find.text('DEPOT'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('Sleeper success redirects to factory-scoped History',
      (tester) async {
    final controller = await _requestController();
    addTearDown(controller.dispose);
    final service = _ViewerRequests();
    service.requests.add(ViewerRequest(
      id: 'other',
      viewerId: _viewer.id,
      viewerName: _viewer.name,
      itemId: 'other-mat',
      itemName: 'Other Factory Material',
      quantity: 1,
      createdAt: DateTime.utc(2026, 9, 12),
      section: 'Sleeper',
      factoryId: 'factory-2',
      factoryName: 'Factory Two',
    ));
    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(),
      home: ViewerShell(
        session: _viewer,
        inventoryController: controller,
        requestService: service,
        onLogout: () {},
      ),
    ));

    await _submitSleeperRequest(tester);

    expect(find.text('SLEEPER HISTORY'), findsOneWidget);
    expect(find.text('RAIL SEAT'), findsOneWidget);
    expect(find.text('OTHER FACTORY MATERIAL'), findsNothing);
  });

  testWidgets('Sleeper failure preserves review and does not redirect',
      (tester) async {
    final controller = await _requestController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(),
      home: ViewerShell(
        session: _viewer,
        inventoryController: controller,
        requestService: _ViewerRequests(fail: true),
        onLogout: () {},
      ),
    ));

    await _submitSleeperRequest(tester);

    expect(find.text('REVIEW REQUEST'), findsOneWidget);
    expect(
        find.textContaining('Failed: Rail Seat: Unavailable'), findsOneWidget);
    expect(find.text('SLEEPER HISTORY'), findsNothing);
  });

  testWidgets(
      'viewer Sleeper footer only exposes factories requests and history',
      (tester) async {
    final controller = await _controller('viewer');
    addTearDown(controller.dispose);
    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(),
      home: ViewerShell(
        session: _viewer,
        inventoryController: controller,
        onLogout: () {},
      ),
    ));

    await _openSleeper(tester);

    expect(find.text('FACTORIES'), findsOneWidget);
    expect(find.text('REQUESTS'), findsOneWidget);
    expect(find.text('HISTORY'), findsOneWidget);
    expect(find.text('ACTIONS'), findsNothing);
    expect(find.text('AUDIT'), findsNothing);
    expect(find.text('PERMISSION'), findsNothing);
  });

  testWidgets('admin switches to Sleeper factories and never sees permission',
      (tester) async {
    final controller = await _controller('admin');
    addTearDown(controller.dispose);
    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(),
      home: AdminShell(
        session: _admin,
        inventoryController: controller,
        onLogout: () {},
      ),
    ));

    expect(find.text('INVENTORY'), findsOneWidget);
    await _openSleeper(tester);

    expect(find.text('SLEEPER FACTORIES'), findsOneWidget);
    expect(find.text('FACTORIES'), findsOneWidget);
    expect(find.text('ACTIONS'), findsOneWidget);
    expect(find.text('AUDIT'), findsOneWidget);
    expect(find.text('REQUESTS'), findsOneWidget);
    expect(find.text('PERMISSION'), findsNothing);
  });

  testWidgets('superadmin Sleeper footer includes every privileged tab',
      (tester) async {
    final controller = await _controller('superadmin');
    addTearDown(controller.dispose);
    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(),
      home: SuperadminShell(
        session: _superadmin,
        inventoryController: controller,
        onLogout: () {},
      ),
    ));

    await _openSleeper(tester);

    for (final label in [
      'FACTORIES',
      'ACTIONS',
      'AUDIT',
      'REQUESTS',
      'PERMISSION'
    ]) {
      expect(find.text(label), findsOneWidget);
    }
  });

  testWidgets('switching areas replaces the active footer state',
      (tester) async {
    final controller = await _controller('admin');
    addTearDown(controller.dispose);
    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(),
      home: AdminShell(
        session: _admin,
        inventoryController: controller,
        onLogout: () {},
      ),
    ));

    await _openSleeper(tester);
    await tester.tap(find.text('ACTIONS'));
    await tester.pumpAndSettle();
    expect(find.text('SLEEPER ACTIONS'), findsWidgets);

    await _openDepot(tester);
    expect(find.text('DEPOT INVENTORY'), findsOneWidget);
    expect(find.text('INVENTORY'), findsOneWidget);

    await _openSleeper(tester);
    expect(find.text('SLEEPER FACTORIES'), findsOneWidget);
    expect(find.text('FACTORIES'), findsOneWidget);
  });

  testWidgets('Sleeper audit excludes Depot events and raw snapshots',
      (tester) async {
    AuditLog event(String scope, String name) => AuditLog(
          id: '$scope-$name',
          eventType: 'INVENTORY_UPDATED',
          entityType: 'INVENTORY',
          entityId: name,
          actor: const AuditActor(
              id: 'a', accountId: 'AD-1', name: 'Admin', role: 'ADMIN'),
          occurredAt: DateTime.utc(2026, 9, 10),
          requestId: 'request',
          after: {'scope': scope, 'name': name, 'quantity': 5, 'version': 2},
        );
    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(),
      home: Scaffold(
        body: LogsView(
          logs: [
            event('DEPOT', 'Depot Rail'),
            event('FACTORY', 'Sleeper Rail')
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

    expect(find.text('Sleeper Rail'), findsOneWidget);
    expect(find.text('Depot Rail'), findsNothing);
    expect(find.textContaining('"version"'), findsNothing);
    expect(find.textContaining('{'), findsNothing);
    expect(find.textContaining('fixture-'), findsNothing);
  });
}
