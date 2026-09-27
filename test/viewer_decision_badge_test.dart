import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:warehouse_poc/controllers/inventory_controller.dart';
import 'package:warehouse_poc/models/viewer_request.dart';
import 'package:warehouse_poc/services/api_client.dart';
import 'package:warehouse_poc/services/auth_service.dart';
import 'package:warehouse_poc/services/request_service.dart';
import 'package:warehouse_poc/theme.dart';
import 'package:warehouse_poc/views/viewer_shell.dart';

import 'fake_inventory_service.dart';

const _viewerA = AuthSession(
  username: 'viewer-a',
  role: 'viewer',
  name: 'Viewer A',
  id: 'viewer-a-uuid',
  accountId: 'VW-A',
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('pending Viewer request never shows a History badge',
      (tester) async {
    final backend = _DecisionBackend([
      _requestJson(id: 'pending', status: 'PENDING'),
    ]);
    await _pumpShell(tester, backend);

    expect(
        find.byKey(const ValueKey('viewer-depot-history-badge')), findsNothing);
  });

  for (final status in ['ACCEPTED', 'REJECTED']) {
    testWidgets('$status Viewer request shows a History badge', (tester) async {
      final backend = _DecisionBackend([
        _requestJson(id: status.toLowerCase(), status: status),
      ]);
      await _pumpShell(tester, backend);

      expect(find.byKey(const ValueKey('viewer-depot-history-badge')),
          findsOneWidget);
    });
  }

  testWidgets(
      'History clears the badge, Requests preserves it, and later decisions restore it',
      (tester) async {
    final backend = _DecisionBackend([
      _requestJson(id: 'accepted', status: 'ACCEPTED'),
    ]);
    await _pumpShell(tester, backend);
    expect(find.byKey(const ValueKey('viewer-depot-history-badge')),
        findsOneWidget);

    await tester.tap(find.text('HISTORY'));
    await tester.pumpAndSettle();
    expect(
        find.byKey(const ValueKey('viewer-depot-history-badge')), findsNothing);

    backend.requests.add(_requestJson(
      id: 'later-rejected',
      status: 'REJECTED',
      decisionAt: '2026-09-28T10:00:00.000Z',
    ));
    await tester.tap(find.text('REQUESTS').last);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('viewer-depot-history-badge')),
        findsOneWidget);

    await tester.tap(find.text('REQUESTS').last);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('viewer-depot-history-badge')),
        findsOneWidget);
  });

  testWidgets('app resume refreshes Viewer decision badges', (tester) async {
    final backend = _DecisionBackend([
      _requestJson(id: 'pending', status: 'PENDING'),
    ]);
    await _pumpShell(tester, backend);
    expect(
        find.byKey(const ValueKey('viewer-depot-history-badge')), findsNothing);

    backend.requests[0] = _requestJson(id: 'pending', status: 'ACCEPTED');
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('viewer-depot-history-badge')),
        findsOneWidget);
  });

  test('seen decisions are isolated by account and include both modules',
      () async {
    final service = RequestService(
        api: ApiClient(
            httpClient: MockClient(
      (_) async => http.Response('{}', 200),
    )));
    final requests = [
      _request(id: 'a-depot', viewerId: 'viewer-a-uuid', section: 'Depot'),
      _request(id: 'a-sleeper', viewerId: 'viewer-a-uuid', section: 'Sleeper'),
      _request(id: 'b-depot', viewerId: 'viewer-b-uuid', section: 'Depot'),
    ];

    expect(
      await service.unseenDecisionCount(
        'viewer-a-uuid',
        'Depot',
        storageViewerId: 'VW-A',
        requests: requests,
      ),
      1,
    );
    expect(
      await service.unseenDecisionCount(
        'viewer-a-uuid',
        'Sleeper',
        storageViewerId: 'VW-A',
        requests: requests,
      ),
      1,
    );
    await service.markDecisionsSeen(
      'viewer-a-uuid',
      'Depot',
      requests,
      storageViewerId: 'VW-A',
    );
    expect(
      await service.unseenDecisionCount(
        'viewer-a-uuid',
        'Depot',
        storageViewerId: 'VW-A',
        requests: requests,
      ),
      0,
    );
    expect(
      await service.unseenDecisionCount(
        'viewer-b-uuid',
        'Depot',
        storageViewerId: 'VW-B',
        requests: requests,
      ),
      1,
    );
  });

  test('older decisions do not reappear after the saved timestamp', () async {
    final service = RequestService(
        api: ApiClient(
            httpClient: MockClient(
      (_) async => http.Response('{}', 200),
    )));
    final seen = _request(id: 'seen', viewerId: 'viewer-a-uuid');
    await service.markDecisionsSeen(
      'viewer-a-uuid',
      'Depot',
      [seen],
      storageViewerId: 'VW-A',
    );
    final older = _request(
      id: 'older',
      viewerId: 'viewer-a-uuid',
      decisionAt: DateTime.utc(2026, 9, 26),
    );

    expect(
      await service.unseenDecisionCount(
        'viewer-a-uuid',
        'Depot',
        storageViewerId: 'VW-A',
        requests: [older, seen],
      ),
      0,
    );
  });
}

Future<void> _pumpShell(
  WidgetTester tester,
  _DecisionBackend backend,
) async {
  final controller = InventoryController(
    inventoryService: FakeInventoryService(),
  );
  addTearDown(controller.dispose);
  await controller.init(role: 'viewer');
  final service = RequestService(
    api: ApiClient(httpClient: MockClient(backend.handle)),
  );
  await tester.pumpWidget(MaterialApp(
    theme: buildTheme(),
    home: ViewerShell(
      session: _viewerA,
      inventoryController: controller,
      requestService: service,
      onLogout: () {},
    ),
  ));
  await tester.pumpAndSettle();
}

ViewerRequest _request({
  required String id,
  required String viewerId,
  String section = 'Depot',
  DateTime? decisionAt,
}) =>
    ViewerRequest(
      id: id,
      viewerId: viewerId,
      viewerName: 'Viewer',
      itemId: 'material-$id',
      itemName: 'Material $id',
      quantity: 1,
      createdAt: DateTime.utc(2026, 9, 27),
      section: section,
      status: 'Accepted',
      decisionAt: decisionAt ?? DateTime.utc(2026, 9, 27),
    );

Map<String, dynamic> _requestJson({
  required String id,
  required String status,
  String module = 'DEPOT',
  String decisionAt = '2026-09-27T10:00:00.000Z',
}) =>
    {
      'id': id,
      'viewerId': _viewerA.id,
      'viewerAccountId': _viewerA.accountId,
      'viewerName': _viewerA.name,
      'itemId': 'material-$id',
      'materialNumber': 'PL-$id',
      'itemName': 'Material $id',
      'quantity': 1,
      'createdAt': '2026-09-27T09:00:00.000Z',
      'module': module,
      'section': module == 'DEPOT' ? 'Depot' : 'Sleeper',
      'status': status,
      if (status == 'ACCEPTED' || status == 'REJECTED')
        'decisionAt': decisionAt,
      'updatedAt': decisionAt,
      'version': 1,
      'history': const [],
    };

class _DecisionBackend {
  _DecisionBackend(this.requests);

  final List<Map<String, dynamic>> requests;

  Future<http.Response> handle(http.Request request) async {
    if (request.url.path.endsWith('/requests')) {
      return http.Response(
        jsonEncode({
          'data': requests,
          'page': {'limit': 50, 'nextCursor': null, 'hasMore': false},
          'meta': {'requestId': 'request-id'},
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    }
    return http.Response('{}', 404);
  }
}
