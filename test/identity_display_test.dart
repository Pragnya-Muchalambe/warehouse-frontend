import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:warehouse_poc/controllers/inventory_controller.dart';
import 'package:warehouse_poc/models/account_request.dart';
import 'package:warehouse_poc/models/inventory_item.dart';
import 'package:warehouse_poc/models/viewer_request.dart';
import 'package:warehouse_poc/presentation.dart';
import 'package:warehouse_poc/services/account_request_service.dart';
import 'package:warehouse_poc/services/auth_service.dart';
import 'package:warehouse_poc/services/request_service.dart';
import 'package:warehouse_poc/theme.dart';
import 'package:warehouse_poc/views/admin_requests_view.dart';
import 'package:warehouse_poc/views/admin_shell.dart';
import 'package:warehouse_poc/views/superadmin_requests_view.dart';
import 'package:warehouse_poc/views/superadmin_shell.dart';
import 'package:warehouse_poc/views/transactions_view.dart';
import 'package:warehouse_poc/views/viewer_shell.dart';

import 'fake_inventory_service.dart';

const _uuid = '550e8400-e29b-41d4-a716-446655440000';

class _Requests extends RequestService {
  _Requests(this.requests);

  final List<ViewerRequest> requests;

  @override
  Future<List<ViewerRequest>> loadRequests() async => requests;
}

class _AccountRequests extends AccountRequestService {
  @override
  Future<List<AccountRequest>> loadRequests() async => const [];
}

Future<InventoryController> _controller({
  List<InventoryItem> inventory = const [],
}) async {
  final controller = InventoryController(
    inventoryService: FakeInventoryService(inventory: inventory),
  );
  await controller.init(role: 'admin');
  return controller;
}

AuthSession _session(String role, String accountId) => AuthSession(
      username: role,
      role: role,
      name: '$role user',
      id: _uuid,
      accountId: accountId,
    );

ViewerRequest _request({
  String id = _uuid,
  String section = 'Depot',
  String itemId = 'material-uuid',
  int quantity = 7,
}) =>
    ViewerRequest(
      id: id,
      viewerId: '4dc4fe6f-4ba7-49d9-bcca-5915ba723c3a',
      viewerAccountId: 'VW-42',
      viewerName: 'Ravi Kumar',
      itemId: itemId,
      materialNumber: 'PL-42',
      itemName: 'Rail Pad',
      quantity: quantity,
      createdAt: DateTime.utc(2026, 9, 27),
      section: section,
      factoryId: section == 'Sleeper' ? 'factory-uuid' : null,
      factoryName: section == 'Sleeper' ? 'Sleeper Works' : null,
      status: 'Accepted',
    );

void main() {
  test('linked requests must exactly fulfil each linked material', () {
    expect(
      dispatchRequestQuantitiesMatch(
        const {'rail-pad': 7},
        const {'rail-pad': 3 + 4},
      ),
      isTrue,
    );
    expect(
      dispatchRequestQuantitiesMatch(
        const {'rail-pad': 7},
        const {'rail-pad': 3},
      ),
      isFalse,
    );
    expect(
      dispatchRequestQuantitiesMatch(
        const {'rail-pad': 7},
        const {},
      ),
      isTrue,
    );
  });

  testWidgets('profile drawers show account IDs and never internal UUIDs',
      (tester) async {
    final controller = await _controller();
    addTearDown(controller.dispose);
    final requests = _Requests(const []);
    final shells = <Widget>[
      ViewerShell(
        session: _session('viewer', 'VW-42'),
        inventoryController: controller,
        requestService: requests,
        onLogout: () {},
      ),
      AdminShell(
        session: _session('admin', 'AD-42'),
        inventoryController: controller,
        requestService: requests,
        onLogout: () {},
      ),
      SuperadminShell(
        session: _session('superadmin', 'SA-42'),
        inventoryController: controller,
        requestService: requests,
        accountRequestService: _AccountRequests(),
        onLogout: () {},
      ),
    ];

    for (final (index, shell) in shells.indexed) {
      await tester.pumpWidget(MaterialApp(theme: buildTheme(), home: shell));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.menu));
      await tester.pumpAndSettle();
      expect(find.text('ID: ${['VW-42', 'AD-42', 'SA-42'][index]}'),
          findsOneWidget);
      expect(find.textContaining(_uuid), findsNothing);
    }
  });

  testWidgets('admin request cards show readable viewer identity without UUIDs',
      (tester) async {
    final controller = await _controller();
    addTearDown(controller.dispose);
    final request = _request();
    final service = _Requests([request]);

    for (final view in [
      AdminRequestsView(
        controller: controller,
        session: _session('admin', 'AD-42'),
        requestService: service,
      ),
      SuperadminRequestsView(
        controller: controller,
        session: _session('superadmin', 'SA-42'),
        requestService: service,
      ),
    ]) {
      await tester.pumpWidget(MaterialApp(
        theme: buildTheme(),
        home: Scaffold(body: view),
      ));
      await tester.pumpAndSettle();
      expect(find.text('Ravi Kumar'), findsOneWidget);
      expect(find.text('VW-42'), findsOneWidget);
      expect(find.textContaining('Request ID'), findsNothing);
      expect(find.textContaining(_uuid), findsNothing);
      expect(find.textContaining(request.viewerId), findsNothing);
    }
  });

  testWidgets('fulfilment label is explicit and contains no request UUID',
      (tester) async {
    const item = InventoryItem(
      id: 'material-uuid',
      materialNumber: 'PL-42',
      name: 'Rail Pad',
      quantity: 20,
    );
    final controller = await _controller(inventory: const [item]);
    addTearDown(controller.dispose);
    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(),
      home: Scaffold(
        body: TransactionsView(
          controller: controller,
          addTransaction: controller.addTransaction,
          session: _session('admin', 'AD-42'),
          fixedSection: InventorySection.depot,
          requestService: _Requests([
            _request(),
            _request(id: 'second-compatible', quantity: 4),
            _request(id: 'wrong-module', section: 'Sleeper'),
            _request(id: 'wrong-material', itemId: 'other-material'),
            _request(id: 'excessive-quantity', quantity: 8),
          ]),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('New Dispatch'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byWidgetPredicate(
        (widget) =>
            widget is TextField &&
            widget.decoration?.hintText == 'SEARCH INVENTORY...',
      ),
      'Rail',
    );
    await tester.pumpAndSettle();
    final material = find.text('RAIL PAD').first;
    await tester.ensureVisible(material);
    await tester.tap(material);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(TextField).last,
      '7',
    );
    await tester.pumpAndSettle();

    const fulfilmentLabel = 'Viewer: Ravi Kumar\n'
        'Viewer ID: VW-42\n'
        'Material: Rail Pad\n'
        'PL Number: PL-42\n'
        'Requested quantity: 7\n'
        'Module: Depot';
    final label = find.text(fulfilmentLabel);
    await tester.ensureVisible(label.first);
    expect(label, findsWidgets);
    expect(find.textContaining('Viewer ID: VW-42'), findsNWidgets(2));
    expect(find.textContaining('Material: Rail Pad'), findsNWidgets(2));
    expect(find.textContaining('PL Number: PL-42'), findsNWidgets(2));
    expect(find.textContaining('Requested quantity: 7'), findsOneWidget);
    expect(find.textContaining('Module: Depot'), findsNWidgets(2));
    expect(find.textContaining('Module: Sleeper'), findsNothing);
    expect(find.textContaining('Requested quantity: 8'), findsNothing);
    expect(find.textContaining(_uuid), findsNothing);

    await tester.tap(
      find.ancestor(
        of: label,
        matching: find.byType(CheckboxListTile),
      ),
    );
    await tester.pump();
    final secondRequest = find.ancestor(
      of: find.textContaining('Requested quantity: 4'),
      matching: find.byType(CheckboxListTile),
    );
    expect(
      tester.widget<CheckboxListTile>(secondRequest).onChanged,
      isNull,
      reason: 'Cumulative linked quantity must not exceed Dispatch quantity.',
    );
  });

  testWidgets('decision and matching history use the same local timestamp',
      (tester) async {
    final controller = await _controller();
    addTearDown(controller.dispose);
    final instant = DateTime.parse('2026-09-27T06:20:00.000Z');
    final request = ViewerRequest(
      id: _uuid,
      viewerId: 'viewer-uuid',
      viewerAccountId: 'VW-42',
      viewerName: 'Ravi Kumar',
      itemId: 'material-uuid',
      materialNumber: 'PL-42',
      itemName: 'Rail Pad',
      quantity: 7,
      createdAt: instant.subtract(const Duration(minutes: 5)),
      status: 'Accepted',
      decisionAt: instant,
      history: [
        RequestHistoryEntry(
          status: 'Accepted',
          actor: 'admin',
          at: instant,
        ),
      ],
    );

    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(),
      home: Scaffold(
        body: SuperadminRequestsView(
          controller: controller,
          session: _session('superadmin', 'SA-42'),
          requestService: _Requests([request]),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    final formatted = formatLocalTimestamp(instant);
    expect(find.text('DECIDED: ${formatted.toUpperCase()}'), findsOneWidget);
    expect(
        find.textContaining('Accepted by Admin — $formatted'), findsOneWidget);
  });
}
