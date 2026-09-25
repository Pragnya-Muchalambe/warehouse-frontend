/// A registration request submitted through the NEW USER flow. Superadmin
/// decides on it from the PERMISSION section. The API never returns passwords.
class AccountRequest {
  final String id;
  final String name;
  final String requestedId;
  final String role;
  final DateTime submittedAt;
  final String status;
  final String? decisionBy;
  final DateTime? decisionAt;
  final int version;

  const AccountRequest({
    required this.id,
    required this.name,
    required this.requestedId,
    required this.role,
    required this.submittedAt,
    this.status = 'Pending',
    this.decisionBy,
    this.decisionAt,
    this.version = 1,
  });

  bool get isPending => status == 'Pending';

  String get statusLabel {
    if (isPending) return 'Pending';
    return status;
  }

  AccountRequest copyWith({
    String? status,
    String? decisionBy,
    DateTime? decisionAt,
    int? version,
  }) {
    return AccountRequest(
      id: id,
      name: name,
      requestedId: requestedId,
      role: role,
      submittedAt: submittedAt,
      status: status ?? this.status,
      decisionBy: decisionBy ?? this.decisionBy,
      decisionAt: decisionAt ?? this.decisionAt,
      version: version ?? this.version,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'requestedId': requestedId,
        'role': role,
        'submittedAt': submittedAt.toIso8601String(),
        'status': status,
        if (decisionBy != null) 'decisionBy': decisionBy,
        if (decisionAt != null) 'decisionAt': decisionAt!.toIso8601String(),
        'version': version,
      };

  factory AccountRequest.fromJson(Map<String, dynamic> json) {
    return AccountRequest(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      requestedId: json['requestedId'] as String? ?? '',
      role: json['role'] as String? ?? 'viewer',
      submittedAt: DateTime.tryParse(json['submittedAt'] as String? ?? '') ??
          DateTime.now(),
      status: _uiAccountStatus(json['status'] as String?),
      decisionBy: json['decisionBy'] as String?,
      decisionAt: DateTime.tryParse(json['decisionAt'] as String? ?? ''),
      version: (json['version'] as num?)?.toInt() ?? 1,
    );
  }
}

String _uiAccountStatus(String? status) => switch (status?.toUpperCase()) {
      'PENDING' => 'Pending',
      'ACCEPTED' => 'Accepted',
      'REJECTED' => 'Rejected',
      _ => status ?? 'Pending',
    };
