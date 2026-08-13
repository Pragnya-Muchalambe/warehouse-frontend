import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/factory.dart';
import '../models/inventory_item.dart';
import '../models/purchase_order_status.dart';
import '../models/transaction_log.dart';
import '../models/viewer_request.dart';
import '../services/inventory_service.dart';
import '../services/request_service.dart';

/// Outcome of processing a Viewer request.
enum RequestDecision {
  accepted,
  rejected,
  insufficientStock,
  alreadyProcessed,
  undone,
  notAuthorized,
}

class InventoryController extends ChangeNotifier {
  final InventoryService _service = InventoryService();

  List<InventoryItem> _inventory = [];
  List<TransactionLog> _logs = [];
  List<WarehouseFactory> _factories = [];
  bool _loading = true;
  InventorySection _activeSection = InventorySection.depot;

  List<InventoryItem> get inventory => List.unmodifiable(_inventory);
  List<TransactionLog> get logs => List.unmodifiable(_logs);
  List<WarehouseFactory> get factories => List.unmodifiable(_factories);
  bool get loading => _loading;
  InventorySection get activeSection => _activeSection;

  void setSection(InventorySection section, {bool notify = true}) {
    if (_activeSection == section) return;
    _activeSection = section;
    if (notify) notifyListeners();
  }

  List<InventoryItem> itemsInSection(InventorySection section) {
    return _inventory.where((i) => i.isInSection(section)).toList();
  }

  Future<void> init() async {
    _loading = true;
    notifyListeners();
    try {
      _inventory = await _service.loadInventory();
      _logs = await _service.loadLogs();
      _factories = await _service.loadFactories();
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  /// Matches `addTransaction` from utils/inventory.js.
  /// [type] is the raw label: 'INCOMING' or 'DISPATCH'.
  /// [section] / [factoryName] tag the action so Depot and Sleeper (factory)
  /// actions stay separated in the audit trail.
  ///
  /// Depot dispatch raises BI Issued (Total stays fixed) so Available shrinks
  /// without reducing stock on hand. Factory (Sleeper) dispatch keeps the
  /// legacy behaviour of reducing the factory's total. Incoming always adds
  /// to Total and leaves BI Issued untouched.
  Future<void> addTransaction({
    required String type,
    required List<CartItem> items,
    String? notes,
    String? photo,
    String? photoData,
    required String user,
    InventorySection? section,
    String? factoryName,
    String? person,
    String? comingFrom,
    String? dateOfArrival,
    String? dateRequested,
    String? dateLeaving,
    String? truckNumber,
  }) async {
    final isIncoming = type == LogType.incoming.label;
    final isDepotDispatch =
        !isIncoming && section == InventorySection.depot;

    final updatedInventory = _inventory.map((invItem) {
      final matches = items.where((i) => i.id == invItem.id).toList();
      if (matches.isEmpty) return invItem;
      final total = matches.fold<int>(0, (sum, i) => sum + i.quantityChange);

      var newQty = invItem.quantity;
      var newBiIssued = invItem.biIssued;
      if (isIncoming) newQty += total;
      if (isDepotDispatch) {
        newBiIssued += total;
      } else if (!isIncoming) {
        newQty -= total;
      }
      newQty = newQty < 0 ? 0 : newQty;
      return invItem.copyWith(quantity: newQty, biIssued: newBiIssued);
    }).toList();

    // Factory-scoped actions also adjust the factory's own stock.
    if (factoryName != null && factoryName.isNotEmpty) {
      _factories = _factories.map((f) {
        if (f.name != factoryName) return f;
        final materials = f.materials.map((m) {
          final matches = items.where((i) => i.id == m.id).toList();
          if (matches.isEmpty) return m;
          final delta = matches.fold<int>(0, (sum, i) => sum + i.quantityChange);
          var newTotal = m.total;
          if (isIncoming) newTotal += delta;
          if (!isIncoming) newTotal -= delta;
          newTotal = newTotal < 0 ? 0 : newTotal;
          return m.copyWith(total: newTotal);
        }).toList();
        return f.copyWith(materials: materials);
      }).toList();
    }

    final log = TransactionLog(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      timestamp: DateTime.now(),
      type: LogType.fromLabel(type),
      user: user,
      items: items.map((i) => i.copyWith()).toList(),
      notes: notes,
      photo: photo != null ? '[PROOF_ATTACHED.jpg]' : null,
      photoData: photoData,
      section: section,
      factoryName: factoryName,
      person: person,
      comingFrom: comingFrom,
      dateOfArrival: dateOfArrival,
      dateRequested: dateRequested,
      dateLeaving: dateLeaving,
      truckNumber: truckNumber,
    );

    _inventory = updatedInventory;
    _logs = [log, ..._logs];
    await _service.saveInventory(updatedInventory);
    if (factoryName != null && factoryName.isNotEmpty) {
      await _service.saveFactories(_factories);
    }
    await _service.saveLogs(_logs);
    notifyListeners();
  }

  /// Matches `editTransaction` from utils/inventory.js (superadmin-only).
  Future<void> editTransaction({
    required String logId,
    required List<CartItem> updatedItems,
    required String user,
  }) async {
    final target = _findLog(logId);
    if (target == null) return;

    // Reverse the old quantities, then apply the new ones.
    final updatedInventory = _inventory.map((invItem) {
      final oldItem = _firstBy(items: target.items, id: invItem.id);
      final newItem = _firstBy(items: updatedItems, id: invItem.id);
      if (oldItem == null && newItem == null) return invItem;

      var currentQty = invItem.quantity;
      var currentBi = invItem.biIssued;
      void apply(CartItem? item, int sign) {
        if (item == null) return;
        if (target.type == LogType.incoming) {
          currentQty += sign * item.quantityChange;
        } else if (target.section == InventorySection.depot) {
          // Depot dispatch affects BI Issued, not stock on hand.
          currentBi += sign * item.quantityChange;
        } else {
          currentQty -= sign * item.quantityChange;
        }
      }

      apply(oldItem, -1);
      apply(newItem, 1);
      currentQty = currentQty < 0 ? 0 : currentQty;
      return invItem.copyWith(quantity: currentQty, biIssued: currentBi);
    }).toList();

    final editLog = TransactionLog(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      timestamp: DateTime.now(),
      type: LogType.edit,
      user: user,
      refLogId: logId,
      oldItems: target.items.map((i) => i.copyWith()).toList(),
      items: updatedItems.map((i) => i.copyWith()).toList(),
      notes: 'Edited transaction $logId',
      section: target.section,
      factoryName: target.factoryName,
    );

    // Reverse the original factory effect, then apply the new one.
    if (target.factoryName != null && target.factoryName!.isNotEmpty) {
      _factories = _factories.map((f) {
        if (f.name != target.factoryName) return f;
        final materials = f.materials.map((m) {
          final oldItem = _firstBy(items: target.items, id: m.id);
          final newItem = _firstBy(items: updatedItems, id: m.id);
          if (oldItem == null && newItem == null) return m;
          var currentTotal = m.total;
          if (oldItem != null) {
            if (target.type == LogType.incoming) {
              currentTotal -= oldItem.quantityChange;
            }
            if (target.type == LogType.dispatch) {
              currentTotal += oldItem.quantityChange;
            }
          }
          if (newItem != null) {
            if (target.type == LogType.incoming) {
              currentTotal += newItem.quantityChange;
            }
            if (target.type == LogType.dispatch) {
              currentTotal -= newItem.quantityChange;
            }
          }
          currentTotal = currentTotal < 0 ? 0 : currentTotal;
          return m.copyWith(total: currentTotal);
        }).toList();
        return f.copyWith(materials: materials);
      }).toList();
    }

    _inventory = updatedInventory;
    _logs = [editLog, ..._logs];
    await _service.saveInventory(updatedInventory);
    if (target.factoryName != null && target.factoryName!.isNotEmpty) {
      await _service.saveFactories(_factories);
    }
    await _service.saveLogs(_logs);
    notifyListeners();
  }

  /// Records a search hit for the given material ids. Counts are kept per
  /// material and persisted with the rest of the inventory. The most recent
  /// search timestamp is also stored so "Recent Searched" can order by recency.
  void registerSearch(List<String> ids) {
    if (ids.isEmpty) return;
    var changed = false;
    final now = DateTime.now();
    _inventory = _inventory.map((item) {
      if (!ids.contains(item.id)) return item;
      changed = true;
      return item.copyWith(
        searchFrequency: item.searchFrequency + 1,
        lastSearchedAt: now,
      );
    }).toList();
    if (changed) {
      unawaited(_service.saveInventory(_inventory));
      notifyListeners();
    }
  }

  /// Returns false when the PL number is missing or already taken.
  Future<bool> addMaterial({
    required String id,
    required String name,
    required InventorySection section,
    required int total,
    required int biIssued,
    required int incomingQuantity,
    required DateTime? expectedAvailabilityDate,
    required PurchaseOrderStatus purchaseOrderStatus,
  }) async {
    final pl = id.trim();
    if (pl.isEmpty) return false;
    if (_inventory.any(
        (i) => i.id.trim().toLowerCase() == pl.toLowerCase())) {
      return false;
    }
    _inventory = [
      InventoryItem(
        id: pl,
        name: name.trim(),
        section: section,
        quantity: total,
        biIssued: biIssued,
        incomingQuantity: incomingQuantity,
        expectedAvailabilityDate: expectedAvailabilityDate,
        purchaseOrderStatus: purchaseOrderStatus,
        // Treating creation as a recent modification.
        lastEditedAt: DateTime.now(),
      ),
      ..._inventory,
    ];
    await _service.saveInventory(_inventory);
    notifyListeners();
    return true;
  }

  /// Returns false when the new PL number collides with another material.
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
  }) async {
    final pl = id.trim();
    if (pl.isEmpty) return false;
    if (_inventory.any((i) =>
        i.id.trim().toLowerCase() == pl.toLowerCase() &&
        i.id != originalId)) {
      return false;
    }
    var found = false;
    _inventory = _inventory.map((item) {
      if (item.id != originalId) return item;
      found = true;
      return item.copyWith(
        id: pl,
        name: name.trim(),
        section: section,
        quantity: total,
        biIssued: biIssued,
        incomingQuantity: incomingQuantity,
        expectedAvailabilityDate: expectedAvailabilityDate,
        purchaseOrderStatus: purchaseOrderStatus,
        lastEditedAt: DateTime.now(),
      );
    }).toList();
    if (!found) return false;
    await _service.saveInventory(_inventory);
    notifyListeners();
    return true;
  }

  /// Edits a material that belongs to a factory. Returns false when the
  /// material is missing or the new PL collides within the same factory.
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
  }) async {
    final pl = id.trim();
    if (pl.isEmpty) return false;

    WarehouseFactory? target;
    for (final f in _factories) {
      if (f.id == factoryId) {
        target = f;
        break;
      }
    }
    if (target == null) return false;
    final duplicate = target.materials.any((m) =>
        m.id != materialId && m.id.trim().toLowerCase() == pl.toLowerCase());
    if (duplicate) return false;

    var found = false;
    _factories = _factories.map((f) {
      if (f.id != factoryId) return f;
      final materials = f.materials.map((m) {
        if (m.id != materialId) return m;
        found = true;
        return m.copyWith(
          id: pl,
          name: name.trim(),
          total: total,
          biIssued: biIssued,
          incomingQuantity: incomingQuantity,
          expectedAvailabilityDate: expectedAvailabilityDate,
          purchaseOrderStatus: purchaseOrderStatus,
        );
      }).toList();
      return f.copyWith(materials: materials);
    }).toList();
    if (!found) return false;
    await _service.saveFactories(_factories);
    notifyListeners();
    return true;
  }

  /// Adds a new warehouse factory. Returns false when the name is blank.
  /// Material entries are normalized: PL ids fall back to a generated one
  /// when left empty.
  Future<bool> addFactory({
    required String name,
    required String location,
    required List<FactoryMaterial> materials,
  }) async {
    final factoryName = name.trim();
    if (factoryName.isEmpty) return false;

    final normalized = <FactoryMaterial>[];
    for (var i = 0; i < materials.length; i++) {
      final m = materials[i];
      final pl = m.id.trim();
      normalized.add(FactoryMaterial(
        id: pl.isEmpty ? 'PL-${i + 1}' : pl,
        name: m.name.trim(),
        total: m.total,
        biIssued: m.biIssued,
      ));
    }

    _factories = [
      WarehouseFactory(
        id: 'f-${DateTime.now().microsecondsSinceEpoch}',
        name: factoryName,
        location: location.trim(),
        materials: normalized,
      ),
      ..._factories,
    ];
    await _service.saveFactories(_factories);
    notifyListeners();
    return true;
  }

  /// Adds a material to the CURRENT factory (Sleeper). Returns false when the
  /// PL number is blank or already taken within that factory.
  Future<bool> addFactoryMaterial({
    required String factoryId,
    required String id,
    required String name,
    required int total,
    required int biIssued,
    required int incomingQuantity,
    required DateTime? expectedAvailabilityDate,
    required PurchaseOrderStatus purchaseOrderStatus,
  }) async {
    final pl = id.trim();
    if (pl.isEmpty) return false;

    WarehouseFactory? target;
    for (final f in _factories) {
      if (f.id == factoryId) {
        target = f;
        break;
      }
    }
    if (target == null) return false;
    final duplicate = target.materials
        .any((m) => m.id.trim().toLowerCase() == pl.toLowerCase());
    if (duplicate) return false;

    _factories = _factories.map((f) {
      if (f.id != factoryId) return f;
      final material = FactoryMaterial(
        id: pl,
        name: name.trim(),
        total: total,
        biIssued: biIssued,
        incomingQuantity: incomingQuantity,
        expectedAvailabilityDate: expectedAvailabilityDate,
        purchaseOrderStatus: purchaseOrderStatus,
      );
      return f.copyWith(materials: [material, ...f.materials]);
    }).toList();
    await _service.saveFactories(_factories);
    notifyListeners();
    return true;
  }

  /// Accepts a Viewer request: marks it Accepted, raises BI Issued by the
  /// requested quantity (Total unchanged), recalculates available and records
  /// the decision in the audit trail. Refuses when stock is insufficient so
  /// no inventory mutation happens. [role] ('admin' or 'superadmin') is
  /// recorded as the decision actor so the UI can distinguish who decided.
  Future<RequestDecision> acceptRequest({
    required String requestId,
    required String user,
    required String role,
  }) async {
    final service = RequestService();
    final requests = await service.loadRequests();
    final index = requests.indexWhere((r) => r.id == requestId);
    if (index == -1) return RequestDecision.alreadyProcessed;
    final request = requests[index];
    if (!request.isPending) return RequestDecision.alreadyProcessed;

    final itemIndex =
        _inventory.indexWhere((i) => i.id == request.itemId);
    if (itemIndex == -1) return RequestDecision.insufficientStock;
    final item = _inventory[itemIndex];
    if (item.available < request.quantity) {
      return RequestDecision.insufficientStock;
    }

    final now = DateTime.now();
    _inventory = _inventory.toList();
    _inventory[itemIndex] =
        item.copyWith(biIssued: item.biIssued + request.quantity);

    final log = TransactionLog(
      id: now.microsecondsSinceEpoch.toString(),
      timestamp: now,
      type: LogType.requestAccepted,
      user: user,
      items: [
        CartItem(
          id: request.itemId,
          name: request.itemName,
          quantityChange: request.quantity,
        ),
      ],
      notes:
          'Viewer Request ${request.id} — Accepted by ${decisionActorLabel(role)}. Viewer: ${request.viewerName} (${request.viewerId})',
      section: InventorySection.depot,
    );
    _logs = [log, ..._logs];

    requests[index] = request.copyWith(
      status: 'Accepted',
      decisionBy: role,
      decisionAt: now,
      history: [
        ...request.history,
        RequestHistoryEntry(status: 'Accepted', actor: role, at: now),
      ],
    );
    await service.saveRequests(requests);
    await _service.saveInventory(_inventory);
    await _service.saveLogs(_logs);
    notifyListeners();
    return RequestDecision.accepted;
  }

  /// Rejects a Viewer request. No inventory change is made; the decision is
  /// persisted and recorded in the audit trail with the acting role.
  Future<RequestDecision> rejectRequest({
    required String requestId,
    required String user,
    required String role,
  }) async {
    final service = RequestService();
    final requests = await service.loadRequests();
    final index = requests.indexWhere((r) => r.id == requestId);
    if (index == -1) return RequestDecision.alreadyProcessed;
    final request = requests[index];
    if (!request.isPending) return RequestDecision.alreadyProcessed;

    final now = DateTime.now();
    final log = TransactionLog(
      id: now.microsecondsSinceEpoch.toString(),
      timestamp: now,
      type: LogType.requestRejected,
      user: user,
      items: [
        CartItem(
          id: request.itemId,
          name: request.itemName,
          quantityChange: request.quantity,
        ),
      ],
      notes:
          'Viewer Request ${request.id} — Rejected by ${decisionActorLabel(role)}. Viewer: ${request.viewerName} (${request.viewerId})',
      section: InventorySection.depot,
    );
    _logs = [log, ..._logs];

    requests[index] = request.copyWith(
      status: 'Rejected',
      decisionBy: role,
      decisionAt: now,
      history: [
        ...request.history,
        RequestHistoryEntry(status: 'Rejected', actor: role, at: now),
      ],
    );
    await service.saveRequests(requests);
    await _service.saveLogs(_logs);
    notifyListeners();
    return RequestDecision.rejected;
  }

  /// Superadmin-only: returns a processed request to Pending. If the request
  /// was Accepted, the exact inventory mutation from that acceptance is
  /// reversed (BI Issued restored, Total untouched). Rejected requests carry
  /// no inventory change. The original decision is preserved in [history].
  Future<RequestDecision> undoRequest({
    required String requestId,
    required String user,
    required String role,
  }) async {
    if (role != 'superadmin') return RequestDecision.notAuthorized;
    final service = RequestService();
    final requests = await service.loadRequests();
    final index = requests.indexWhere((r) => r.id == requestId);
    if (index == -1) return RequestDecision.alreadyProcessed;
    final request = requests[index];
    if (request.isPending) return RequestDecision.alreadyProcessed;

    final now = DateTime.now();

    // Reverse only the inventory mutation caused by the original acceptance.
    if (request.status == 'Accepted') {
      final itemIndex =
          _inventory.indexWhere((i) => i.id == request.itemId);
      if (itemIndex != -1) {
        final item = _inventory[itemIndex];
        final restored = item.biIssued - request.quantity;
        _inventory = _inventory.toList();
        _inventory[itemIndex] = item.copyWith(
          biIssued: restored < 0 ? 0 : restored,
        );
      }
    }

    final log = TransactionLog(
      id: now.microsecondsSinceEpoch.toString(),
      timestamp: now,
      type: LogType.requestUndone,
      user: user,
      items: [
        CartItem(
          id: request.itemId,
          name: request.itemName,
          quantityChange: request.quantity,
        ),
      ],
      notes:
          'Viewer Request ${request.id} — Undone by ${decisionActorLabel(role)}. Previous decision: ${request.decisionLabel}',
      section: InventorySection.depot,
    );
    _logs = [log, ..._logs];

    requests[index] = request.copyWith(
      status: 'Pending',
      decisionBy: null,
      clearDecisionBy: true,
      decisionAt: null,
      clearDecisionAt: true,
      history: [
        ...request.history,
        RequestHistoryEntry(status: 'Undone', actor: role, at: now),
      ],
    );
    await service.saveRequests(requests);
    if (request.status == 'Accepted') {
      await _service.saveInventory(_inventory);
    }
    await _service.saveLogs(_logs);
    notifyListeners();
    return RequestDecision.undone;
  }

  TransactionLog? _findLog(String id) {
    for (final log in _logs) {
      if (log.id == id) return log;
    }
    return null;
  }

  CartItem? _firstBy({required List<CartItem> items, required String id}) {
    for (final item in items) {
      if (item.id == id) return item;
    }
    return null;
  }
}
