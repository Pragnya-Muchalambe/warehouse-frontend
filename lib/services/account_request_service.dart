import '../models/account_request.dart';
import 'api_client.dart';

class AccountRequestService {
  AccountRequestService({ApiClient? api}) : _api = api ?? ApiClient.instance;

  final ApiClient _api;

  Future<List<AccountRequest>> loadRequests() async {
    final data = await _api.getAll('/account-requests');
    return data
        .map((request) =>
            AccountRequest.fromJson(request as Map<String, dynamic>))
        .toList();
  }

  Future<AccountRequest> addRequest({
    required String name,
    required String id,
    required String password,
    required String role,
  }) async {
    final data = await _api.sendJson(
      'POST',
      '/account-requests',
      body: {
        'name': name,
        'requestedId': id,
        'password': password,
        'role': role.toUpperCase(),
      },
    );
    return AccountRequest.fromJson(data as Map<String, dynamic>);
  }

  Future<AccountRequest> decide(
    AccountRequest request,
    String action, {
    String? reason,
  }) async {
    final data = await _api.sendJson(
      'POST',
      '/account-requests/${Uri.encodeComponent(request.id)}/$action',
      version: request.version,
      body: {
        if (reason != null && reason.trim().isNotEmpty) 'reason': reason.trim(),
      },
    ) as Map<String, dynamic>;
    final resource = action == 'approve'
        ? data['accountRequest'] as Map<String, dynamic>
        : data;
    return AccountRequest.fromJson(resource);
  }
}
