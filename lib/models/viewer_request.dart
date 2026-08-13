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
  final DateTime at;

  const RequestHistoryEntry({
    required this.status,
    required this.actor,
    required this.at,
  });

  String get label {
    if (status == 'Pending') return 'Pending';
    return '$status by ${decisionActorLabel(actor)}';
  }

  Map<String, dynamic> toJson() => {
        'status': status,
        'actor': actor,
        'at': at.toIso8601String(),
      };

  factory RequestHistoryEntry.fromJson(Map<String, dynamic> json) {
    return RequestHistoryEntry(
      status: json['status'] as String? ?? '',
      actor: json['actor'] as String? ?? '',
      at: DateTime.tryParse(json['at'] as String? ?? '') ?? DateTime.now(),
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
  final String viewerId;
  final String viewerName;
  final String itemId;
  final String itemName;
  final int quantity;
  final DateTime createdAt;
  final String section;
  final String status;
  final String? decisionBy;
  final DateTime? decisionAt;
  final List<RequestHistoryEntry> history;

  const ViewerRequest({
    required this.id,
    required this.viewerId,
    required this.viewerName,
    required this.itemId,
    required this.itemName,
    required this.quantity,
    required this.createdAt,
    this.section = 'Depot',
    this.status = 'Pending',
    this.decisionBy,
    this.decisionAt,
    this.history = const [],
  });

  bool get isPending => status == 'Pending';

  /// Human-readable decision for the current status, e.g. 'Accepted by Admin'
  /// or 'Rejected by Superadmin'. Legacy requests without a recorded actor
  /// fall back to the bare 'Accepted' / 'Rejected' label.
  String get decisionLabel {
    if (isPending) return 'Pending';
    if (decisionBy == null || decisionBy!.isEmpty) return status;
    return '$status by ${decisionActorLabel(decisionBy!)}';
  }

  ViewerRequest copyWith({
    String? status,
    String? decisionBy,
    bool clearDecisionBy = false,
    DateTime? decisionAt,
    bool clearDecisionAt = false,
    List<RequestHistoryEntry>? history,
  }) {
    return ViewerRequest(
      id: id,
      viewerId: viewerId,
      viewerName: viewerName,
      itemId: itemId,
      itemName: itemName,
      quantity: quantity,
      createdAt: createdAt,
      section: section,
      status: status ?? this.status,
      decisionBy: clearDecisionBy ? null : (decisionBy ?? this.decisionBy),
      decisionAt: clearDecisionAt ? null : (decisionAt ?? this.decisionAt),
      history: history ?? this.history,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'viewerId': viewerId,
        'viewerName': viewerName,
        'itemId': itemId,
        'itemName': itemName,
        'quantity': quantity,
        'createdAt': createdAt.toIso8601String(),
        'section': section,
        'status': status,
        if (decisionBy != null) 'decisionBy': decisionBy,
        if (decisionAt != null) 'decisionAt': decisionAt!.toIso8601String(),
        'history': history.map((e) => e.toJson()).toList(),
      };

  factory ViewerRequest.fromJson(Map<String, dynamic> json) {
    return ViewerRequest(
      id: json['id'] as String? ?? '',
      viewerId: json['viewerId'] as String? ?? '',
      viewerName: json['viewerName'] as String? ?? '',
      itemId: json['itemId'] as String? ?? '',
      itemName: json['itemName'] as String? ?? '',
      quantity: (json['quantity'] as num?)?.toInt() ?? 0,
      createdAt:
          DateTime.tryParse(json['createdAt'] as String? ?? '') ??
              DateTime.now(),
      section: json['section'] as String? ?? 'Depot',
      status: json['status'] as String? ?? 'Pending',
      decisionBy: json['decisionBy'] as String?,
      decisionAt: DateTime.tryParse(json['decisionAt'] as String? ?? ''),
      history: (json['history'] as List? ?? [])
          .map((e) => RequestHistoryEntry.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}
