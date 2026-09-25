import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:warehouse_poc/controllers/inventory_controller.dart';
import 'package:warehouse_poc/models/account_request.dart';
import 'package:warehouse_poc/models/viewer_request.dart';
import 'package:warehouse_poc/services/account_request_service.dart';
import 'package:warehouse_poc/services/auth_service.dart';
import 'package:warehouse_poc/services/request_service.dart';
import 'package:warehouse_poc/theme.dart';
import 'package:warehouse_poc/views/admin_shell.dart';
import 'package:warehouse_poc/views/superadmin_shell.dart';

import 'fake_inventory_service.dart';

class _Requests extends RequestService {
  final List<ViewerRequest> requests;
  _Requests(this.requests);

  @override
  Future<List<ViewerRequest>> loadRequests() async => requests;
}

class _Permissions extends AccountRequestService {
  final List<AccountRequest> requests;
  _Permissions(this.requests);

  @override
  Future<List<AccountRequest>> loadRequests() async => requests;
}

ViewerRequest _request(String id, String section) => ViewerRequest(
      id: id,
      viewerId: 'viewer-id',
      viewerName: 'Viewer',
      itemId: 'material-$id',
      itemName: 'Material $id',
      quantity: 1,
      createdAt: DateTime.utc(2026, 9, 11),
      section: section,
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

void main() {
  testWidgets('admin footer renders scoped pending Requests badge',
      (tester) async {
    final controller = await _controller('admin');
    addTearDown(controller.dispose);
    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(),
      home: AdminShell(
        session: _admin,
        inventoryController: controller,
        requestService: _Requests([
          _request('1', 'Depot'),
          _request('2', 'Depot'),
          _request('3', 'Sleeper'),
        ]),
        onLogout: () {},
      ),
    ));
    await tester.pump();

    expect(find.byKey(const ValueKey('requests-footer-badge')), findsOneWidget);
    expect(find.byKey(const ValueKey('hamburger-notification-dot')),
        findsOneWidget);
    await tester.tap(find.byIcon(Icons.menu));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('depot-drawer-badge')), findsOneWidget);
    expect(find.byKey(const ValueKey('sleeper-drawer-badge')), findsOneWidget);
  });

  testWidgets('zero pending count hides admin badge', (tester) async {
    final controller = await _controller('admin');
    addTearDown(controller.dispose);
    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(),
      home: AdminShell(
        session: _admin,
        inventoryController: controller,
        requestService: _Requests(const []),
        onLogout: () {},
      ),
    ));
    await tester.pump();

    expect(find.text('0'), findsNothing);
    expect(
        find.byKey(const ValueKey('hamburger-notification-dot')), findsNothing);
    await tester.tap(find.byIcon(Icons.menu));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('depot-drawer-badge')), findsNothing);
    expect(find.byKey(const ValueKey('sleeper-drawer-badge')), findsNothing);
  });

  testWidgets('superadmin renders Requests and Permission badges',
      (tester) async {
    final controller = await _controller('superadmin');
    addTearDown(controller.dispose);
    final permission = AccountRequest(
      id: 'permission-1',
      name: 'New User',
      requestedId: 'VW-2',
      role: 'viewer',
      submittedAt: DateTime.utc(2026, 9, 11),
    );
    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(),
      home: SuperadminShell(
        session: _superadmin,
        inventoryController: controller,
        requestService: _Requests([_request('1', 'Depot')]),
        accountRequestService: _Permissions([permission]),
        onLogout: () {},
      ),
    ));
    await tester.pump();

    expect(find.text('1'), findsNWidgets(2));
    expect(find.byKey(const ValueKey('hamburger-notification-dot')),
        findsOneWidget);
  });

  testWidgets('permission alone displays the Superadmin hamburger dot',
      (tester) async {
    final controller = await _controller('superadmin');
    addTearDown(controller.dispose);
    final permission = AccountRequest(
      id: 'permission-only',
      name: 'New User',
      requestedId: 'VW-3',
      role: 'viewer',
      submittedAt: DateTime.utc(2026, 9, 13),
    );
    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(),
      home: SuperadminShell(
        session: _superadmin,
        inventoryController: controller,
        requestService: _Requests(const []),
        accountRequestService: _Permissions([permission]),
        onLogout: () {},
      ),
    ));
    await tester.pump();

    expect(find.byKey(const ValueKey('hamburger-notification-dot')),
        findsOneWidget);
  });
}
