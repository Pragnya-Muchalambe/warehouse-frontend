import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/inventory_item.dart';
import '../models/viewer_request.dart';

/// Persists Viewer material requests using the same SharedPreferences
/// architecture as the rest of the POC (inventory/logs/factories). Existing
/// keys are never touched, so this storage layer is fully additive.
class RequestService {
  static const requestsKey = 'viewer_requests';

  Future<List<ViewerRequest>> loadRequests() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(requestsKey);
    if (stored == null) return [];
    try {
      final decoded = jsonDecode(stored) as List<dynamic>;
      return decoded
          .map((e) => ViewerRequest.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      // Corrupt or unexpected payload: fall back to an empty history rather
      // than wiping the stored value.
      return [];
    }
  }

  Future<void> saveRequests(List<ViewerRequest> requests) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      requestsKey,
      jsonEncode(requests.map((r) => r.toJson()).toList()),
    );
  }

  /// Creates a Depot request and prepends it to the persisted history.
  Future<ViewerRequest> addRequest({
    required String viewerId,
    required String viewerName,
    required String itemId,
    required String itemName,
    required int quantity,
  }) async {
    final request = ViewerRequest(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      viewerId: viewerId,
      viewerName: viewerName,
      itemId: itemId,
      itemName: itemName,
      quantity: quantity,
      createdAt: DateTime.now(),
      section: InventorySection.depot.label,
      status: 'Pending',
    );
    final all = await loadRequests();
    await saveRequests([request, ...all]);
    return request;
  }

  /// Updates the status of a request (e.g. 'Accepted' / 'Rejected'). Returns
  /// the updated list, or the current list unchanged when the id is unknown.
  Future<List<ViewerRequest>> updateRequestStatus({
    required String id,
    required String status,
  }) async {
    final all = await loadRequests();
    final updated = all.map((r) {
      if (r.id != id) return r;
      return r.copyWith(status: status);
    }).toList();
    await saveRequests(updated);
    return updated;
  }
}
