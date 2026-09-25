import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:warehouse_poc/models/account_request.dart';
import 'package:warehouse_poc/services/account_request_service.dart';
import 'package:warehouse_poc/services/api_client.dart';
import 'support/local_warehouse.dart';
import 'package:warehouse_poc/theme.dart';
import 'package:warehouse_poc/views/superadmin_permission_view.dart';

void main() {
  testWidgets(
      'Permission loads local data and employee selector excludes superadmin',
      (tester) async {
    final store = LocalWarehouseStore.seeded();
    final session =
        await LocalAuthService(store).login('superadmin', 'superadmin123456');
    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(),
      home: Scaffold(
        body: SuperadminPermissionView(
          session: session!,
          accountRequestService: LocalAccountRequestService(store),
          userService: LocalUserAccountService(store),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('PENDING OPERATOR'), findsOneWidget);
    expect(find.text('DELETE EMPLOYEE ACCOUNT'), findsOneWidget);
    await tester.tap(find.text('DELETE EMPLOYEE ACCOUNT'));
    await tester.pumpAndSettle();
    expect(
        find.textContaining('Viewer User — viewer — Viewer'), findsOneWidget);
    expect(find.textContaining('Admin User — admin — Admin'), findsOneWidget);
    expect(find.textContaining('Superadmin User'), findsNothing);
  });

  testWidgets('Permission shows stable error and retry recovers',
      (tester) async {
    final store = LocalWarehouseStore.seeded();
    final session =
        await LocalAuthService(store).login('superadmin', 'superadmin123456');
    final requests = _FailOnceAccountRequestService(store.accountRequests);
    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(),
      home: Scaffold(
        body: SuperadminPermissionView(
          session: session!,
          accountRequestService: requests,
          userService: LocalUserAccountService(store),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('UNABLE TO LOAD PERMISSION DATA.'), findsOneWidget);
    await tester.tap(find.text('RETRY'));
    await tester.pumpAndSettle();
    expect(find.text('PENDING OPERATOR'), findsOneWidget);
  });

  testWidgets('employee confirmation deletes only the selected login',
      (tester) async {
    final store = LocalWarehouseStore.seeded();
    final auth = LocalAuthService(store);
    final session = await auth.login('superadmin', 'superadmin123456');
    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(),
      home: Scaffold(
        body: SuperadminPermissionView(
          session: session!,
          accountRequestService: LocalAccountRequestService(store),
          userService: LocalUserAccountService(store),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('DELETE EMPLOYEE ACCOUNT'));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Viewer User — viewer — Viewer'));
    await tester.pumpAndSettle();
    expect(find.text('Employee: Viewer User'), findsOneWidget);
    await tester.tap(find.text('Delete Account'));
    await tester.pumpAndSettle();
    expect(await auth.login('viewer', 'viewer123456'), isNull);
    expect(await auth.login('admin', 'admin123456'), isNotNull);
    expect(store.requests.where((request) => request.viewerId == 'user-viewer'),
        isNotEmpty);
  });

  test('account decisions affect only the selected pending request', () async {
    final store = LocalWarehouseStore.seeded();
    store.accountRequests.add(AccountRequest(
      id: 'account-request-002',
      name: 'Second Operator',
      requestedId: 'VW-2002',
      role: 'viewer',
      submittedAt: DateTime.utc(2026, 9, 11, 10),
    ));
    await LocalAuthService(store).login('superadmin', 'superadmin123456');
    final service = LocalAccountRequestService(store);
    await service.decide(store.accountRequests.first, 'reject');
    expect(store.accountRequests.first.status, 'Rejected');
    expect(store.accountRequests.last.isPending, isTrue);
  });
}

class _FailOnceAccountRequestService extends AccountRequestService {
  _FailOnceAccountRequestService(this.requests);
  final List<AccountRequest> requests;
  bool failed = false;

  @override
  Future<List<AccountRequest>> loadRequests() async {
    if (!failed) {
      failed = true;
      throw const ApiException('failure', 500);
    }
    return List.unmodifiable(requests);
  }
}
