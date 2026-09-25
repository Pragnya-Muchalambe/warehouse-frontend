import 'package:flutter/foundation.dart';

import 'controllers/inventory_controller.dart';
import 'services/account_request_service.dart';
import 'services/auth_service.dart';
import 'services/inventory_service.dart';
import 'services/request_service.dart';
import 'services/user_account_service.dart';
import 'services/transaction_file_picker.dart';

class AppDependencies {
  AppDependencies({
    required this.auth,
    required this.inventory,
    required this.requests,
    required this.accountRequests,
    required this.users,
    required this.transactionFilePicker,
  }) : controller = InventoryController(
          inventoryService: inventory,
          requestService: requests,
        );

  factory AppDependencies.production() => AppDependencies(
        auth: AuthService(),
        inventory: InventoryService(),
        requests: RequestService(),
        accountRequests: AccountRequestService(),
        users: UserAccountService(),
        transactionFilePicker: kIsWeb
            ? PlatformTransactionFilePicker.initialized()
            : const PlatformTransactionFilePicker(),
      );

  @visibleForTesting
  factory AppDependencies.forTesting({
    required AuthService auth,
    required InventoryService inventory,
    required RequestService requests,
    required AccountRequestService accountRequests,
    required UserAccountService users,
    required TransactionFilePicker transactionFilePicker,
  }) =>
      AppDependencies(
        auth: auth,
        inventory: inventory,
        requests: requests,
        accountRequests: accountRequests,
        users: users,
        transactionFilePicker: transactionFilePicker,
      );

  static Future<AppDependencies> loadFromEnvironment() async =>
      AppDependencies.production();

  final AuthService auth;
  final InventoryService inventory;
  final RequestService requests;
  final AccountRequestService accountRequests;
  final UserAccountService users;
  final InventoryController controller;
  final TransactionFilePicker transactionFilePicker;
}
