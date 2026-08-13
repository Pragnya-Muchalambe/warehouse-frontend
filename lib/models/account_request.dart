import 'viewer_request.dart';

/// A registration request submitted through the NEW USER flow. Superadmin
/// decides on it from the PERMISSION section; accepted requests become real
/// login accounts via [AuthService.createAccount].
///
/// Passwords are kept on the request only to carry credentials into account
/// creation; they are never rendered in any UI or audit record.
class AccountRequest {
  final String id;
  final String name;
  final String requestedId;
  final String password;
  final String role;
  final DateTime submittedAt;
  final String status;
  final String? decisionBy;
  final DateTime? decisionAt;

  const AccountRequest({
    required this.id,
    required this.name,
    required this.requestedId,
    required this.password,
    required this.role,
    required this.submittedAt,
    this.status = 'Pending',
    this.decisionBy,
    this.decisionAt,
  });

  bool get isPending => status == 'Pending';

  String get statusLabel {
    if (isPending) return 'Pending';
    if (decisionBy == null || decisionBy!.isEmpty) return status;
    return '$status by ${decisionActorLabel(decisionBy!)}';
  }

  AccountRequest copyWith({
    String? status,
    String? decisionBy,
    DateTime? decisionAt,
  }) {
    return AccountRequest(
      id: id,
      name: name,
      requestedId: requestedId,
      password: password,
      role: role,
      submittedAt: submittedAt,
      status: status ?? this.status,
      decisionBy: decisionBy ?? this.decisionBy,
      decisionAt: decisionAt ?? this.decisionAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'requestedId': requestedId,
        'password': password,
        'role': role,
        'submittedAt': submittedAt.toIso8601String(),
        'status': status,
        if (decisionBy != null) 'decisionBy': decisionBy,
        if (decisionAt != null) 'decisionAt': decisionAt!.toIso8601String(),
      };

  factory AccountRequest.fromJson(Map<String, dynamic> json) {
    return AccountRequest(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      requestedId: json['requestedId'] as String? ?? '',
      password: json['password'] as String? ?? '',
      role: json['role'] as String? ?? 'viewer',
      submittedAt:
          DateTime.tryParse(json['submittedAt'] as String? ?? '') ??
              DateTime.now(),
      status: json['status'] as String? ?? 'Pending',
      decisionBy: json['decisionBy'] as String?,
      decisionAt: DateTime.tryParse(json['decisionAt'] as String? ?? ''),
    );
  }
}
