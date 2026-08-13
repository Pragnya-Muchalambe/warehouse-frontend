import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/account_request.dart';

/// Persists NEW USER account-creation requests using the same
/// SharedPreferences architecture as the rest of the POC. Fully additive:
/// existing keys are never touched.
class AccountRequestService {
  static const accountRequestsKey = 'account_requests';

  Future<List<AccountRequest>> loadRequests() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(accountRequestsKey);
    if (stored == null) return [];
    try {
      final decoded = jsonDecode(stored) as List<dynamic>;
      return decoded
          .map((e) => AccountRequest.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> saveRequests(List<AccountRequest> requests) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      accountRequestsKey,
      jsonEncode(requests.map((r) => r.toJson()).toList()),
    );
  }

  /// Creates a new Pending account request and prepends it to the persisted
  /// list. Returns the created request.
  Future<AccountRequest> addRequest({
    required String name,
    required String id,
    required String password,
    required String role,
  }) async {
    final request = AccountRequest(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      name: name,
      requestedId: id.toUpperCase(),
      password: password,
      role: role,
      submittedAt: DateTime.now(),
      status: 'Pending',
    );
    final all = await loadRequests();
    await saveRequests([request, ...all]);
    return request;
  }
}
