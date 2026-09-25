import 'dart:async';
import 'package:flutter/foundation.dart';

import '../models/factory.dart';
import '../models/audit_log.dart';
import '../models/inventory_item.dart';
import '../models/purchase_order_status.dart';
import '../models/transaction_log.dart';
import '../models/viewer_request.dart';
import '../services/api_client.dart';
import '../services/inventory_service.dart';
import '../services/request_service.dart';

enum RequestDecision {
  accepted,
  rejected,
  insufficientStock,
  alreadyProcessed,
  undone,
  notAuthorized,
  failed,
}

class InventoryController extends ChangeNotifier {
  InventoryController({
    InventoryService? inventoryService,
    RequestService? requestService,
  })  : _service = inventoryService ?? InventoryService(),
        _requestService = requestService ?? RequestService();

  final InventoryService _service;
  final RequestService _requestService;

  List<InventoryItem> _inventory = [];
  List<TransactionLog> _logs = [];
  List<AuditLog> _auditLogs = [];
  List<WarehouseFactory> _factories = [];
  bool _loading = false;
  InventorySection _activeSection = InventorySection.depot;
  String? lastErrorMessage;
  String? _role;

  List<InventoryItem> get inventory => List.unmodifiable(_inventory);
  List<TransactionLog> get logs => List.unmodifiable(_logs);
  List<AuditLog> get auditLogs => List.unmodifiable(_auditLogs);
  List<WarehouseFactory> get factories => List.unmodifiable(_factories);
  bool get loading => _loading;
  InventorySection get activeSection => _activeSection;
  bool get supportsFactoryDeletion => _service.supportsFactoryDeletion;

  Future<Uint8List> downloadFile(String fileId) =>
      _service.downloadFile(fileId);

  void setSection(InventorySection section, {bool notify = true}) {
    if (_activeSection == section) return;
    _activeSection = section;
    if (notify) notifyListeners();
  }

  List<InventoryItem> itemsInSection(InventorySection section) {
    return _inventory.where((item) => item.isInSection(section)).toList();
  }

  Future<void> init({required String role}) async {
    _role = role;
    _loading = true;
    lastErrorMessage = null;
    notifyListeners();
    final errors = <String>[];
    final privileged = role == 'admin' || role == 'superadmin';
    if (!privileged) {
      _logs = [];
      _auditLogs = [];
    }
    await Future.wait([
      _loadSafely(
          _service.loadInventory, (value) => _inventory = value, errors),
      _loadSafely(
          _service.loadFactories, (value) => _factories = value, errors),
      if (privileged)
        _loadSafely(_service.loadLogs, (value) => _logs = value, errors),
      if (privileged)
        _loadSafely(
          _service.loadAuditLogs,
          (value) => _auditLogs = value,
          errors,
        ),
    ]);
    lastErrorMessage = errors.firstOrNull;
    _loading = false;
    notifyListeners();
  }

  Future<void> _loadSafely<T>(
    Future<List<T>> Function() load,
    void Function(List<T>) assign,
    List<String> errors,
  ) async {
    try {
      assign(await load());
    } on ApiException catch (error) {
      errors.add(error.message);
    } catch (_) {
      errors.add('The server returned invalid data.');
    }
  }

  Future<void> addTransaction({
    required String type,
    required List<CartItem> items,
    String? notes,
    String? bill,
    String? billData,
    String? proof,
    String? proofData,
    required String user,
    InventorySection? section,
    String? person,
    String? comingFrom,
    String? dateOfArrival,
    String? dateRequested,
    String? dateLeaving,
    String? truckNumber,
    Uint8List? billBytes,
    Uint8List? proofBytes,
    List<TransactionAttachment> proofs = const [],
    String? factoryId,
    List<String> sourceRequestIds = const [],
  }) async {
    if (!_isAdmin) {
      throw const ApiException('Action not permitted.', 403, code: 'FORBIDDEN');
    }
    if (billBytes == null || bill == null) {
      throw const ApiException(
          'Please upload the Bill before submitting this transaction.', 0);
    }
    final scope = section == InventorySection.sleeper ? 'FACTORY' : 'DEPOT';
    if (scope == 'FACTORY' && (factoryId == null || factoryId.isEmpty)) {
      throw const ApiException('Select a factory for Sleeper transactions.', 0);
    }
    final isIncoming = type == LogType.incoming.label;
    final transaction = await _service.createTransaction(
      type: type,
      scope: scope,
      factoryId: scope == 'FACTORY' ? factoryId : null,
      items: items,
      billBytes: billBytes,
      billName: bill,
      proofBytes: proofBytes,
      proofName: proof,
      proofs: proofs,
      notes: notes,
      person: person ?? '',
      comingFrom: isIncoming ? comingFrom : null,
      dateOfArrival: isIncoming ? dateOfArrival : null,
      dateRequested: isIncoming ? null : dateRequested,
      dateLeaving: isIncoming ? null : dateLeaving,
      truckNumber: truckNumber ?? '',
      sourceRequestIds: sourceRequestIds,
    );
    await _refreshStock();
    _logs = [transaction, ..._logs.where((log) => log.id != transaction.id)];
    await _refreshAuditLogs();
    notifyListeners();
  }

  Future<void> editTransaction({
    required String logId,
    required List<CartItem> updatedItems,
    required String user,
    String? reason,
  }) async {
    final index = _logs.indexWhere((log) => log.id == logId);
    if (index == -1) return;
    final current = await _service.getTransaction(logId);
    try {
      final updated = await _service.correctTransaction(
        current,
        updatedItems,
        reason,
      );
      _logs = _logs.map((log) => log.id == logId ? updated : log).toList();
      await _refreshStock();
      await _refreshAuditLogs();
      notifyListeners();
    } on ApiException catch (error) {
      if (error.isVersionConflict) {
        _logs = await _service.loadLogs();
        await _refreshStock();
      }
      rethrow;
    }
  }

  Future<bool> registerSearch(List<String> ids) async {
    final uniqueIds = ids.toSet().take(100).toList();
    if (uniqueIds.isEmpty) return false;
    final searchedAt = DateTime.now().toUtc();
    final previous = {
      for (final item in _inventory)
        if (uniqueIds.contains(item.id)) item.id: item,
    };
    _inventory = _inventory.map((item) {
      if (!previous.containsKey(item.id)) return item;
      return item.copyWith(
        searchFrequency: item.searchFrequency + 1,
        lastSearchedAt: searchedAt,
      );
    }).toList();
    notifyListeners();
    try {
      final updates = await _service.registerSearch(uniqueIds);
      final byId = {for (final update in updates) update.materialId: update};
      _inventory = _inventory.map((item) {
        final update = byId[item.id];
        return update == null
            ? item
            : item.copyWith(
                searchFrequency: update.searchFrequency,
                lastSearchedAt: update.lastSearchedAt,
              );
      }).toList();
      notifyListeners();
      return true;
    } on ApiException catch (error) {
      _inventory = _inventory.map((item) {
        final old = previous[item.id];
        if (old == null || item.lastSearchedAt != searchedAt) return item;
        return old;
      }).toList();
      lastErrorMessage = error.message;
      notifyListeners();
      return false;
    }
  }

  Future<bool> addMaterial({
    required String id,
    required String name,
    required InventorySection section,
    required int total,
    required int biIssued,
    required int incomingQuantity,
    required DateTime? expectedAvailabilityDate,
    required PurchaseOrderStatus purchaseOrderStatus,
    String? reason,
  }) async {
    if (!_isAdmin) return false;
    if (!_validMaterial(
      id,
      total,
      biIssued,
      incomingQuantity,
      expectedAvailabilityDate,
      purchaseOrderStatus,
    )) {
      return false;
    }
    try {
      final item = await _service.createMaterial(
        _materialBody(
          id,
          name,
          section,
          total,
          biIssued,
          incomingQuantity,
          expectedAvailabilityDate,
          purchaseOrderStatus,
        ),
      );
      _inventory = [item, ..._inventory];
      notifyListeners();
      return true;
    } on ApiException catch (error) {
      lastErrorMessage = error.message;
      return false;
    }
  }

  Future<bool> editMaterial({
    required String originalId,
    required String id,
    required String name,
    required InventorySection section,
    required int total,
    required int biIssued,
    required int incomingQuantity,
    required DateTime? expectedAvailabilityDate,
    required PurchaseOrderStatus purchaseOrderStatus,
    String? reason,
  }) async {
    if (!_isAdmin) return false;
    if (!_validMaterial(
      id,
      total,
      biIssued,
      incomingQuantity,
      expectedAvailabilityDate,
      purchaseOrderStatus,
    )) {
      return false;
    }
    final index = _inventory.indexWhere((item) => item.id == originalId);
    if (index == -1) return false;
    final body = _materialBody(
      id,
      name,
      section,
      total,
      biIssued,
      incomingQuantity,
      expectedAvailabilityDate,
      purchaseOrderStatus,
    );
    if (reason != null && reason.trim().isNotEmpty) {
      body['reason'] = reason.trim();
    }
    try {
      final updated = await _service.updateMaterial(
        originalId,
        _inventory[index].version,
        body,
      );
      _inventory = _inventory
          .map((item) => item.id == originalId ? updated : item)
          .toList();
      notifyListeners();
      return true;
    } on ApiException catch (error) {
      lastErrorMessage = error.message;
      if (error.isVersionConflict) {
        await _reloadInventoryAfterConflict();
      }
      return false;
    }
  }

  Future<bool> editFactoryMaterial({
    required String factoryId,
    required String materialId,
    required String id,
    required String name,
    required int total,
    required int biIssued,
    required int incomingQuantity,
    required DateTime? expectedAvailabilityDate,
    required PurchaseOrderStatus purchaseOrderStatus,
    String? reason,
  }) async {
    if (!_isAdmin) return false;
    if (!_validMaterial(
      id,
      total,
      biIssued,
      incomingQuantity,
      expectedAvailabilityDate,
      purchaseOrderStatus,
    )) {
      return false;
    }
    final factory =
        _factories.where((item) => item.id == factoryId).firstOrNull;
    final material =
        factory?.materials.where((item) => item.id == materialId).firstOrNull;
    if (factory == null || material == null) return false;
    final body = _factoryMaterialBody(
      id,
      name,
      total,
      biIssued,
      incomingQuantity,
      expectedAvailabilityDate,
      purchaseOrderStatus,
    );
    if (reason != null && reason.trim().isNotEmpty) {
      body['reason'] = reason.trim();
    }
    try {
      final updated = await _service.updateFactoryMaterial(
        factoryId,
        materialId,
        material.version,
        body,
      );
      _factories = _factories.map((item) {
        if (item.id != factoryId) return item;
        return item.copyWith(
          materials: item.materials
              .map((entry) => entry.id == materialId ? updated : entry)
              .toList(),
        );
      }).toList();
      notifyListeners();
      return true;
    } on ApiException catch (error) {
      lastErrorMessage = error.message;
      if (error.isVersionConflict) {
        await _reloadFactoriesAfterConflict();
      }
      return false;
    }
  }

  Future<bool> addFactory({
    required String name,
    required String location,
    required List<FactoryMaterial> materials,
  }) async {
    if (!_isAdmin) return false;
    lastErrorMessage = null;
    final materialIds =
        materials.map((material) => material.id.trim().toLowerCase()).toList();
    if (name.trim().isEmpty ||
        location.trim().isEmpty ||
        materialIds.toSet().length != materialIds.length ||
        materials.any(
          (material) => !_validMaterial(
            material.id,
            material.total,
            material.biIssued,
            material.incomingQuantity,
            material.expectedAvailabilityDate,
            material.purchaseOrderStatus,
          ),
        )) {
      return false;
    }
    WarehouseFactory factory;
    try {
      factory = await _service.createFactory(name.trim(), location.trim());
    } on ApiException catch (error) {
      lastErrorMessage = error.message;
      return false;
    }
    var current = factory;
    _factories = [current, ..._factories];
    notifyListeners();
    for (final material in materials) {
      try {
        final created = await _service.createFactoryMaterial(
          factory.id,
          _factoryMaterialBody(
            material.id,
            material.name,
            material.total,
            material.biIssued,
            material.incomingQuantity,
            material.expectedAvailabilityDate,
            material.purchaseOrderStatus,
          ),
        );
        current = current.copyWith(
          materials: [...current.materials, created],
          materialCount: current.materials.length + 1,
        );
        _replaceFactory(current);
      } on ApiException catch (error) {
        try {
          current = current.copyWith(
            materials: await _service.loadFactoryMaterials(factory.id),
          );
          _replaceFactory(current);
        } on ApiException {
          // Keep the factory and confirmed materials already returned.
        }
        lastErrorMessage =
            'Factory created, but material ${material.id} failed: ${error.message}';
        notifyListeners();
        return true;
      }
    }
    notifyListeners();
    return true;
  }

  Future<bool> deleteFactory(String id) async {
    if (_role != 'superadmin') return false;
    if (!_service.supportsFactoryDeletion) {
      lastErrorMessage = 'Factory deletion is not supported by this server.';
      return false;
    }
    final factory = _factories.where((item) => item.id == id).firstOrNull;
    if (factory == null) return false;
    lastErrorMessage = null;
    try {
      await _service.deleteFactory(factory.id, factory.version);
      try {
        _factories = await _service.loadFactories();
      } on ApiException catch (error) {
        _factories = _factories.where((item) => item.id != factory.id).toList();
        lastErrorMessage =
            'Factory deleted, but refresh failed: ${error.message}';
      }
      notifyListeners();
      return true;
    } on ApiException catch (error) {
      lastErrorMessage = error.message;
      if (error.isVersionConflict) await _reloadFactoriesAfterConflict();
      notifyListeners();
      return false;
    }
  }

  void _replaceFactory(WarehouseFactory factory) {
    _factories = _factories
        .map((item) => item.id == factory.id ? factory : item)
        .toList();
  }

  Future<bool> addFactoryMaterial({
    required String factoryId,
    required String id,
    required String name,
    required int total,
    required int biIssued,
    required int incomingQuantity,
    required DateTime? expectedAvailabilityDate,
    required PurchaseOrderStatus purchaseOrderStatus,
    String? reason,
  }) async {
    if (!_isAdmin) return false;
    if (!_validMaterial(
      id,
      total,
      biIssued,
      incomingQuantity,
      expectedAvailabilityDate,
      purchaseOrderStatus,
    )) {
      return false;
    }
    if (!_factories.any((factory) => factory.id == factoryId)) return false;
    try {
      final material = await _service.createFactoryMaterial(
        factoryId,
        _factoryMaterialBody(
          id,
          name,
          total,
          biIssued,
          incomingQuantity,
          expectedAvailabilityDate,
          purchaseOrderStatus,
        ),
      );
      _factories = _factories.map((factory) {
        if (factory.id != factoryId) return factory;
        return factory.copyWith(
          materials: [material, ...factory.materials],
          materialCount: factory.materialCount + 1,
        );
      }).toList();
      notifyListeners();
      return true;
    } on ApiException catch (error) {
      lastErrorMessage = error.message;
      return false;
    }
  }

  Future<RequestDecision> acceptRequest({
    required String requestId,
    required String user,
    required String role,
  }) async {
    if (!_isAdmin) return RequestDecision.notAuthorized;
    final request = await _findRequest(requestId);
    if (request == null || !request.isPending) {
      return RequestDecision.alreadyProcessed;
    }
    try {
      await _requestService.decide(requestId, 'accept', request.version);
      await _refreshInventoryAfterRequestDecision();
      return RequestDecision.accepted;
    } on ApiException catch (error) {
      lastErrorMessage = error.message;
      return error.code == 'INSUFFICIENT_STOCK'
          ? RequestDecision.insufficientStock
          : RequestDecision.failed;
    }
  }

  Future<RequestDecision> rejectRequest({
    required String requestId,
    required String user,
    required String role,
    String? reason,
  }) async {
    if (!_isAdmin) return RequestDecision.notAuthorized;
    final request = await _findRequest(requestId);
    if (request == null || !request.isPending) {
      return RequestDecision.alreadyProcessed;
    }
    try {
      await _requestService.decide(
        requestId,
        'reject',
        request.version,
        reason: reason,
      );
      return RequestDecision.rejected;
    } on ApiException catch (error) {
      lastErrorMessage = error.message;
      return RequestDecision.failed;
    }
  }

  Future<RequestDecision> undoRequest({
    required String requestId,
    required String user,
    required String role,
    String? reason,
  }) async {
    if (_role != 'superadmin') return RequestDecision.notAuthorized;
    final request = await _findRequest(requestId);
    if (request == null || request.isPending) {
      return RequestDecision.alreadyProcessed;
    }
    try {
      await _requestService.decide(
        requestId,
        'undo',
        request.version,
        reason: reason,
      );
      await _refreshInventoryAfterRequestDecision();
      return RequestDecision.undone;
    } on ApiException catch (error) {
      lastErrorMessage = error.message;
      return RequestDecision.failed;
    }
  }

  Future<ViewerRequest?> _findRequest(String requestId) async {
    try {
      return (await _requestService.loadRequests())
          .where((request) => request.id == requestId)
          .firstOrNull;
    } on ApiException catch (error) {
      lastErrorMessage = error.message;
      return null;
    }
  }

  Future<void> _refreshInventoryAfterRequestDecision() async {
    try {
      final results = await Future.wait([
        _service.loadInventory(),
        _service.loadFactories(),
      ]);
      _inventory = results[0] as List<InventoryItem>;
      _factories = results[1] as List<WarehouseFactory>;
    } on ApiException catch (error) {
      _inventory = [];
      lastErrorMessage =
          'The decision succeeded, but inventory refresh failed: ${error.message}';
    }
    notifyListeners();
  }

  bool get _isAdmin => _role == 'admin' || _role == 'superadmin';

  Future<void> _reloadInventoryAfterConflict() async {
    try {
      _inventory = await _service.loadInventory();
      notifyListeners();
    } on ApiException catch (error) {
      lastErrorMessage = error.message;
    }
  }

  Future<void> _reloadFactoriesAfterConflict() async {
    try {
      _factories = await _service.loadFactories();
      notifyListeners();
    } on ApiException catch (error) {
      lastErrorMessage = error.message;
    }
  }

  Future<void> _refreshStock() async {
    final errors = <String>[];
    await Future.wait([
      _loadSafely(
          _service.loadInventory, (value) => _inventory = value, errors),
      _loadSafely(
          _service.loadFactories, (value) => _factories = value, errors),
    ]);
    if (errors.isNotEmpty) lastErrorMessage = errors.first;
  }

  Future<void> _refreshAuditLogs() async {
    try {
      _auditLogs = await _service.loadAuditLogs();
    } on ApiException catch (error) {
      lastErrorMessage = error.message;
    }
  }

  bool _validMaterial(
    String id,
    int total,
    int biIssued,
    int incoming,
    DateTime? expected,
    PurchaseOrderStatus status,
  ) {
    if (id.trim().isEmpty ||
        total < 0 ||
        total > 2147483647 ||
        biIssued < 0 ||
        biIssued > total ||
        incoming < 0 ||
        incoming > 2147483647) {
      return false;
    }
    return switch (status) {
      PurchaseOrderStatus.none => incoming == 0 && expected == null,
      PurchaseOrderStatus.pending => incoming > 0,
      PurchaseOrderStatus.ordered => incoming > 0 && expected != null,
    };
  }

  Map<String, dynamic> _materialBody(
    String id,
    String name,
    InventorySection section,
    int total,
    int biIssued,
    int incoming,
    DateTime? expected,
    PurchaseOrderStatus status,
  ) =>
      {
        'id': id.trim(),
        'name': name.trim(),
        'quantity': total,
        'biIssued': biIssued,
        'uom': 'Pieces',
        'section': section.name.toUpperCase(),
        'incomingQuantity': incoming,
        'expectedAvailabilityDate': _dateOnly(expected),
        'purchaseOrderStatus': status.apiValue,
      };

  Map<String, dynamic> _factoryMaterialBody(
    String id,
    String name,
    int total,
    int biIssued,
    int incoming,
    DateTime? expected,
    PurchaseOrderStatus status,
  ) =>
      {
        'id': id.trim(),
        'name': name.trim(),
        'total': total,
        'biIssued': biIssued,
        'incomingQuantity': incoming,
        'expectedAvailabilityDate': _dateOnly(expected),
        'purchaseOrderStatus': status.apiValue,
      };

  String? _dateOnly(DateTime? date) => date == null
      ? null
      : '${date.year.toString().padLeft(4, '0')}-'
          '${date.month.toString().padLeft(2, '0')}-'
          '${date.day.toString().padLeft(2, '0')}';
}
