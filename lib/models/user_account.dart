import '../services/api_client.dart';

class UserAccount {
  final String id;
  final String accountId;
  final String username;
  final String name;
  final String role;
  final String status;
  final DateTime createdAt;
  final DateTime updatedAt;
  final int version;

  const UserAccount({
    required this.id,
    required this.accountId,
    required this.username,
    required this.name,
    required this.role,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    required this.version,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'accountId': accountId,
        'username': username,
        'name': name,
        'role': role,
        'status': status,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        'version': version,
      };

  factory UserAccount.fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final accountId = json['accountId'];
    final username = json['username'];
    final name = json['name'];
    final role = json['role'];
    final status = json['status'];
    final createdAt = DateTime.tryParse(json['createdAt'] as String? ?? '');
    final updatedAt = DateTime.tryParse(json['updatedAt'] as String? ?? '');
    final version = (json['version'] as num?)?.toInt();
    if (id is! String ||
        id.isEmpty ||
        accountId is! String ||
        accountId.isEmpty ||
        username is! String ||
        username.isEmpty ||
        name is! String ||
        name.isEmpty ||
        role is! String ||
        status != 'ACTIVE' ||
        createdAt == null ||
        updatedAt == null ||
        version == null ||
        version < 1) {
      throw const ApiException(
          'The server returned an invalid user account.', 0);
    }
    return UserAccount(
      id: id,
      accountId: accountId,
      username: username,
      name: name,
      role: role.toLowerCase(),
      status: status,
      createdAt: createdAt,
      updatedAt: updatedAt,
      version: version,
    );
  }
}
