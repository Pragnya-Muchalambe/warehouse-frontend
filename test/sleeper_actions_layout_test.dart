import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:warehouse_poc/controllers/inventory_controller.dart';
import 'package:warehouse_poc/services/auth_service.dart';
import 'package:warehouse_poc/theme.dart';
import 'package:warehouse_poc/views/transactions_view.dart';

void main() {
  testWidgets('Sleeper action form header fits a long factory name',
      (tester) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({});

    final controller = InventoryController();
    addTearDown(controller.dispose);
    await controller.init();
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
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.text('SLEEPER'));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.text(factoryName));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.text('New Incoming'));
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('RECEIVE GOODS'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
