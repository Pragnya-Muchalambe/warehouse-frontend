import 'dart:typed_data';

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

  Future<int> unseenDecisionCount(String viewerId, String section) async => 0;

  Future<void> markDecisionsSeen(String viewerId, String section,
      Iterable<ViewerRequest> requests) async {}

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
