import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:warehouse_poc/app_dependencies.dart';
import 'package:warehouse_poc/main.dart';
import 'package:warehouse_poc/models/transaction_log.dart';
import 'package:warehouse_poc/models/factory.dart';
import 'package:warehouse_poc/theme.dart';
import 'package:warehouse_poc/views/login_view.dart';
import 'package:warehouse_poc/views/viewer_shell.dart';
import 'package:warehouse_poc/views/viewer_requests_view.dart';
import 'package:warehouse_poc/services/transaction_file_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/local_warehouse.dart';

AppDependencies _localDependencies() {
  final store = LocalWarehouseStore.seeded();
  return AppDependencies.forTesting(
    auth: LocalAuthService(store),
    inventory: LocalInventoryService(store),
    requests: LocalRequestService(store),
    accountRequests: LocalAccountRequestService(store),
    users: LocalUserAccountService(store),
    transactionFilePicker: kIsWeb
        ? PlatformTransactionFilePicker.initialized()
        : const PlatformTransactionFilePicker(),
  );
}

void main() {
  test('all deterministic local accounts authenticate and wrong password fails',
      () async {
    for (final credentials in const [
      ('viewer', 'viewer123456', 'viewer'),
      ('admin', 'admin123456', 'admin'),
      ('superadmin', 'superadmin123456', 'superadmin'),
    ]) {
      final store = LocalWarehouseStore.seeded();
      expect(store.users, hasLength(3));
      final session =
          await LocalAuthService(store).login(credentials.$1, credentials.$2);
      expect(session?.role, credentials.$3);
    }
    final auth = LocalAuthService(LocalWarehouseStore.seeded());
    expect(await auth.login('admin', 'password'), isNull);
  });

  test('approved registrations authenticate with their submitted credentials',
      () async {
    final store = LocalWarehouseStore.seeded();
    final auth = LocalAuthService(store);
    final accounts = LocalAccountRequestService(store);
    final viewerRequest = await accounts.addRequest(
      name: 'Prithvi Viewer',
      id: ' 1234 ',
      password: 'Prithvi@2007',
      role: 'viewer',
    );
    expect(await auth.login('1234', 'Prithvi@2007'), isNull);
    await auth.login('superadmin', 'superadmin123456');
    await accounts.decide(viewerRequest, 'approve');
    await auth.logout();
    expect((await auth.login(' 1234 ', 'Prithvi@2007'))?.role, 'viewer');
    expect(await auth.login('1234', 'wrong-password'), isNull);

    final adminRequest = await accounts.addRequest(
      name: 'New Admin',
      id: 'A-2002',
      password: 'Admin@Password1',
      role: 'admin',
    );
    await auth.login('superadmin', 'superadmin123456');
    await accounts.decide(adminRequest, 'approve');
    expect((await auth.login('a-2002', 'Admin@Password1'))?.role, 'admin');

    final rejected = await accounts.addRequest(
      name: 'Rejected User',
      id: 'R-2003',
      password: 'Rejected@123',
      role: 'viewer',
    );
    await auth.login('superadmin', 'superadmin123456');
    await accounts.decide(rejected, 'reject');
    expect(await auth.login('R-2003', 'Rejected@123'), isNull);
  });

  test('approved password verifier survives store and browser reconstruction',
      () async {
    SharedPreferences.setMockInitialValues({});
    final store = await LocalWarehouseStore.loadOrSeed();
    final auth = LocalAuthService(store);
    final accounts = LocalAccountRequestService(store);
    final request = await accounts.addRequest(
      name: 'Shingi',
      id: 'Shingi',
      password: 'Shingi@12345',
      role: 'viewer',
    );
    expect(await auth.login('Shingi', 'Shingi@12345'), isNull);
    await auth.login('superadmin', 'superadmin123456');
    await accounts.decide(request, 'approve');
    final identity = identityHashCode(store);
    await auth.logout();
    expect(identityHashCode(store), identity);
    expect((await auth.login('shingi', 'Shingi@12345'))?.role, 'viewer');
    expect(store.passwords['shingi'], isNot(contains('Shingi@12345')));

    final restored = await LocalWarehouseStore.loadOrSeed();
    expect(
        (await LocalAuthService(restored).login('SHINGI', 'Shingi@12345'))
            ?.role,
        'viewer');
    expect(await LocalAuthService(restored).login('shingi', 'shingi@12345'),
        isNull);
  });

  test('normal local dependency graph uses the production file picker', () {
    final dependencies = _localDependencies();
    addTearDown(dependencies.controller.dispose);
    expect(dependencies.transactionFilePicker,
        isA<PlatformTransactionFilePicker>());
    expect((dependencies.auth as LocalAuthService).store,
        same((dependencies.inventory as LocalInventoryService).store));
  });

  testWidgets('frontend starts in local mode without a backend',
      (tester) async {
    final dependencies = _localDependencies();
    await tester.pumpWidget(WarehouseApp(dependencies: dependencies));
    await tester.pumpAndSettle();

    expect(find.text('SYSTEM LOGIN'), findsOneWidget);
    expect(find.text('User ID'), findsOneWidget);
  });

  testWidgets('Login button and keyboard action preserve password value',
      (tester) async {
    final auth = LocalAuthService(LocalWarehouseStore.seeded());
    var logins = 0;
    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(),
      home: LoginView(
        key: const ValueKey('keyboard-login'),
        authService: auth,
        onLogin: (_) async => logins++,
      ),
    ));

    await tester.enterText(find.byType(TextFormField).first, 'admin');
    await tester.enterText(find.byType(TextFormField).last, 'admin123456');
    await tester.tap(find.byTooltip('Show password'));
    expect(find.text('admin123456'), findsOneWidget);
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(logins, 1);

    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(),
      home: LoginView(
        key: const ValueKey('button-login'),
        authService: auth,
        onLogin: (_) async => logins++,
      ),
    ));
    await tester.enterText(find.byType(TextFormField).first, 'admin');
    await tester.enterText(find.byType(TextFormField).last, 'admin123456');
    await tester.tap(find.text('Login'));
    await tester.pump();
    expect(logins, 2);
  });

  test('batch children are decided and undone independently', () async {
    final store = LocalWarehouseStore.seeded();
    final auth = LocalAuthService(store);
    final requests = LocalRequestService(store);
    final session = await auth.login('admin', 'admin123456');
    expect(session, isNotNull);
    final beforeA = store.inventory[0].available;
    final beforeB = store.inventory[1].available;

    final batch = await requests.addBatch(
      viewerId: 'user-viewer',
      viewerName: 'Viewer User',
      items: [
        (
          itemId: store.inventory[0].id,
          itemName: store.inventory[0].name,
          quantity: 9
        ),
        (
          itemId: store.inventory[1].id,
          itemName: store.inventory[1].name,
          quantity: 4
        ),
      ],
    );
    expect(batch.first.batchId, batch.last.batchId);
    expect(batch.first.id, isNot(batch.last.id));
    await requests.decide(batch.first.id, 'reject', batch.first.version);
    expect(
        store.requests.firstWhere((item) => item.id == batch.first.id).status,
        'Rejected');
    expect(store.requests.firstWhere((item) => item.id == batch.last.id).status,
        'Pending');
    expect(store.inventory[0].available, beforeA);
    expect(store.inventory[1].available, beforeB);
    expect(store.requests.where((item) => item.isPending), hasLength(2));
    expect(await requests.unseenDecisionCount('user-viewer', 'Depot'), 3);

    await requests.decide(batch.last.id, 'accept', batch.last.version);
    expect(store.inventory[0].available, beforeA);
    expect(store.inventory[1].available, beforeB - 4);
    expect(await requests.unseenDecisionCount('user-viewer', 'Depot'), 4);
    final accepted =
        store.requests.firstWhere((item) => item.id == batch.last.id);
    await requests.decide(accepted.id, 'undo', accepted.version);
    expect(store.inventory[0].available, beforeA);
    expect(store.inventory[1].available, beforeB);
    expect(
        store.requests.firstWhere((item) => item.id == batch.first.id).status,
        'Rejected');
    expect(store.requests.firstWhere((item) => item.id == batch.last.id).status,
        'Pending');
    expect(() => requests.decide(batch.first.id, 'reject', batch.first.version),
        throwsA(isA<Exception>()));
  });

  test('factory batch keeps identity, filtering, stock and decisions isolated',
      () async {
    final store = LocalWarehouseStore.seeded();
    final service = LocalRequestService(store);
    await LocalAuthService(store).login('admin', 'admin123456');
    final bengaluru = store.factories.first;
    final beforeA = bengaluru.materials[0].available;
    final beforeB = bengaluru.materials[1].available;
    final batch = await service.addBatch(
      viewerId: 'user-viewer',
      viewerName: 'Viewer User',
      factoryId: bengaluru.id,
      factoryName: bengaluru.name,
      items: [
        (
          itemId: bengaluru.materials[0].id,
          itemName: bengaluru.materials[0].name,
          quantity: 3
        ),
        (
          itemId: bengaluru.materials[1].id,
          itemName: bengaluru.materials[1].name,
          quantity: 4
        ),
      ],
    );
    expect(batch.map((request) => request.factoryId).toSet(), {bengaluru.id});
    expect(batch.map((request) => request.id).toSet(), hasLength(2));
    await service.decide(batch.first.id, 'accept', batch.first.version);
    await service.decide(batch.last.id, 'reject', batch.last.version);
    final updated = store.factories.first;
    expect(updated.materials[0].available, beforeA - 3);
    expect(updated.materials[1].available, beforeB);
    expect(store.requests.where((request) => request.factoryId == bengaluru.id),
        hasLength(2));
    expect(
        store.requests
            .where((request) => request.factoryId == store.factories.last.id),
        isEmpty);
    expect(await service.unseenDecisionCount('user-viewer', 'Sleeper'), 2);
  });

  test('unseen request decisions are isolated and clear after viewing',
      () async {
    final store = LocalWarehouseStore.seeded();
    final requests = LocalRequestService(store);
    expect(await requests.unseenDecisionCount('user-viewer', 'Depot'), 2);
    expect(await requests.unseenDecisionCount('another-viewer', 'Depot'), 0);

    await requests.markDecisionsSeen(
        'user-viewer', 'Depot', await requests.loadRequests());
    expect(await requests.unseenDecisionCount('user-viewer', 'Depot'), 0);
  });

  testWidgets('viewer footer renders and clears unseen History badge',
      (tester) async {
    final dependencies = _localDependencies();
    addTearDown(dependencies.controller.dispose);
    final session = await dependencies.auth.login('viewer', 'viewer123456');
    await dependencies.controller.init(role: 'viewer');
    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(),
      home: ViewerShell(
        session: session!,
        inventoryController: dependencies.controller,
        requestService: dependencies.requests,
        onLogout: () {},
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('2'), findsOneWidget);
    await tester.tap(find.text('HISTORY'));
    await tester.pumpAndSettle();
    expect(find.text('2'), findsNothing);
  });

  testWidgets('Sleeper requests select a factory and show only its materials',
      (tester) async {
    final dependencies = _localDependencies();
    addTearDown(dependencies.controller.dispose);
    final session = await dependencies.auth.login('viewer', 'viewer123456');
    await dependencies.controller.init(role: 'viewer');
    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(),
      home: Scaffold(
        body: ViewerRequestsView(
          controller: dependencies.controller,
          session: session!,
          section: 'Sleeper',
          requestService: dependencies.requests,
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('No factory-specific request creation is available.'),
        findsNothing);
    expect(find.text('Select Factory'), findsOneWidget);
    await tester.tap(find.byType(DropdownButtonFormField<WarehouseFactory>));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Bengaluru Sleeper Plant').last);
    await tester.pumpAndSettle();
    expect(find.textContaining('SELECTED FACTORY: BENGALURU SLEEPER PLANT'),
        findsOneWidget);
    await tester.tap(find.text('SELECT MATERIAL FROM FACTORY'));
    await tester.pumpAndSettle();
    expect(find.text('PSC SLEEPER'), findsOneWidget);
    expect(find.text('MYSURU INSERT'), findsNothing);
  });

  test('deactivated local account can no longer sign in', () async {
    final store = LocalWarehouseStore.seeded();
    final auth = LocalAuthService(store);
    final users = LocalUserAccountService(store);
    await auth.login('superadmin', 'superadmin123456');
    final viewer = store.users.firstWhere((user) => user.role == 'viewer');
    await users.deleteUser(viewer.id, viewer.version);

    expect(await auth.login('viewer', 'viewer123456'), isNull);
  });

  test('local transactions preserve multiple proofs and material numbers',
      () async {
    final store = LocalWarehouseStore.seeded();
    final inventory = LocalInventoryService(store);
    final transaction = await inventory.createTransaction(
      type: 'INCOMING',
      scope: 'DEPOT',
      factoryId: null,
      items: [
        CartItem(
          id: store.inventory[0].id,
          materialNumber: store.inventory[0].materialNumber,
          name: store.inventory[0].name,
          quantityChange: 9,
        ),
      ],
      billBytes: Uint8List.fromList([0x89, 0x50, 0x4e, 0x47]),
      billName: 'bill.png',
      proofs: [
        TransactionAttachment(
            fileName: 'proof.pdf',
            bytes: Uint8List.fromList([0x25, 0x50, 0x44, 0x46]),
            contentType: 'application/pdf'),
        TransactionAttachment(
            fileName: 'proof.png',
            bytes: Uint8List.fromList([0x89, 0x50, 0x4e, 0x47]),
            contentType: 'image/png'),
      ],
      person: 'Supplier',
      comingFrom: 'Workshop',
      dateOfArrival: '2026-09-11',
      truckNumber: 'TRK-1',
    );

    expect(transaction.proofs, hasLength(2));
    expect(transaction.proofFileIds, hasLength(2));
    expect(transaction.proofFileId, isNull);
    expect(transaction.toJson()['proofFileIds'], transaction.proofFileIds);
    expect(transaction.proofs.first.isPdf, isTrue);
    expect(transaction.items.single.materialNumber, 'T-5836');
    expect(store.audit.singleWhere((entry) => entry.entityId == transaction.id),
        isNotNull);
  });

  test('local attachment downloads remain inside the local service', () async {
    final store = LocalWarehouseStore.seeded();
    final inventory = LocalInventoryService(store);

    final bytes = await inventory.downloadFile('local-bill-seed');

    expect(bytes, isNotEmpty);
  });

  test('local rejection persists trimmed reason and undo suppresses it',
      () async {
    final store = LocalWarehouseStore.seeded();
    final auth = LocalAuthService(store);
    final service = LocalRequestService(store);
    await auth.login('admin', 'admin123456');
    final pending = store.requests.firstWhere((request) => request.isPending);

    final rejected = await service.decide(
      pending.id,
      'reject',
      pending.version,
      reason: '  damaged during delivery  ',
    );

    expect(rejected.status, 'Rejected');
    expect(rejected.currentRejectionReason, 'damaged during delivery');
    expect(rejected.history.last.reason, 'damaged during delivery');
    expect(rejected.toJson()['history'], isNotEmpty);

    await auth.login('superadmin', 'superadmin123456');
    final undone = await service.decide(
      rejected.id,
      'undo',
      rejected.version,
      reason: 'review again',
    );

    expect(undone.status, 'Pending');
    expect(undone.currentRejectionReason, isNull);
    expect(
      undone.history.map((entry) => entry.status).toList(),
      orderedEquals(['Rejected', 'Undone']),
    );
  });
}
