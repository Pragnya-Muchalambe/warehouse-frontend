import '../models/user_account.dart';
import 'api_client.dart';

class UserAccountService {
  UserAccountService({ApiClient? api}) : _api = api ?? ApiClient.instance;

  final ApiClient _api;

  Future<List<UserAccount>> loadUsers() async {
    final data = await _api.getAll('/users');
    return data
        .map((user) => UserAccount.fromJson(user as Map<String, dynamic>))
        .toList();
  }

  Future<void> deleteUser(String id, int version) async {
    await _api.sendJson(
      'DELETE',
      '/users/${Uri.encodeComponent(id)}',
      version: version,
    );
  }
}
