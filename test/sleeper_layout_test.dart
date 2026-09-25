import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:warehouse_poc/controllers/inventory_controller.dart';
import 'package:warehouse_poc/models/factory.dart';
import 'package:warehouse_poc/models/inventory_item.dart';
import 'package:warehouse_poc/services/auth_service.dart';
import 'package:warehouse_poc/theme.dart';
import 'package:warehouse_poc/views/inventory_view.dart';

import 'fake_inventory_service.dart';

void main() {
  testWidgets('open Sleeper factory fits a narrow screen with long names',
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
      location: 'A location with a longer descriptive name',
      materials: const [
        FactoryMaterial(
          id: 'LONG-PL-001',
          name: 'A very long sleeper material description for mobile layout',
          total: 20,
          biIssued: 2,
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(),
        home: Scaffold(
          body: InventoryView(
            controller: controller,
            session: const AuthSession(
              username: 'admin',
              role: 'admin',
              name: 'Admin User',
              id: 'AD-1002',
            ),
            initialSection: InventorySection.sleeper,
            showSectionTabs: false,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text(factoryName));
    await tester.pumpAndSettle();

    expect(find.text('SLEEPER ACTIONS'), findsNothing);
    expect(find.text('ADD NEW MATERIALS - SLEEPER'), findsOneWidget);
    expect(find.text('BACK TO SLEEPER'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
