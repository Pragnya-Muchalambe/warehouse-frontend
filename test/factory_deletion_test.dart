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

class _FailingDeletionService extends InventoryService {
  final WarehouseFactory factory;
  int calls = 0;

  _FailingDeletionService(this.factory);

  @override
  bool get supportsFactoryDeletion => true;

  @override
  Future<List<InventoryItem>> loadInventory() async => const [];

  @override
  Future<List<WarehouseFactory>> loadFactories() async => [factory];

  @override
  Future<void> deleteFactory(String id, int version) async {
    calls++;
    throw const ApiException('Factory could not be deleted.', 409);
  }
}

void main() {
  testWidgets('selected factory deletion leaves detail before list refresh',
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

    await tester.tap(find.text('DELETE FACTORY'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('factory-delete-confirmation')),
      factory.name,
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('confirm-factory-delete')));
    await tester.pumpAndSettle();

    expect(controller.factories.any((item) => item.id == factory.id), isFalse);
    expect(selections.last, isNull);
    expect(find.text('LIVE INVENTORY'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('failed deletion restores selected factory and allows retry',
      (tester) async {
    const factory = WarehouseFactory(
      id: 'factory-authoritative-id',
      name: 'Factory Failure',
      location: 'North',
    );
    final service = _FailingDeletionService(factory);
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
    await tester.tap(find.text('DELETE FACTORY'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('factory-delete-confirmation')),
      factory.name,
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('confirm-factory-delete')));
    await tester.pumpAndSettle();

    expect(service.calls, 1);
    expect(find.text('Factory Failure'), findsOneWidget);
    expect(find.text('DELETE FACTORY'), findsOneWidget);
    expect(find.text('Factory could not be deleted.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('real API service does not advertise factory deletion', () {
    expect(InventoryService().supportsFactoryDeletion, isFalse);
  });
}
