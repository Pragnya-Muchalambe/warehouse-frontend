import 'dart:typed_data';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/viewer_request.dart';
import 'api_client.dart';

class RequestBatchException implements Exception {
  final List<String> succeededItemIds;
  final Map<String, String> failedItems;

  const RequestBatchException({
    required this.succeededItemIds,
    required this.failedItems,
  });
}

class RequestService {
  RequestService({ApiClient? api}) : _api = api ?? ApiClient.instance;

  final ApiClient _api;

  Future<Uint8List> downloadFile(String fileId) => _api.downloadFile(fileId);

  Future<List<ViewerRequest>> loadRequests() async {
    final data = await _api.getAll('/requests');
    return data
        .map((request) =>
            ViewerRequest.fromJson(request as Map<String, dynamic>))
        .toList();
  }

  Future<int> unseenDecisionCount(
    String viewerId,
    String section, {
    String? storageViewerId,
    Iterable<ViewerRequest>? requests,
  }) async {
    final values = requests ?? await loadRequests();
    final seenAt =
        await _lastSeenDecision(storageViewerId ?? viewerId, section);
    return values
        .where((request) => request.viewerId == viewerId)
        .where((request) => request.section == section)
        .map(_decisionInstant)
        .whereType<DateTime>()
        .where((instant) => seenAt == null || instant.isAfter(seenAt))
        .length;
  }

  Future<void> markDecisionsSeen(
    String viewerId,
    String section,
    Iterable<ViewerRequest> requests, {
    String? storageViewerId,
  }) async {
    DateTime? latest;
    for (final request in requests
        .where((request) => request.viewerId == viewerId)
        .where((request) => request.section == section)) {
      final instant = _decisionInstant(request);
      if (instant != null && (latest == null || instant.isAfter(latest))) {
        latest = instant;
      }
    }
    if (latest == null) return;
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(
      _seenDecisionKey(storageViewerId ?? viewerId, section),
      latest.toUtc().toIso8601String(),
    );
  }

  DateTime? _decisionInstant(ViewerRequest request) {
    if (request.status != 'Accepted' && request.status != 'Rejected') {
      return null;
    }
    return request.decisionAt ?? request.updatedAt;
  }

  Future<DateTime?> _lastSeenDecision(
      String storageViewerId, String section) async {
    final preferences = await SharedPreferences.getInstance();
    return DateTime.tryParse(
      preferences.getString(_seenDecisionKey(storageViewerId, section)) ?? '',
    );
  }

  String _seenDecisionKey(String storageViewerId, String section) {
    final identity = Uri.encodeComponent(storageViewerId.trim().toLowerCase());
    final scope = section.trim().toLowerCase();
    return 'viewer.lastSeenDecision.$identity.$scope';
  }

  Future<ViewerRequest> addRequest({
    required String viewerId,
    required String viewerName,
    required String itemId,
    required String itemName,
    required int quantity,
    String? factoryId,
  }) async {
    final data = await _api.sendJson(
      'POST',
      '/requests',
      body: {
        'module': factoryId == null ? 'DEPOT' : 'SLEEPER',
        'factoryId': factoryId,
        'itemId': itemId,
        'quantity': quantity,
      },
    );
    return ViewerRequest.fromJson(data as Map<String, dynamic>);
  }

  Future<List<ViewerRequest>> addBatch({
    required String viewerId,
    required String viewerName,
    required List<({String itemId, String itemName, int quantity})> items,
    String? factoryId,
    String? factoryName,
  }) async {
    final created = <ViewerRequest>[];
    final failed = <String, String>{};
    for (final item in items) {
      try {
        created.add(await addRequest(
          viewerId: viewerId,
          viewerName: viewerName,
          itemId: item.itemId,
          itemName: item.itemName,
          quantity: item.quantity,
          factoryId: factoryId,
        ));
      } on ApiException catch (error) {
        failed[item.itemId] = error.message;
      } catch (_) {
        failed[item.itemId] = 'Request could not be sent.';
      }
    }
    if (failed.isNotEmpty) {
      throw RequestBatchException(
        succeededItemIds: created.map((request) => request.itemId).toList(),
        failedItems: failed,
      );
    }
    return created;
  }

  Future<ViewerRequest> decide(
    String id,
    String action,
    int version, {
    String? reason,
  }) async {
    final data = await _api.sendJson(
      'POST',
      '/requests/${Uri.encodeComponent(id)}/$action',
      version: version,
      body: {
        if (reason != null && reason.trim().isNotEmpty) 'reason': reason.trim(),
      },
    );
    return ViewerRequest.fromJson(data as Map<String, dynamic>);
  }
}
