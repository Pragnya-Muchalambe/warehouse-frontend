import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:warehouse_poc/controllers/inventory_controller.dart';
import 'package:warehouse_poc/models/inventory_item.dart';
import 'package:warehouse_poc/services/auth_service.dart';
import 'package:warehouse_poc/theme.dart';
import 'package:warehouse_poc/views/transactions_view.dart';

import 'fake_inventory_service.dart';

void main() {
  testWidgets('Sleeper action form header fits a long factory name',
      (tester) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = InventoryController(
      inventoryService: FakeInventoryService(),
    );
    addTearDown(controller.dispose);
    await controller.init(role: 'admin');
    const factoryName =
        'VERY LONG SLEEPER FACTORY NAME FOR A NARROW ANDROID SCREEN';
    await controller.addFactory(
      name: factoryName,
      location: 'Bangalore',
      materials: const [],
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(),
        home: Scaffold(
          body: TransactionsView(
            controller: controller,
            addTransaction: controller.addTransaction,
            session: const AuthSession(
              username: 'admin',
              role: 'admin',
              name: 'Admin User',
              id: 'AD-1002',
            ),
            fixedSection: InventorySection.sleeper,
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.text(factoryName));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.text('New Incoming'));
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('RECEIVE GOODS'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
