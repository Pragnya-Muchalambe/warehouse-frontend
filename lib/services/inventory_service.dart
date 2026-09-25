import 'dart:typed_data';

import '../models/audit_log.dart';
import '../models/factory.dart';
import '../models/inventory_item.dart';
import '../models/transaction_log.dart';
import 'api_client.dart';

class InventoryService {
  InventoryService({ApiClient? api}) : _api = api ?? ApiClient.instance;

  final ApiClient _api;

  bool get supportsFactoryDeletion => false;

  Future<Uint8List> downloadFile(String fileId) => _api.downloadFile(fileId);

  Future<List<InventoryItem>> loadInventory() async {
    final data = await _api.getAll('/inventory');
    return data
        .map((item) => InventoryItem.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<List<TransactionLog>> loadLogs() async {
    final data =
        await _api.getAll('/transactions', query: {'sort': '-createdAt'});
    return data
        .map((item) => TransactionLog.fromApi(item as Map<String, dynamic>))
        .toList();
  }

  Future<List<AuditLog>> loadAuditLogs() async {
    final data = await _api.getAll('/logs', query: {'sort': '-occurredAt'});
    return data
        .map((item) => AuditLog.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<TransactionLog> getTransaction(String id) async {
    final data = await _api.get('/transactions/${Uri.encodeComponent(id)}');
    return TransactionLog.fromApi(data as Map<String, dynamic>);
  }

  Future<List<WarehouseFactory>> loadFactories() async {
    final data = await _api.getAll('/factories');
    final factories = <WarehouseFactory>[];
    for (final raw in data.cast<Map<String, dynamic>>()) {
      final factory = WarehouseFactory.fromJson(raw);
      factories.add(
        factory.copyWith(materials: await loadFactoryMaterials(factory.id)),
      );
    }
    return factories;
  }

  Future<List<FactoryMaterial>> loadFactoryMaterials(String factoryId) async {
    final data = await _api.getAll(
      '/factories/${Uri.encodeComponent(factoryId)}/materials',
    );
    return data
        .map((item) => FactoryMaterial.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<InventoryItem> createMaterial(Map<String, dynamic> body) async {
    final data = await _api.sendJson('POST', '/inventory', body: body);
    return InventoryItem.fromJson(data as Map<String, dynamic>);
  }

  Future<InventoryItem> updateMaterial(
    String id,
    int version,
    Map<String, dynamic> body,
  ) async {
    final data = await _api.sendJson(
      'PATCH',
      '/inventory/${Uri.encodeComponent(id)}',
      body: body,
      version: version,
    );
    return InventoryItem.fromJson(data as Map<String, dynamic>);
  }

  Future<WarehouseFactory> createFactory(String name, String location) async {
    final data = await _api.sendJson(
      'POST',
      '/factories',
      body: {'name': name, 'location': location},
    );
    return WarehouseFactory.fromJson(data as Map<String, dynamic>);
  }

  Future<void> deleteFactory(String id, int version) async {
    await _api.sendJson(
      'DELETE',
      '/factories/${Uri.encodeComponent(id)}',
      version: version,
    );
  }

  Future<FactoryMaterial> createFactoryMaterial(
    String factoryId,
    Map<String, dynamic> body,
  ) async {
    final data = await _api.sendJson(
      'POST',
      '/factories/${Uri.encodeComponent(factoryId)}/materials',
      body: body,
    );
    return FactoryMaterial.fromJson(data as Map<String, dynamic>);
  }

  Future<FactoryMaterial> updateFactoryMaterial(
    String factoryId,
    String materialId,
    int version,
    Map<String, dynamic> body,
  ) async {
    final data = await _api.sendJson(
      'PATCH',
      '/factories/${Uri.encodeComponent(factoryId)}/materials/'
          '${Uri.encodeComponent(materialId)}',
      body: body,
      version: version,
    );
    return FactoryMaterial.fromJson(data as Map<String, dynamic>);
  }

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
    String? notes,
    required String person,
    String? comingFrom,
    String? dateOfArrival,
    String? dateRequested,
    String? dateLeaving,
    required String truckNumber,
    List<String> sourceRequestIds = const [],
  }) async {
    if (sourceRequestIds.length > 100 ||
        sourceRequestIds.length != sourceRequestIds.toSet().length) {
      throw const ApiException(
        'Source requests must contain at most 100 unique IDs.',
        0,
      );
    }
    if (proofs.length + (proofBytes == null ? 0 : 1) > 10) {
      throw const ApiException('Transactions support at most 10 proofs.', 0);
    }
    _validateCreateTransaction(
      type: type,
      scope: scope,
      factoryId: factoryId,
      items: items,
      notes: notes,
      person: person,
      comingFrom: comingFrom,
      dateOfArrival: dateOfArrival,
      dateRequested: dateRequested,
      dateLeaving: dateLeaving,
      truckNumber: truckNumber,
    );
    final billFileId = await _api.uploadFile(
      purpose: 'BILL',
      fileName: billName,
      bytes: billBytes,
    );
    final proofFileId = proofBytes == null || proofName == null
        ? null
        : await _api.uploadFile(
            purpose: 'PROOF',
            fileName: proofName,
            bytes: proofBytes,
          );
    final proofFileIds = await _resolveProofFileIds([
      if (proofFileId != null) proofFileId,
      ...proofs,
    ]);
    if (proofFileIds.contains(billFileId)) {
      throw const ApiException('Bill and proof must be separate files.', 0);
    }
    final body = <String, dynamic>{
      'type': type,
      'scope': scope,
      if (scope == 'FACTORY') 'factoryId': factoryId,
      'items': items
          .map(
            (item) => {
              'materialId': item.id,
              'quantityChange': item.quantityChange,
            },
          )
          .toList(),
      if (notes != null && notes.trim().isNotEmpty) 'notes': notes.trim(),
      'person': person.trim(),
      'truckNumber': truckNumber.trim().toUpperCase(),
      'billFileId': billFileId,
      'proofFileIds': proofFileIds,
      if (sourceRequestIds.isNotEmpty) 'sourceRequestIds': sourceRequestIds,
      if (type == 'INCOMING') ...{
        'comingFrom': comingFrom!.trim(),
        'dateOfArrival': dateOfArrival,
      } else ...{
        'dateRequested': dateRequested,
        'dateLeaving': dateLeaving,
      },
    };
    final data = await _api.sendJson('POST', '/transactions', body: body);
    return TransactionLog.fromApi(data as Map<String, dynamic>);
  }

  Future<TransactionLog> correctTransaction(
    TransactionLog transaction,
    List<CartItem> items,
    String? reason, {
    List<TransactionAttachment>? proofs,
  }) async {
    _validateTransactionItems(items);
    final billFileId = transaction.billFileId;
    if (billFileId == null || billFileId.trim().isEmpty) {
      throw const ApiException(
          'A bill is required to correct a transaction.', 0);
    }
    if (reason != null && reason.trim().length > 500) {
      throw const ApiException(
        'Reasons must be 500 characters or less.',
        0,
      );
    }
    final body = <String, dynamic>{
      'items': items
          .map(
            (item) => {
              'materialId': item.id,
              'quantityChange': item.quantityChange,
            },
          )
          .toList(),
      if (transaction.notes != null) 'notes': transaction.notes,
      'person': transaction.person,
      'truckNumber': transaction.truckNumber,
      'billFileId': billFileId,
      if (proofs != null) 'proofFileIds': await _resolveProofFileIds(proofs),
      if (transaction.type == LogType.incoming) ...{
        'comingFrom': transaction.comingFrom,
        'dateOfArrival': transaction.dateOfArrival,
      } else ...{
        'dateRequested': transaction.dateRequested,
        'dateLeaving': transaction.dateLeaving,
      },
      if (reason != null && reason.trim().isNotEmpty) 'reason': reason.trim(),
    };
    final data = await _api.sendJson(
      'PATCH',
      '/transactions/${Uri.encodeComponent(transaction.id)}',
      body: body,
      version: transaction.version,
    );
    return TransactionLog.fromApi(data as Map<String, dynamic>);
  }

  Future<List<String>> _resolveProofFileIds(
    List<Object> proofs,
  ) async {
    if (proofs.length > 10) {
      throw const ApiException('Transactions support at most 10 proofs.', 0);
    }
    final ids = <String>[];
    for (final value in proofs) {
      if (value is String && value.isNotEmpty) {
        ids.add(value);
        continue;
      }
      if (value is! TransactionAttachment) {
        throw const ApiException('A selected proof is invalid.', 0);
      }
      if (value.fileId case final String fileId when fileId.isNotEmpty) {
        ids.add(fileId);
        continue;
      }
      final bytes = value.bytes;
      if (bytes == null || bytes.isEmpty) {
        throw const ApiException(
          'Every selected proof must contain a file.',
          0,
        );
      }
      ids.add(await _api.uploadFile(
        purpose: 'PROOF',
        fileName: value.fileName,
        bytes: bytes,
      ));
    }
    if (ids.length != ids.toSet().length) {
      throw const ApiException('Proof files must be unique.', 0);
    }
    return ids;
  }

  Future<List<SearchHitUpdate>> registerSearch(List<String> ids) async {
    final data = await _api.sendJson(
      'POST',
      '/inventory/search-hits',
      body: {
        'materialIds': ids.toSet().toList(),
        'searchedAt': DateTime.now().toUtc().toIso8601String(),
      },
    );
    final updated = (data as Map<String, dynamic>)['updated'] as List? ?? [];
    return updated
        .map((raw) => SearchHitUpdate.fromJson(raw as Map<String, dynamic>))
        .toList();
  }

  void _validateTransactionItems(List<CartItem> items) {
    if (items.isEmpty || items.length > 100) {
      throw const ApiException(
        'Transactions require between 1 and 100 items.',
        0,
      );
    }
    if (items.any((item) =>
        item.quantityChange < 1 || item.quantityChange > 2147483647)) {
      throw const ApiException(
        'Transaction quantities must be between 1 and 2147483647.',
        0,
      );
    }
    if (items.map((item) => item.id).toSet().length != items.length) {
      throw const ApiException('Transaction material IDs must be unique.', 0);
    }
  }

  void _validateCreateTransaction({
    required String type,
    required String scope,
    required String? factoryId,
    required List<CartItem> items,
    required String? notes,
    required String person,
    required String? comingFrom,
    required String? dateOfArrival,
    required String? dateRequested,
    required String? dateLeaving,
    required String truckNumber,
  }) {
    _validateTransactionItems(items);
    if (type != 'INCOMING' && type != 'DISPATCH') {
      throw const ApiException('Transaction type is invalid.', 0);
    }
    if (scope != 'DEPOT' && scope != 'FACTORY') {
      throw const ApiException('Transaction scope is invalid.', 0);
    }
    if (scope == 'FACTORY' && (factoryId == null || factoryId.trim().isEmpty)) {
      throw const ApiException('A factory is required.', 0);
    }
    if (scope == 'DEPOT' && factoryId != null) {
      throw const ApiException(
          'Depot transactions cannot include a factory.', 0);
    }
    _validateRequiredText(person, 'Person', 200);
    _validateRequiredText(truckNumber, 'Truck number', 32);
    if (!RegExp(r'^[A-Za-z0-9 -]+$').hasMatch(truckNumber.trim())) {
      throw const ApiException(
        'Truck number may contain only letters, numbers, spaces, and hyphens.',
        0,
      );
    }
    if (notes != null && notes.trim().length > 2000) {
      throw const ApiException('Notes must be 2000 characters or less.', 0);
    }
    if (type == 'INCOMING') {
      _validateRequiredText(comingFrom, 'Coming from', 200);
      _parseDateOnly(dateOfArrival, 'Date of arrival');
      if (dateRequested != null || dateLeaving != null) {
        throw const ApiException(
          'Incoming transactions cannot include dispatch dates.',
          0,
        );
      }
    } else {
      final requested = _parseDateOnly(dateRequested, 'Date requested');
      final leaving = _parseDateOnly(dateLeaving, 'Date leaving');
      if (leaving.isBefore(requested)) {
        throw const ApiException(
          'Date leaving cannot be before date requested.',
          0,
        );
      }
      if (comingFrom != null || dateOfArrival != null) {
        throw const ApiException(
          'Dispatch transactions cannot include incoming fields.',
          0,
        );
      }
    }
  }

  void _validateRequiredText(String? value, String label, int maxLength) {
    final text = value?.trim() ?? '';
    if (text.isEmpty || text.length > maxLength) {
      throw ApiException(
          '$label must be between 1 and $maxLength characters.', 0);
    }
  }

  DateTime _parseDateOnly(String? value, String label) {
    final text = value ?? '';
    if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(text)) {
      throw ApiException('$label must use YYYY-MM-DD.', 0);
    }
    final parsed = DateTime.tryParse(text);
    if (parsed == null ||
        '${parsed.year.toString().padLeft(4, '0')}-'
                '${parsed.month.toString().padLeft(2, '0')}-'
                '${parsed.day.toString().padLeft(2, '0')}' !=
            text) {
      throw ApiException('$label is invalid.', 0);
    }
    return parsed;
  }
}

class SearchHitUpdate {
  final String materialId;
  final int searchFrequency;
  final DateTime? lastSearchedAt;

  const SearchHitUpdate({
    required this.materialId,
    required this.searchFrequency,
    required this.lastSearchedAt,
  });

  factory SearchHitUpdate.fromJson(Map<String, dynamic> json) =>
      SearchHitUpdate(
        materialId: json['materialId'] as String,
        searchFrequency: (json['searchFrequency'] as num).toInt(),
        lastSearchedAt: DateTime.tryParse(
          json['lastSearchedAt'] as String? ?? '',
        ),
      );
}
