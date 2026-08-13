import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class AuthSession {
  final String username;
  final String role;
  final String name;
  final String id;

  const AuthSession({
    required this.username,
    required this.role,
    required this.name,
    required this.id,
  });

  Map<String, dynamic> toJson() =>
      {'username': username, 'role': role, 'name': name, 'id': id};

  factory AuthSession.fromJson(Map<String, dynamic> json) {
    return AuthSession(
      username: json['username'] as String,
      role: json['role'] as String,
      // Older stored sessions predate the profile fields; fall back safely.
      name: json['name'] as String? ?? '',
      id: json['id'] as String? ?? '',
    );
  }
}

/// A user account created from a Superadmin-approved account request. Login
/// uses the lowercased requested ID as the username, mirroring how the
/// built-in mock users are keyed.
class CustomAccount {
  final String username;
  final String name;
  final String id;
  final String password;
  final String role;
  final DateTime createdAt;

  const CustomAccount({
    required this.username,
    required this.name,
    required this.id,
    required this.password,
    required this.role,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
        'username': username,
        'name': name,
        'id': id,
        'password': password,
        'role': role,
        'createdAt': createdAt.toIso8601String(),
      };

  factory CustomAccount.fromJson(Map<String, dynamic> json) {
    return CustomAccount(
      username: json['username'] as String? ?? '',
      name: json['name'] as String? ?? '',
      id: json['id'] as String? ?? '',
      password: json['password'] as String? ?? '',
      role: json['role'] as String? ?? 'viewer',
      createdAt:
          DateTime.tryParse(json['createdAt'] as String? ?? '') ??
              DateTime.now(),
    );
  }
}

class AuthService {
  static const _sessionKey = 'poc_session';

  /// Persisted accounts created from Superadmin-approved account requests.
  static const _accountsKey = 'poc_accounts';

  // Mirrors the mock users table from the React POC (utils/auth.js).
  static const Map<String, String> _passwords = {
    'superadmin': 'password',
    'admin': 'password',
    'viewer': 'password',
  };

  static const Map<String, String> _roles = {
    'superadmin': 'superadmin',
    'admin': 'admin',
    'viewer': 'viewer',
  };

  // Mock user profile info shown in the Viewer drawer. Mirrors the profile
  // block of the React POC users table (utils/auth.js).
  static const Map<String, String> _displayNames = {
    'superadmin': 'Super Admin',
    'admin': 'Admin User',
    'viewer': 'Viewer User',
  };

  static const Map<String, String> _userIds = {
    'superadmin': 'SA-1001',
    'admin': 'AD-1002',
    'viewer': 'VW-1003',
  };

  Future<AuthSession?> login(String username, String password) async {
    final normalized = username.toLowerCase().trim();
    AuthSession? session;
    if (_passwords[normalized] == password) {
      session = AuthSession(
        username: normalized,
        role: _roles[normalized]!,
        name: _displayNames[normalized] ?? normalized,
        id: _userIds[normalized] ?? 'USER-${normalized.toUpperCase()}',
      );
    } else {
      // Accounts created from Superadmin-approved account requests.
      for (final account in await loadAccounts()) {
        if (account.username == normalized && account.password == password) {
          session = AuthSession(
            username: account.username,
            role: account.role,
            name: account.name,
            id: account.id,
          );
          break;
        }
      }
    }
    if (session == null) return null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_sessionKey, jsonEncode(session.toJson()));
    return session;
  }

  Future<List<CustomAccount>> loadAccounts() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_accountsKey);
    if (stored == null) return [];
    try {
      final decoded = jsonDecode(stored) as List<dynamic>;
      return decoded
          .map((e) => CustomAccount.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> _saveAccounts(List<CustomAccount> accounts) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _accountsKey,
      jsonEncode(accounts.map((a) => a.toJson()).toList()),
    );
  }

  /// Creates a usable login account from an approved request. Returns false
  /// when the ID already belongs to an active account (built-in or approved).
  Future<bool> createAccount({
    required String name,
    required String id,
    required String password,
    required String role,
  }) async {
    final username = id.toLowerCase().trim();
    final accounts = await loadAccounts();
    if (accounts.any((a) => a.username == username)) return false;
    if (_passwords.containsKey(username)) return false;
    accounts.add(CustomAccount(
      username: username,
      name: name.trim(),
      id: id.toUpperCase(),
      password: password,
      role: role,
      createdAt: DateTime.now(),
    ));
    await _saveAccounts(accounts);
    return true;
  }

  /// True when the requested ID collides with any active account (built-in
  /// login names, built-in display IDs, or previously approved accounts).
  Future<bool> isAccountIdTaken(String id) async {
    final username = id.toLowerCase().trim();
    final display = id.toUpperCase().trim();
    if (_passwords.containsKey(username)) return true;
    if (_userIds.values.any((v) => v.toUpperCase() == display)) return true;
    final accounts = await loadAccounts();
    return accounts.any(
      (a) => a.username == username || a.id.toUpperCase() == display,
    );
  }

  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_sessionKey);
  }

  Future<AuthSession?> getSession() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_sessionKey);
    if (raw == null) return null;
    try {
      return AuthSession.fromJson(
        jsonDecode(raw) as Map<String, dynamic>,
      );
    } catch (_) {
      return null;
    }
  }
}
