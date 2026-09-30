import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:warehouse_poc/controllers/inventory_controller.dart';
import 'package:warehouse_poc/models/factory.dart';
import 'package:warehouse_poc/models/inventory_item.dart';
import 'package:warehouse_poc/services/api_client.dart';
import 'package:warehouse_poc/services/auth_service.dart';
import 'package:warehouse_poc/services/inventory_service.dart';
import 'support/local_warehouse.dart';
import 'package:warehouse_poc/theme.dart';
import 'package:warehouse_poc/views/inventory_view.dart';

const _superadmin = AuthSession(
  username: 'superadmin',
  role: 'superadmin',
  name: 'Superadmin',
  id: 'superadmin-id',
  accountId: 'SA-1',
);

class _FailingArchivalService extends InventoryService {
  final WarehouseFactory factory;
  int calls = 0;

  _FailingArchivalService(this.factory);

  @override
  bool get supportsFactoryArchival => true;

  @override
  Future<List<InventoryItem>> loadInventory() async => const [];

  @override
  Future<List<WarehouseFactory>> loadFactories() async => [factory];

  @override
  Future<void> archiveFactory(String id, int version) async {
    calls++;
    throw const ApiException('Factory has active dependencies.', 409,
        code: 'FACTORY_HAS_ACTIVE_DEPENDENCIES');
  }
}

class _RecordingArchivalService extends InventoryService {
  _RecordingArchivalService(this.factory, {this.failure});

  final WarehouseFactory factory;
  final ApiException? failure;
  int calls = 0;
  int factoryLoads = 0;
  String? archivedId;
  int? archivedVersion;

  @override
  Future<List<InventoryItem>> loadInventory() async => const [];

  @override
  Future<List<WarehouseFactory>> loadFactories() async {
    factoryLoads++;
    return [factory];
  }

  @override
  Future<void> archiveFactory(String id, int version) async {
    calls++;
    archivedId = id;
    archivedVersion = version;
    if (failure != null) throw failure!;
  }
}

void main() {
  testWidgets('selected factory archival leaves detail before list refresh',
      (tester) async {
    final store = LocalWarehouseStore.seeded();
    final controller = InventoryController(
      inventoryService: LocalInventoryService(store),
    );
    await controller.init(role: 'superadmin');
    addTearDown(controller.dispose);
    final factory = controller.factories.first;
    final selections = <String?>[];
    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(),
      home: Scaffold(
        body: InventoryView(
          controller: controller,
          session: _superadmin,
          initialSection: InventorySection.sleeper,
          showSectionTabs: false,
          onOpenSleeperActions: selections.add,
        ),
      ),
    ));
    await tester.tap(find.text(factory.name.toUpperCase()).first);
    await tester.pumpAndSettle();
    expect(selections.last, factory.id);

    await tester.tap(find.text('ARCHIVE FACTORY'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('factory-archive-confirmation')),
      factory.name,
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('confirm-factory-archive')));
    await tester.pumpAndSettle();

    expect(controller.factories.any((item) => item.id == factory.id), isFalse);
    expect(selections.last, isNull);
    expect(find.text('LIVE INVENTORY'), findsOneWidget);
    expect(find.text('Factory archived.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('active dependency failure restores selected factory and retries',
      (tester) async {
    const factory = WarehouseFactory(
      id: 'factory-authoritative-id',
      name: 'Factory Failure',
      location: 'North',
    );
    final service = _FailingArchivalService(factory);
    final controller = InventoryController(inventoryService: service);
    await controller.init(role: 'superadmin');
    addTearDown(controller.dispose);
    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(),
      home: Scaffold(
        body: InventoryView(
          controller: controller,
          session: _superadmin,
          initialSection: InventorySection.sleeper,
          showSectionTabs: false,
        ),
      ),
    ));
    await tester.tap(find.text('FACTORY FAILURE'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ARCHIVE FACTORY'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('factory-archive-confirmation')),
      factory.name,
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('confirm-factory-archive')));
    await tester.pumpAndSettle();

    expect(service.calls, 1);
    expect(find.text('Factory Failure'), findsOneWidget);
    expect(find.text('ARCHIVE FACTORY'), findsOneWidget);
    expect(find.text('Factory has active dependencies.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('cancelling archival never calls the API', (tester) async {
    const factory = WarehouseFactory(
      id: 'factory-authoritative-id',
      name: 'Factory Cancel',
      location: 'North',
    );
    final service = _RecordingArchivalService(factory);
    final controller = InventoryController(inventoryService: service);
    await controller.init(role: 'superadmin');
    addTearDown(controller.dispose);
    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(),
      home: Scaffold(
        body: InventoryView(
          controller: controller,
          session: _superadmin,
          initialSection: InventorySection.sleeper,
          showSectionTabs: false,
        ),
      ),
    ));

    await tester.tap(find.text('FACTORY CANCEL'));
    await tester.pumpAndSettle();
    expect(find.text('ARCHIVE FACTORY'), findsOneWidget);
    await tester.tap(find.text('ARCHIVE FACTORY'));
    await tester.pumpAndSettle();
    expect(find.text('Archive Factory'), findsNWidgets(2));
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(service.calls, 0);
  });

  test('only Superadmin can archive with authoritative ID and version',
      () async {
    const factory = WarehouseFactory(
      id: 'factory-authoritative-id',
      name: 'Factory',
      location: 'North',
      version: 7,
    );
    for (final role in ['viewer', 'admin']) {
      final service = _RecordingArchivalService(factory);
      final controller = InventoryController(inventoryService: service);
      await controller.init(role: role);
      expect(await controller.archiveFactory(factory.id), isFalse);
      expect(service.calls, 0);
      controller.dispose();
    }

    final service = _RecordingArchivalService(factory);
    final controller = InventoryController(inventoryService: service);
    await controller.init(role: 'superadmin');
    expect(await controller.archiveFactory(factory.id), isTrue);
    expect(service.archivedId, factory.id);
    expect(service.archivedVersion, factory.version);
    controller.dispose();
  });

  test('version conflict reloads authoritative factories', () async {
    const factory = WarehouseFactory(
      id: 'factory-authoritative-id',
      name: 'Factory',
      location: 'North',
    );
    final service = _RecordingArchivalService(
      factory,
      failure:
          const ApiException('Factory changed.', 412, code: 'VERSION_CONFLICT'),
    );
    final controller = InventoryController(inventoryService: service);
    await controller.init(role: 'superadmin');

    expect(await controller.archiveFactory(factory.id), isFalse);
    expect(service.factoryLoads, 2);
    controller.dispose();
  });

  test('real API service advertises factory archival', () {
    expect(InventoryService().supportsFactoryArchival, isTrue);
  });

  test('factory API parsing requires a valid concurrency version', () {
    expect(
      () => WarehouseFactory.fromJson({
        'id': 'factory-id',
        'name': 'Factory',
        'location': 'North',
      }),
      throwsFormatException,
    );
    expect(
      () => WarehouseFactory.fromJson({
        'id': 'factory-id',
        'name': 'Factory',
        'location': 'North',
        'version': 0,
      }),
      throwsFormatException,
    );
  });
}
