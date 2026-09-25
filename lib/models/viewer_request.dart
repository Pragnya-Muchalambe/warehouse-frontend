import 'dart:convert';

import 'transaction_log.dart';

/// Maps an internal role string ('admin' / 'superadmin' / 'viewer') to the
/// human label used in request statuses and audit notes.
String decisionActorLabel(String role) {
  switch (role) {
    case 'superadmin':
      return 'Superadmin';
    case 'admin':
      return 'Admin';
    case 'viewer':
      return 'Viewer';
    default:
      return role;
  }
}

/// A single event in a Viewer request's decision history. Kept append-only so
/// an Undo never erases the original Admin (or Superadmin) decision.
class RequestHistoryEntry {
  /// One of 'Accepted', 'Rejected', 'Undone', 'Pending'.
  final String status;
  final String actor;
  final String actorId;
  final String actorAccountId;
  final String actorName;
  final DateTime at;
  final String? reason;

  const RequestHistoryEntry({
    required this.status,
    required this.actor,
    this.actorId = '',
    this.actorAccountId = '',
    this.actorName = '',
    required this.at,
    this.reason,
  });

  String get label {
    if (status == 'Pending') return 'Pending';
    return '$status by ${decisionActorLabel(actor)}';
  }

  Map<String, dynamic> toJson() => {
        'status': status,
        'actor': {
          'id': actorId,
          'accountId': actorAccountId,
          'name': actorName,
          'role': actor.toUpperCase(),
        },
        'at': at.toIso8601String(),
        if (reason != null && reason!.trim().isNotEmpty)
          'reason': reason!.trim(),
      };

  factory RequestHistoryEntry.fromJson(Map<String, dynamic> json) {
    final actor = json['actor'];
    return RequestHistoryEntry(
      status: _uiRequestStatus(json['status'] as String?),
      actor: actor is Map<String, dynamic>
          ? (actor['role'] as String? ?? '').toLowerCase()
          : actor as String? ?? '',
      actorId:
          actor is Map<String, dynamic> ? actor['id'] as String? ?? '' : '',
      actorAccountId: actor is Map<String, dynamic>
          ? actor['accountId'] as String? ?? ''
          : '',
      actorName:
          actor is Map<String, dynamic> ? actor['name'] as String? ?? '' : '',
      at: DateTime.tryParse(json['at'] as String? ?? '') ?? DateTime.now(),
      reason: json['reason'] as String?,
    );
  }
}

/// A request made by a Viewer for depot inventory. Requests start as
/// [status] = 'Pending' and are stored locally until an approval flow exists.
///
/// Processed requests carry [decisionBy] (the acting role: 'admin' or
/// 'superadmin'), [decisionAt] and an append-only [history] so Superadmin
/// overrides (undo + re-decide) remain fully auditable.
class ViewerRequest {
  final String id;
  final String? batchId;
  final String viewerId;
  final String viewerAccountId;
  final String viewerName;
  final String itemId;
  final String materialNumber;
  final String itemName;
  final int quantity;
  final DateTime createdAt;
  final String section;
  final String? factoryId;
  final String? factoryName;
  final String status;
  final String? decisionBy;
  final DateTime? decisionAt;
  final List<RequestHistoryEntry> history;
  final int version;
  final DateTime? updatedAt;
  final String? relatedTransactionId;
  final TransactionAttachment? billAttachment;

  const ViewerRequest({
    required this.id,
    this.batchId,
    required this.viewerId,
    this.viewerAccountId = '',
    required this.viewerName,
    required this.itemId,
    String? materialNumber,
    required this.itemName,
    required this.quantity,
    required this.createdAt,
    this.section = 'Depot',
    this.factoryId,
    this.factoryName,
    this.status = 'Pending',
    this.decisionBy,
    this.decisionAt,
    this.history = const [],
    this.version = 1,
    this.updatedAt,
    this.relatedTransactionId,
    this.billAttachment,
  }) : materialNumber = materialNumber ?? itemId;

  bool get isPending => status == 'Pending';

  String? get currentRejectionReason {
    if (status != 'Rejected') return null;
    for (final entry in history.reversed) {
      if (entry.status == 'Rejected' &&
          entry.reason?.trim().isNotEmpty == true) {
        return entry.reason!.trim();
      }
    }
    return null;
  }

  /// Human-readable decision for the current status, e.g. 'Accepted by Admin'
  /// or 'Rejected by Superadmin'. Legacy requests without a recorded actor
  /// fall back to the bare 'Accepted' / 'Rejected' label.
  String get decisionLabel {
    if (isPending) return 'Pending';
    final actor = history.isEmpty ? null : history.last.actor;
    if (actor == null || actor.isEmpty) return status;
    return '$status by ${decisionActorLabel(actor)}';
  }

  ViewerRequest copyWith({
    String? status,
    String? decisionBy,
    bool clearDecisionBy = false,
    DateTime? decisionAt,
    bool clearDecisionAt = false,
    List<RequestHistoryEntry>? history,
    int? version,
    DateTime? updatedAt,
    String? relatedTransactionId,
    TransactionAttachment? billAttachment,
  }) {
    return ViewerRequest(
      id: id,
      batchId: batchId,
      viewerId: viewerId,
      viewerAccountId: viewerAccountId,
      viewerName: viewerName,
      itemId: itemId,
      materialNumber: materialNumber,
      itemName: itemName,
      quantity: quantity,
      createdAt: createdAt,
      section: section,
      factoryId: factoryId,
      factoryName: factoryName,
      status: status ?? this.status,
      decisionBy: clearDecisionBy ? null : (decisionBy ?? this.decisionBy),
      decisionAt: clearDecisionAt ? null : (decisionAt ?? this.decisionAt),
      history: history ?? this.history,
      version: version ?? this.version,
      updatedAt: updatedAt ?? this.updatedAt,
      relatedTransactionId: relatedTransactionId ?? this.relatedTransactionId,
      billAttachment: billAttachment ?? this.billAttachment,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        if (batchId != null) 'batchId': batchId,
        'viewerId': viewerId,
        'viewerAccountId': viewerAccountId,
        'viewerName': viewerName,
        'itemId': itemId,
        'materialNumber': materialNumber,
        'itemName': itemName,
        'quantity': quantity,
        'createdAt': createdAt.toIso8601String(),
        'section': section,
        if (factoryId != null) 'factoryId': factoryId,
        if (factoryName != null) 'factoryName': factoryName,
        'status': status,
        if (decisionBy != null) 'decisionBy': decisionBy,
        if (decisionAt != null) 'decisionAt': decisionAt!.toIso8601String(),
        'history': history.map((e) => e.toJson()).toList(),
        'version': version,
        if (updatedAt != null) 'updatedAt': updatedAt!.toIso8601String(),
        if (relatedTransactionId != null)
          'relatedTransactionId': relatedTransactionId,
        if (billAttachment != null)
          'billAttachment': {
            'fileName': billAttachment!.fileName,
            if (billAttachment!.bytes != null)
              'bytes': base64Encode(billAttachment!.bytes!),
            if (billAttachment!.fileId != null)
              'fileId': billAttachment!.fileId,
            if (billAttachment!.contentType != null)
              'contentType': billAttachment!.contentType,
          },
      };

  factory ViewerRequest.fromJson(Map<String, dynamic> json) {
    return ViewerRequest(
      id: json['id'] as String? ?? '',
      batchId: json['batchId'] as String?,
      viewerId: json['viewerId'] as String? ?? '',
      viewerAccountId: json['viewerAccountId'] as String? ?? '',
      viewerName: json['viewerName'] as String? ?? '',
      itemId: json['itemId'] as String? ?? '',
      materialNumber: json['materialNumber'] as String?,
      itemName: json['itemName'] as String? ?? '',
      quantity: (json['quantity'] as num?)?.toInt() ?? 0,
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.now(),
      section: (json['section'] as String? ?? 'DEPOT').toLowerCase() == 'depot'
          ? 'Depot'
          : 'Sleeper',
      factoryId: json['factoryId'] as String?,
      factoryName: json['factoryName'] as String?,
      status: _uiRequestStatus(json['status'] as String?),
      decisionBy: json['decisionBy'] as String?,
      decisionAt: DateTime.tryParse(json['decisionAt'] as String? ?? ''),
      history: (json['history'] as List? ?? [])
          .map((e) => RequestHistoryEntry.fromJson(e as Map<String, dynamic>))
          .toList(),
      version: (json['version'] as num?)?.toInt() ?? 1,
      updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? ''),
      relatedTransactionId: json['relatedTransactionId'] as String?,
      billAttachment: switch (json['billAttachment']) {
        final Map<String, dynamic> bill => TransactionAttachment(
            fileName: bill['fileName'] as String? ?? 'Bill',
            bytes: bill['bytes'] is String
                ? base64Decode(bill['bytes'] as String)
                : null,
            fileId: bill['id'] as String? ?? bill['fileId'] as String?,
            contentType: bill['contentType'] as String?,
          ),
        _ => null,
      },
    );
  }
}

String _uiRequestStatus(String? status) => switch (status?.toUpperCase()) {
      'PENDING' => 'Pending',
      'ACCEPTED' => 'Accepted',
      'REJECTED' => 'Rejected',
      'UNDONE' => 'Undone',
      _ => status ?? 'Pending',
    };
