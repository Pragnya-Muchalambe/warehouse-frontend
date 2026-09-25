class AuditActor {
  final String id;
  final String accountId;
  final String name;
  final String role;

  const AuditActor({
    required this.id,
    required this.accountId,
    required this.name,
    required this.role,
  });

  factory AuditActor.fromJson(Map<String, dynamic> json) => AuditActor(
        id: json['id'] as String? ?? '',
        accountId: json['accountId'] as String? ?? '',
        name: json['name'] as String? ?? '',
        role: json['role'] as String? ?? '',
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'accountId': accountId,
        'name': name,
        'role': role,
      };
}

class AuditFileMetadata {
  final String id;
  final String purpose;
  final String fileName;
  final String? contentType;
  final int? sizeBytes;
  final String? sha256;
  final String? status;
  final Map<String, dynamic>? createdBy;
  final DateTime? createdAt;
  final bool? referenced;
  final int? version;

  const AuditFileMetadata({
    required this.id,
    required this.purpose,
    required this.fileName,
    this.contentType,
    this.sizeBytes,
    this.sha256,
    this.status,
    this.createdBy,
    this.createdAt,
    this.referenced,
    this.version,
  });

  factory AuditFileMetadata.fromJson(Map<String, dynamic> json) =>
      AuditFileMetadata(
        id: json['id'] as String? ?? '',
        purpose: json['purpose'] as String? ?? '',
        fileName: json['fileName'] as String? ?? '',
        contentType: json['contentType'] as String?,
        sizeBytes: (json['sizeBytes'] as num?)?.toInt(),
        sha256: json['sha256'] as String?,
        status: json['status'] as String?,
        createdBy: json['createdBy'] is Map<String, dynamic>
            ? json['createdBy'] as Map<String, dynamic>
            : null,
        createdAt: DateTime.tryParse(json['createdAt'] as String? ?? ''),
        referenced: json['referenced'] as bool?,
        version: (json['version'] as num?)?.toInt(),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'purpose': purpose,
        'fileName': fileName,
        if (contentType != null) 'contentType': contentType,
        if (sizeBytes != null) 'sizeBytes': sizeBytes,
        if (sha256 != null) 'sha256': sha256,
        if (status != null) 'status': status,
        if (createdBy != null) 'createdBy': createdBy,
        if (createdAt != null) 'createdAt': createdAt!.toIso8601String(),
        if (referenced != null) 'referenced': referenced,
        if (version != null) 'version': version,
      };
}

class AuditLog {
  final String id;
  final String eventType;
  final String entityType;
  final String entityId;
  final AuditActor actor;
  final DateTime occurredAt;
  final String requestId;
  final String? reason;
  final Map<String, dynamic>? before;
  final Map<String, dynamic>? after;
  final AuditFileMetadata? billFile;
  final AuditFileMetadata? proofFile;

  const AuditLog({
    required this.id,
    required this.eventType,
    required this.entityType,
    required this.entityId,
    required this.actor,
    required this.occurredAt,
    required this.requestId,
    this.reason,
    this.before,
    this.after,
    this.billFile,
    this.proofFile,
  });

  String? get scope => _snapshotValue('scope');

  Map<String, dynamic> toJson() => {
        'id': id,
        'eventType': eventType,
        'entityType': entityType,
        'entityId': entityId,
        'actor': actor.toJson(),
        'occurredAt': occurredAt.toIso8601String(),
        'requestId': requestId,
        if (reason != null) 'reason': reason,
        if (before != null) 'before': before,
        if (after != null) 'after': after,
        if (billFile != null) 'billFile': billFile!.toJson(),
        if (proofFile != null) 'proofFile': proofFile!.toJson(),
      };
  String? get factoryId => _snapshotValue('factoryId');
  String? get factoryNameSnapshot => _snapshotValue('factoryNameSnapshot');

  String? _snapshotValue(String key) {
    final value = after?[key] ?? before?[key];
    return value is String ? value : null;
  }

  factory AuditLog.fromJson(Map<String, dynamic> json) {
    final actor = json['actor'];
    final occurredAt = DateTime.tryParse(json['occurredAt'] as String? ?? '');
    if (occurredAt == null) {
      throw const FormatException('Invalid audit timestamp');
    }
    return AuditLog(
      id: json['id'] as String? ?? '',
      eventType: json['eventType'] as String? ?? '',
      entityType: json['entityType'] as String? ?? '',
      entityId: json['entityId'] as String? ?? '',
      actor: actor is Map<String, dynamic>
          ? AuditActor.fromJson(actor)
          : const AuditActor(id: '', accountId: '', name: '', role: ''),
      occurredAt: occurredAt,
      requestId: json['requestId'] as String? ?? '',
      reason: json['reason'] as String?,
      before: _jsonMap(json['before']),
      after: _jsonMap(json['after']),
      billFile: _file(json['billFile']),
      proofFile: _file(json['proofFile']),
    );
  }

  static Map<String, dynamic>? _jsonMap(Object? value) =>
      value is Map<String, dynamic> ? value : null;

  static AuditFileMetadata? _file(Object? value) =>
      value is Map<String, dynamic> ? AuditFileMetadata.fromJson(value) : null;
}
