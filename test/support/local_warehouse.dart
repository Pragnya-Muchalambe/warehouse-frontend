import 'dart:typed_data';
import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:warehouse_poc/models/account_request.dart';
import 'package:warehouse_poc/models/audit_log.dart';
import 'package:warehouse_poc/models/factory.dart';
import 'package:warehouse_poc/models/inventory_item.dart';
import 'package:warehouse_poc/models/transaction_log.dart';
import 'package:warehouse_poc/models/user_account.dart';
import 'package:warehouse_poc/models/viewer_request.dart';
import 'package:warehouse_poc/services/account_request_service.dart';
import 'package:warehouse_poc/services/api_client.dart';
import 'package:warehouse_poc/services/auth_service.dart';
import 'package:warehouse_poc/services/inventory_service.dart';
import 'package:warehouse_poc/services/request_service.dart';
import 'package:warehouse_poc/services/user_account_service.dart';

/// Shared, process-lifetime domain state used by every local service adapter.
/// No widget owns fixture data and switching roles does not reset the session.
class LocalWarehouseStore {
  static const storageKey = 'warehouse_local_store_v1';
  static const schemaVersion = 1;

  LocalWarehouseStore._empty();

  LocalWarehouseStore.seeded() {
    final now = DateTime.utc(2026, 9, 11, 9);
    users.addAll([
      _user('user-viewer', 'VW-1001', 'viewer', 'Viewer User', 'viewer', now),
      _user('user-admin', 'AD-1001', 'admin', 'Admin User', 'admin', now),
      _user('user-super', 'SA-1001', 'superadmin', 'Superadmin User',
          'superadmin', now),
    ]);
    passwords.addAll({
      'viewer': createPasswordVerifier('viewer123456', salt: 'seed-viewer'),
      'admin': createPasswordVerifier('admin123456', salt: 'seed-admin'),
      'superadmin':
          createPasswordVerifier('superadmin123456', salt: 'seed-superadmin'),
    });
    inventory.addAll([
      _item('uuid-material-001', 'T-5836', 'Switch for Trap - 52 KG', 60),
      _item('uuid-material-002', 'R-100', 'Rail Pad', 45),
      _item('uuid-material-003', 'C-220', 'Elastic Rail Clip', 80),
    ]);
    factories.add(WarehouseFactory(
      id: 'uuid-factory-001',
      name: 'Bengaluru Sleeper Plant',
      location: 'Bengaluru',
      materialCount: 3,
      createdAt: now,
      updatedAt: now,
      materials: const [
        FactoryMaterial(id: 'uuid-sleeper-001', name: 'PSC Sleeper', total: 40),
        FactoryMaterial(
            id: 'uuid-sleeper-002', name: 'Sleeper Insert', total: 70),
        FactoryMaterial(
            id: 'uuid-sleeper-003', name: 'Rail Seat Pad', total: 55),
      ],
    ));
    factories.add(WarehouseFactory(
      id: 'uuid-factory-002',
      name: 'Mysuru Sleeper Plant',
      location: 'Mysuru',
      materialCount: 1,
      createdAt: now,
      updatedAt: now,
      materials: const [
        FactoryMaterial(
            id: 'uuid-mysuru-001', name: 'Mysuru Insert', total: 30),
      ],
    ));
    accountRequests.add(AccountRequest(
      id: 'account-request-001',
      name: 'Pending Operator',
      requestedId: 'VW-2001',
      role: 'viewer',
      submittedAt: now.add(const Duration(minutes: 15)),
    ));
    requests.addAll([
      ViewerRequest(
        id: 'request-pending-001',
        viewerId: 'user-viewer',
        viewerAccountId: 'VW-1001',
        viewerName: 'Viewer User',
        itemId: 'uuid-material-001',
        materialNumber: 'T-5836',
        itemName: 'Switch for Trap - 52 KG',
        quantity: 3,
        createdAt: now.add(const Duration(minutes: 30)),
      ),
      ViewerRequest(
        id: 'request-accepted-001',
        viewerId: 'user-viewer',
        viewerAccountId: 'VW-1001',
        viewerName: 'Viewer User',
        itemId: 'uuid-material-002',
        materialNumber: 'R-100',
        itemName: 'Rail Pad',
        quantity: 2,
        createdAt: now,
        status: 'Accepted',
        decisionBy: 'admin',
        decisionAt: now.add(const Duration(minutes: 10)),
        version: 2,
      ),
      ViewerRequest(
        id: 'request-rejected-001',
        viewerId: 'user-viewer',
        viewerAccountId: 'VW-1001',
        viewerName: 'Viewer User',
        itemId: 'uuid-material-003',
        materialNumber: 'C-220',
        itemName: 'Elastic Rail Clip',
        quantity: 1,
        createdAt: now.subtract(const Duration(minutes: 5)),
        status: 'Rejected',
        decisionBy: 'admin',
        decisionAt: now.add(const Duration(minutes: 5)),
        version: 2,
      ),
    ]);
    final imageBytes = base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=');
    final pdfBytes = Uint8List.fromList(utf8.encode(
        '%PDF-1.4\n1 0 obj<</Type/Catalog/Pages 2 0 R>>endobj\n2 0 obj<</Type/Pages/Count 0/Kids[]>>endobj\ntrailer<</Root 1 0 R>>\n%%EOF'));
    files['local-bill-seed'] = imageBytes;
    files['local-proof-pdf-seed'] = pdfBytes;
    files['local-proof-image-seed'] = imageBytes;
    final transaction = TransactionLog(
      id: 'transaction-incoming-001',
      timestamp: now.add(const Duration(hours: 1)),
      type: LogType.incoming,
      user: 'Admin User',
      section: InventorySection.depot,
      person: 'Rail Supplier',
      comingFrom: 'Central Workshop',
      dateOfArrival: '2026-09-11',
      truckNumber: 'TRK-100',
      bill: 'bill.png',
      billData: base64Encode(imageBytes),
      billFileId: 'local-bill-seed',
      items: const [
        CartItem(
          id: 'uuid-material-001',
          materialNumber: 'T-5836',
          name: 'Switch for Trap - 52 KG',
          quantityChange: 9,
        ),
        CartItem(
          id: 'uuid-material-002',
          materialNumber: 'R-100',
          name: 'Rail Pad',
          quantityChange: 4,
        ),
      ],
      proofs: [
        TransactionAttachment(
          fileName: 'inspection.pdf',
          bytes: pdfBytes,
          fileId: 'local-proof-pdf-seed',
          contentType: 'application/pdf',
        ),
        TransactionAttachment(
          fileName: 'delivery.png',
          bytes: imageBytes,
          fileId: 'local-proof-image-seed',
          contentType: 'image/png',
        ),
      ],
    );
    transactions.add(transaction);
    final acceptedRequestIndex =
        requests.indexWhere((request) => request.id == 'request-accepted-001');
    requests[acceptedRequestIndex] = requests[acceptedRequestIndex].copyWith(
      relatedTransactionId: transaction.id,
      billAttachment: TransactionAttachment(
        fileName: transaction.bill!,
        bytes: imageBytes,
        fileId: transaction.billFileId,
        contentType: 'image/png',
      ),
    );
    audit.add(AuditLog(
      id: 'audit-transaction-001',
      eventType: 'TRANSACTION_CREATED',
      entityType: 'TRANSACTION',
      entityId: transaction.id,
      actor: const AuditActor(
        id: 'user-admin',
        accountId: 'AD-1001',
        name: 'Admin User',
        role: 'ADMIN',
      ),
      occurredAt: transaction.timestamp,
      requestId: 'local-operation-seed',
      after: const {
        'scope': 'DEPOT',
        'type': 'INCOMING',
        'items': [{}, {}]
      },
    ));
  }

  final List<UserAccount> users = [];
  final Map<String, String> passwords = {};
  final List<InventoryItem> inventory = [];
  final List<WarehouseFactory> factories = [];
  final List<ViewerRequest> requests = [];
  final List<AccountRequest> accountRequests = [];
  final Map<String, String> accountRequestPasswords = {};
  final List<TransactionLog> transactions = [];
  final List<AuditLog> audit = [];
  final Map<String, Uint8List> files = {};
  final Map<String, Set<String>> seenDecisions = {};
  AuthSession? session;
  int sequence = 100;
  bool persistenceEnabled = false;

  static Future<LocalWarehouseStore> loadOrSeed() async {
    final preferences = await SharedPreferences.getInstance();
    final encoded = preferences.getString(storageKey);
    if (encoded != null) {
      try {
        final store = LocalWarehouseStore.fromJson(
            jsonDecode(encoded) as Map<String, dynamic>);
        store.persistenceEnabled = true;
        return store;
      } catch (_) {
        // Invalid or older demo data is replaced by the current seed below.
      }
    }
    final store = LocalWarehouseStore.seeded();
    store.persistenceEnabled = true;
    await store.persist();
    return store;
  }

  Future<void> persist() async {
    if (!persistenceEnabled) return;
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(storageKey, jsonEncode(toJson()));
  }

  Map<String, dynamic> toJson() => {
        'schemaVersion': schemaVersion,
        'users': users.map((value) => value.toJson()).toList(),
        'passwords': passwords,
        'inventory': inventory.map((value) => value.toJson()).toList(),
        'factories': factories.map((value) => value.toJson()).toList(),
        'requests': requests.map((value) => value.toJson()).toList(),
        'accountRequests':
            accountRequests.map((value) => value.toJson()).toList(),
        'accountRequestPasswords': accountRequestPasswords,
        'transactions': transactions.map((value) => value.toJson()).toList(),
        'audit': audit.map((value) => value.toJson()).toList(),
        'files': files.map((key, value) => MapEntry(key, base64Encode(value))),
        'seenDecisions':
            seenDecisions.map((key, value) => MapEntry(key, value.toList())),
        'sequence': sequence,
      };

  factory LocalWarehouseStore.fromJson(Map<String, dynamic> json) {
    if (json['schemaVersion'] != schemaVersion) {
      throw const FormatException('Unsupported local store schema');
    }
    final store = LocalWarehouseStore._empty();
    store.users.addAll((json['users'] as List? ?? [])
        .map((value) => UserAccount.fromJson(value as Map<String, dynamic>)));
    store.passwords.addAll(Map<String, String>.from(json['passwords'] as Map));
    store.inventory.addAll((json['inventory'] as List? ?? [])
        .map((value) => InventoryItem.fromJson(value as Map<String, dynamic>)));
    store.factories.addAll((json['factories'] as List? ?? []).map(
        (value) => WarehouseFactory.fromJson(value as Map<String, dynamic>)));
    store.requests.addAll((json['requests'] as List? ?? [])
        .map((value) => ViewerRequest.fromJson(value as Map<String, dynamic>)));
    store.accountRequests.addAll((json['accountRequests'] as List? ?? []).map(
        (value) => AccountRequest.fromJson(value as Map<String, dynamic>)));
    store.accountRequestPasswords.addAll(Map<String, String>.from(
        json['accountRequestPasswords'] as Map? ?? const {}));
    store.transactions.addAll((json['transactions'] as List? ?? []).map(
        (value) => TransactionLog.fromJson(value as Map<String, dynamic>)));
    store.audit.addAll((json['audit'] as List? ?? [])
        .map((value) => AuditLog.fromJson(value as Map<String, dynamic>)));
    (json['files'] as Map? ?? const {}).forEach((key, value) {
      store.files[key as String] = base64Decode(value as String);
    });
    (json['seenDecisions'] as Map? ?? const {}).forEach((key, value) {
      store.seenDecisions[key as String] = Set<String>.from(value as List);
    });
    store.sequence = (json['sequence'] as num?)?.toInt() ?? 100;
    return store;
  }

  static String createPasswordVerifier(String password, {String? salt}) {
    final actualSalt = salt ??
        List.generate(24, (_) => Random.secure().nextInt(256))
            .map((value) => value.toRadixString(16).padLeft(2, '0'))
            .join();
    final digest = sha256.convert(utf8.encode('$actualSalt:$password'));
    return '$actualSalt:$digest';
  }

  static bool verifyPassword(String password, String verifier) {
    final separator = verifier.indexOf(':');
    if (separator <= 0) return false;
    final salt = verifier.substring(0, separator);
    return createPasswordVerifier(password, salt: salt) == verifier;
  }

  static UserAccount _user(String id, String accountId, String username,
          String name, String role, DateTime now) =>
      UserAccount(
        id: id,
        accountId: accountId,
        username: username,
        name: name,
        role: role,
        status: 'ACTIVE',
        createdAt: now,
        updatedAt: now,
        version: 1,
      );

  static InventoryItem _item(
          String id, String number, String name, int quantity) =>
      InventoryItem(
        id: id,
        materialNumber: number,
        name: name,
        quantity: quantity,
        section: InventorySection.depot,
      );
}

class LocalAuthService extends AuthService {
  LocalAuthService(this.store);
  final LocalWarehouseStore store;

  @override
  Future<AuthSession?> login(String username, String password) async {
    final normalized = username.trim().toLowerCase();
    final user = store.users
        .where((user) =>
            user.username.toLowerCase() == normalized ||
            user.accountId.toLowerCase() == normalized)
        .firstOrNull;
    final verifier = user == null ? null : store.passwords[user.username];
    if (user == null ||
        verifier == null ||
        !LocalWarehouseStore.verifyPassword(password, verifier)) {
      lastErrorMessage = 'Invalid User ID or password.';
      return null;
    }
    return store.session = AuthSession(
      username: user.username,
      role: user.role,
      name: user.name,
      id: user.id,
      accountId: user.accountId,
      version: user.version,
    );
  }

  @override
  Future<AuthSession?> getSession() async => store.session;

  @override
  Future<void> logout() async => store.session = null;
}

class LocalRequestService extends RequestService {
  LocalRequestService(this.store);
  final LocalWarehouseStore store;

  @override
  Future<List<ViewerRequest>> loadRequests() async =>
      List.unmodifiable(store.requests);

  @override
  Future<int> unseenDecisionCount(String viewerId, String section) async {
    final seen = store.seenDecisions[viewerId] ?? const <String>{};
    return store.requests.where((request) {
      final decided =
          request.status == 'Accepted' || request.status == 'Rejected';
      return request.viewerId == viewerId &&
          request.section == section &&
          decided &&
          !seen.contains('${request.id}:${request.version}');
    }).length;
  }

  @override
  Future<void> markDecisionsSeen(
      String viewerId, String section, Iterable<ViewerRequest> requests) async {
    final seen = store.seenDecisions.putIfAbsent(viewerId, () => <String>{});
    for (final request in requests) {
      if (request.viewerId == viewerId &&
          request.section == section &&
          (request.status == 'Accepted' || request.status == 'Rejected')) {
        seen.add('${request.id}:${request.version}');
      }
    }
    await store.persist();
  }

  @override
  Future<ViewerRequest> addRequest({
    required String viewerId,
    required String viewerName,
    required String itemId,
    required String itemName,
    required int quantity,
    String? factoryId,
  }) async {
    final item = store.inventory.where((item) => item.id == itemId).firstOrNull;
    if (item == null || quantity < 1 || quantity > item.available) {
      throw const ApiException('Requested quantity is not available.', 409);
    }
    final request = ViewerRequest(
      id: 'local-request-${++store.sequence}',
      viewerId: viewerId,
      viewerName: viewerName,
      itemId: itemId,
      materialNumber: item.materialNumber,
      itemName: item.name,
      quantity: quantity,
      createdAt: DateTime.now().toUtc(),
    );
    store.requests.insert(0, request);
    await store.persist();
    return request;
  }

  @override
  Future<List<ViewerRequest>> addBatch({
    required String viewerId,
    required String viewerName,
    required List<({String itemId, String itemName, int quantity})> items,
    String? factoryId,
    String? factoryName,
  }) async {
    final factory = factoryId == null
        ? null
        : store.factories.where((item) => item.id == factoryId).firstOrNull;
    if (factoryId != null && factory == null) {
      throw const ApiException('Factory was not found.', 404);
    }
    final inventoryById = factory == null
        ? {for (final item in store.inventory) item.id: item}
        : {
            for (final item in factory.materials)
              item.id: InventoryItem(
                id: item.id,
                materialNumber: item.id,
                name: item.name,
                quantity: item.total,
                biIssued: item.biIssued,
                section: InventorySection.sleeper,
                status: item.status,
              )
          };
    if (items.isEmpty ||
        items.map((item) => item.itemId).toSet().length != items.length) {
      throw const ApiException('Request materials must be unique.', 409);
    }
    for (final line in items) {
      final material = inventoryById[line.itemId];
      if (material == null ||
          line.quantity < 1 ||
          line.quantity > material.available) {
        throw ApiException('${line.itemName} does not have enough stock.', 409);
      }
    }
    final batchId = 'local-request-batch-${++store.sequence}';
    final createdAt = DateTime.now().toUtc();
    final created = items.map((line) {
      final material = inventoryById[line.itemId]!;
      return ViewerRequest(
        id: 'local-request-${++store.sequence}',
        batchId: batchId,
        viewerId: viewerId,
        viewerName: viewerName,
        itemId: line.itemId,
        materialNumber: material.materialNumber,
        itemName: material.name,
        quantity: line.quantity,
        createdAt: createdAt,
        section: factory == null ? 'Depot' : 'Sleeper',
        factoryId: factory?.id,
        factoryName: factory?.name ?? factoryName,
      );
    }).toList();
    store.requests.insertAll(0, created);
    await store.persist();
    return created;
  }

  @override
  Future<ViewerRequest> decide(String id, String action, int version,
      {String? reason}) async {
    final index = store.requests.indexWhere((request) => request.id == id);
    if (index < 0) throw const ApiException('Request was not found.', 404);
    final current = store.requests[index];
    if (current.version != version) {
      throw const ApiException('Request changed. Refresh and try again.', 409,
          code: 'VERSION_CONFLICT');
    }
    var status = current.status;
    final normalizedReason = reason?.trim();
    if (normalizedReason != null && normalizedReason.length > 500) {
      throw const ApiException('Reason must be 500 characters or less.', 400);
    }
    if (action == 'accept') {
      if (!current.isPending) {
        throw const ApiException('Already processed.', 409);
      }
      final itemIndex =
          store.inventory.indexWhere((item) => item.id == current.itemId);
      final factoryIndex = current.factoryId == null
          ? -1
          : store.factories.indexWhere((item) => item.id == current.factoryId);
      final factoryMaterial = factoryIndex < 0
          ? null
          : store.factories[factoryIndex].materials
              .where((item) => item.id == current.itemId)
              .firstOrNull;
      final available = itemIndex >= 0
          ? store.inventory[itemIndex].available
          : factoryMaterial?.available;
      if (available == null || available < current.quantity) {
        throw const ApiException('Insufficient available stock.', 409,
            code: 'INSUFFICIENT_STOCK');
      }
      if (itemIndex >= 0) {
        final item = store.inventory[itemIndex];
        store.inventory[itemIndex] = item.copyWith(
          biIssued: item.biIssued + current.quantity,
          version: item.version + 1,
        );
      } else {
        final factory = store.factories[factoryIndex];
        store.factories[factoryIndex] = factory.copyWith(
          materials: factory.materials
              .map((item) => item.id == current.itemId
                  ? item.copyWith(
                      biIssued: item.biIssued + current.quantity,
                      version: item.version + 1)
                  : item)
              .toList(),
          version: factory.version + 1,
        );
      }
      status = 'Accepted';
    } else if (action == 'reject') {
      if (!current.isPending) {
        throw const ApiException('Already processed.', 409);
      }
      status = 'Rejected';
    } else if (action == 'undo') {
      if (current.isPending) throw const ApiException('Already pending.', 409);
      if (current.status == 'Accepted') {
        final itemIndex =
            store.inventory.indexWhere((item) => item.id == current.itemId);
        if (itemIndex >= 0) {
          final item = store.inventory[itemIndex];
          store.inventory[itemIndex] = item.copyWith(
            biIssued: item.biIssued - current.quantity,
            version: item.version + 1,
          );
        } else if (current.factoryId != null) {
          final factoryIndex = store.factories
              .indexWhere((item) => item.id == current.factoryId);
          if (factoryIndex >= 0) {
            final factory = store.factories[factoryIndex];
            store.factories[factoryIndex] = factory.copyWith(
              materials: factory.materials
                  .map((item) => item.id == current.itemId
                      ? item.copyWith(
                          biIssued: item.biIssued - current.quantity,
                          version: item.version + 1)
                      : item)
                  .toList(),
              version: factory.version + 1,
            );
          }
        }
      }
      status = 'Pending';
    }
    final now = DateTime.now().toUtc();
    final session = store.session;
    final historyStatus = switch (action) {
      'accept' => 'Accepted',
      'reject' => 'Rejected',
      'undo' => 'Undone',
      _ => status,
    };
    final updated = current.copyWith(
      status: status,
      decisionBy: action == 'undo' ? null : session?.role,
      clearDecisionBy: action == 'undo',
      decisionAt: action == 'undo' ? null : now,
      clearDecisionAt: action == 'undo',
      history: [
        ...current.history,
        RequestHistoryEntry(
          status: historyStatus,
          actor: session?.role ?? '',
          actorId: session?.id ?? '',
          actorAccountId: session?.accountId ?? '',
          actorName: session?.name ?? '',
          at: now,
          reason: normalizedReason?.isEmpty == true ? null : normalizedReason,
        ),
      ],
      version: current.version + 1,
      updatedAt: now,
    );
    store.requests[index] = updated;
    await store.persist();
    return updated;
  }
}

class LocalAccountRequestService extends AccountRequestService {
  LocalAccountRequestService(this.store);
  final LocalWarehouseStore store;

  @override
  Future<List<AccountRequest>> loadRequests() async =>
      List.unmodifiable(store.accountRequests);

  @override
  Future<AccountRequest> addRequest({
    required String name,
    required String id,
    required String password,
    required String role,
  }) async {
    final requestedId = id.trim().toUpperCase();
    final normalized = requestedId.toLowerCase();
    final duplicateUser = store.users.any((user) =>
        user.accountId.toLowerCase() == normalized ||
        user.username.toLowerCase() == normalized);
    final duplicateRequest = store.accountRequests.any((request) =>
        request.isPending && request.requestedId.toLowerCase() == normalized);
    if (duplicateUser || duplicateRequest) {
      throw const ApiException('This User ID is already in use.', 409);
    }
    final request = AccountRequest(
      id: 'local-account-request-${++store.sequence}',
      name: name.trim(),
      requestedId: requestedId,
      role: role.toLowerCase(),
      submittedAt: DateTime.now().toUtc(),
    );
    store.accountRequests.insert(0, request);
    store.accountRequestPasswords[request.id] =
        LocalWarehouseStore.createPasswordVerifier(password);
    await store.persist();
    return request;
  }

  @override
  Future<AccountRequest> decide(AccountRequest request, String action,
      {String? reason}) async {
    final index =
        store.accountRequests.indexWhere((item) => item.id == request.id);
    if (index < 0) {
      throw const ApiException('Account request was not found.', 404);
    }
    final current = store.accountRequests[index];
    if (!current.isPending || current.version != request.version) {
      throw const ApiException('Request changed. Refresh and try again.', 409,
          code: 'VERSION_CONFLICT');
    }
    String? approvedPassword;
    if (action == 'approve') {
      final username = current.requestedId.toLowerCase();
      if (store.users.any((user) =>
          user.accountId.toLowerCase() == username ||
          user.username.toLowerCase() == username)) {
        throw const ApiException('This User ID is already in use.', 409);
      }
      approvedPassword = store.accountRequestPasswords[current.id];
      if (approvedPassword == null) {
        throw const ApiException(
            'The registration credential is unavailable.', 409);
      }
    }
    final updated = current.copyWith(
      status: action == 'approve' ? 'Accepted' : 'Rejected',
      decisionBy: store.session?.role,
      decisionAt: DateTime.now().toUtc(),
      version: request.version + 1,
    );
    store.accountRequests[index] = updated;
    if (action == 'approve') {
      final now = DateTime.now().toUtc();
      final username = current.requestedId.toLowerCase();
      store.users.add(LocalWarehouseStore._user(
          'local-user-${++store.sequence}',
          current.requestedId,
          username,
          current.name,
          current.role,
          now));
      store.passwords[username] = approvedPassword!;
    }
    store.accountRequestPasswords.remove(current.id);
    await store.persist();
    return updated;
  }
}

class LocalUserAccountService extends UserAccountService {
  LocalUserAccountService(this.store);
  final LocalWarehouseStore store;

  @override
  Future<List<UserAccount>> loadUsers() async => List.unmodifiable(store.users);

  @override
  Future<void> deleteUser(String id, int version) async {
    if (store.session?.id == id) {
      throw const ApiException('You cannot delete your own account.', 409);
    }
    final user = store.users.where((user) => user.id == id).firstOrNull;
    if (user == null || user.version != version) {
      throw const ApiException('Account changed. Refresh and try again.', 409,
          code: 'VERSION_CONFLICT');
    }
    if (user.role == 'superadmin') {
      throw const ApiException('Superadmin accounts cannot be deleted.', 403);
    }
    store.users.remove(user);
    store.passwords.remove(user.username);
    await store.persist();
  }
}

class LocalInventoryService extends InventoryService {
  LocalInventoryService(this.store);
  final LocalWarehouseStore store;

  @override
  bool get supportsFactoryDeletion => true;

  @override
  Future<List<InventoryItem>> loadInventory() async =>
      List.unmodifiable(store.inventory);
  @override
  Future<List<WarehouseFactory>> loadFactories() async =>
      List.unmodifiable(store.factories);
  @override
  Future<List<TransactionLog>> loadLogs() async =>
      List.unmodifiable(store.transactions);
  @override
  Future<List<AuditLog>> loadAuditLogs() async =>
      List.unmodifiable(store.audit);
  @override
  Future<TransactionLog> getTransaction(String id) async =>
      store.transactions.firstWhere((transaction) => transaction.id == id);

  @override
  Future<InventoryItem> createMaterial(Map<String, dynamic> body) async {
    final item = InventoryItem.fromJson({
      ...body,
      'id': body['id'] ?? 'local-material-${++store.sequence}',
      'materialNumber': body['materialNumber'] ?? body['id'],
      'version': 1,
    });
    store.inventory.add(item);
    await store.persist();
    return item;
  }

  @override
  Future<InventoryItem> updateMaterial(
      String id, int version, Map<String, dynamic> body) async {
    final index = store.inventory.indexWhere((item) => item.id == id);
    if (index < 0) throw const ApiException('Material was not found.', 404);
    final current = store.inventory[index];
    final updated = InventoryItem.fromJson({
      ...current.toJson(),
      ...body,
      'id': current.id,
      'version': current.version + 1,
    });
    store.inventory[index] = updated;
    await store.persist();
    return updated;
  }

  @override
  Future<void> deleteFactory(String id, int version) async {
    final index = store.factories.indexWhere((factory) => factory.id == id);
    if (index < 0) throw const ApiException('Factory was not found.', 404);
    if (store.factories[index].version != version) {
      throw const ApiException('Factory changed. Refresh and try again.', 409,
          code: 'VERSION_CONFLICT');
    }
    store.factories.removeAt(index);
    await store.persist();
  }

  @override
  Future<WarehouseFactory> createFactory(String name, String location) async {
    final factory = WarehouseFactory(
      id: 'local-factory-${++store.sequence}',
      name: name,
      location: location,
      createdAt: DateTime.now().toUtc(),
      updatedAt: DateTime.now().toUtc(),
    );
    store.factories.add(factory);
    await store.persist();
    return factory;
  }

  @override
  Future<FactoryMaterial> createFactoryMaterial(
      String factoryId, Map<String, dynamic> body) async {
    final index =
        store.factories.indexWhere((factory) => factory.id == factoryId);
    if (index < 0) throw const ApiException('Factory was not found.', 404);
    final material = FactoryMaterial.fromJson({...body, 'version': 1});
    final factory = store.factories[index];
    store.factories[index] = factory.copyWith(
      materials: [...factory.materials, material],
      materialCount: factory.materials.length + 1,
      version: factory.version + 1,
    );
    await store.persist();
    return material;
  }

  @override
  Future<FactoryMaterial> updateFactoryMaterial(String factoryId,
      String materialId, int version, Map<String, dynamic> body) async {
    final index =
        store.factories.indexWhere((factory) => factory.id == factoryId);
    if (index < 0) throw const ApiException('Factory was not found.', 404);
    final factory = store.factories[index];
    final current =
        factory.materials.firstWhere((item) => item.id == materialId);
    final updated = FactoryMaterial.fromJson({
      ...current.toJson(),
      ...body,
      'id': current.id,
      'version': current.version + 1,
    });
    store.factories[index] = factory.copyWith(
      materials: factory.materials
          .map((item) => item.id == materialId ? updated : item)
          .toList(),
      version: factory.version + 1,
    );
    await store.persist();
    return updated;
  }

  @override
  Future<TransactionLog> createTransaction({
    required String type,
    required String scope,
    required String? factoryId,
    required List<CartItem> items,
    required Uint8List billBytes,
    required String billName,
    Uint8List? proofBytes,
    String? proofName,
    List<TransactionAttachment> proofs = const [],
    List<String> sourceRequestIds = const [],
    String? notes,
    required String person,
    String? comingFrom,
    String? dateOfArrival,
    String? dateRequested,
    String? dateLeaving,
    required String truckNumber,
  }) async {
    final incoming = type == 'INCOMING';
    final factoryIndex = scope == 'FACTORY'
        ? store.factories.indexWhere((factory) => factory.id == factoryId)
        : -1;
    if (!incoming && scope == 'DEPOT') {
      for (final line in items) {
        final material =
            store.inventory.firstWhere((item) => item.id == line.id);
        if (material.available < line.quantityChange) {
          throw const ApiException('Insufficient available stock.', 409);
        }
      }
    } else if (!incoming && factoryIndex >= 0) {
      final factory = store.factories[factoryIndex];
      for (final line in items) {
        final material =
            factory.materials.firstWhere((item) => item.id == line.id);
        if (material.available < line.quantityChange) {
          throw const ApiException('Insufficient available stock.', 409);
        }
      }
    }
    if (scope == 'DEPOT') {
      for (final line in items) {
        final index = store.inventory.indexWhere((item) => item.id == line.id);
        if (index >= 0) {
          final material = store.inventory[index];
          store.inventory[index] = material.copyWith(
            quantity: incoming ? material.quantity + line.quantityChange : null,
            biIssued: incoming ? null : material.biIssued + line.quantityChange,
            version: material.version + 1,
          );
        }
      }
    } else if (factoryIndex >= 0) {
      final factory = store.factories[factoryIndex];
      final updatedMaterials = factory.materials.map((material) {
        final line = items.where((item) => item.id == material.id).firstOrNull;
        if (line == null) return material;
        return material.copyWith(
          total: incoming ? material.total + line.quantityChange : null,
          biIssued: incoming ? null : material.biIssued + line.quantityChange,
          version: material.version + 1,
        );
      }).toList();
      store.factories[factoryIndex] = factory.copyWith(
        materials: updatedMaterials,
        version: factory.version + 1,
      );
    }
    final billId = 'local-file-${++store.sequence}';
    store.files[billId] = billBytes;
    String? proofId;
    if (proofBytes != null) {
      proofId = 'local-file-${++store.sequence}';
      store.files[proofId] = proofBytes;
    }
    final storedProofs = <TransactionAttachment>[
      if (proofBytes != null && proofName != null)
        TransactionAttachment(
          fileName: proofName,
          bytes: proofBytes,
          fileId: proofId,
        ),
      for (final proof in proofs)
        TransactionAttachment(
          fileName: proof.fileName,
          bytes: proof.bytes,
          fileId: 'local-file-${++store.sequence}',
          contentType: proof.contentType,
        ),
    ];
    for (final proof in storedProofs) {
      if (proof.fileId != null && proof.bytes != null) {
        store.files[proof.fileId!] = proof.bytes!;
      }
    }
    final transaction = TransactionLog(
      id: 'local-transaction-${++store.sequence}',
      timestamp: DateTime.now().toUtc(),
      type: incoming ? LogType.incoming : LogType.dispatch,
      user: store.session?.name ?? person,
      items: List.unmodifiable(items),
      notes: notes,
      bill: billName,
      billData: base64Encode(billBytes),
      proof: proofName,
      proofs: storedProofs,
      billFileId: billId,
      proofFileIds: storedProofs
          .map((proof) => proof.fileId)
          .whereType<String>()
          .toList(),
      section: scope == 'FACTORY'
          ? InventorySection.sleeper
          : InventorySection.depot,
      factoryId: factoryId,
      factoryName:
          store.factories.where((f) => f.id == factoryId).firstOrNull?.name,
      person: person,
      comingFrom: comingFrom,
      dateOfArrival: dateOfArrival,
      dateRequested: dateRequested,
      dateLeaving: dateLeaving,
      truckNumber: truckNumber,
    );
    store.transactions.insert(0, transaction);
    final actor = store.session;
    store.audit.insert(
        0,
        AuditLog(
          id: 'local-audit-${++store.sequence}',
          eventType: 'TRANSACTION_CREATED',
          entityType: 'TRANSACTION',
          entityId: transaction.id,
          actor: AuditActor(
            id: actor?.id ?? '',
            accountId: actor?.accountId ?? '',
            name: actor?.name ?? person,
            role: actor?.role.toUpperCase() ?? 'ADMIN',
          ),
          occurredAt: transaction.timestamp,
          requestId: 'local-operation-${store.sequence}',
          after: {
            'scope': scope,
            'type': type,
            'items': items.map((e) => e.toJson()).toList()
          },
        ));
    await store.persist();
    return transaction;
  }

  @override
  Future<Uint8List> downloadFile(String fileId) async {
    final bytes = store.files[fileId];
    if (bytes == null) {
      throw const ApiException('Attachment was not found.', 404);
    }
    return bytes;
  }
}
