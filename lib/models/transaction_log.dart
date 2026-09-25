import 'dart:convert';
import 'dart:typed_data';

import 'inventory_item.dart';

class TransactionAttachment {
  final String fileName;
  final Uint8List? bytes;
  final String? fileId;
  final String? contentType;

  const TransactionAttachment({
    required this.fileName,
    this.bytes,
    this.fileId,
    this.contentType,
  });

  bool get isPdf =>
      contentType == 'application/pdf' ||
      fileName.toLowerCase().endsWith('.pdf');

  factory TransactionAttachment.fromApi(Map<String, dynamic> json) =>
      TransactionAttachment(
        fileName: json['fileName'] as String? ?? 'Proof',
        fileId: json['id'] as String?,
        contentType: json['contentType'] as String?,
      );
}

class CartItem {
  final String id;
  final String materialNumber;
  final String name;
  final int quantityChange;
  final int? max;

  const CartItem({
    required this.id,
    String? materialNumber,
    required this.name,
    required this.quantityChange,
    this.max,
  }) : materialNumber = materialNumber ?? id;

  CartItem copyWith({int? quantityChange}) {
    return CartItem(
      id: id,
      materialNumber: materialNumber,
      name: name,
      quantityChange: quantityChange ?? this.quantityChange,
      max: max,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'materialNumber': materialNumber,
        'name': name,
        'quantityChange': quantityChange,
      };

  factory CartItem.fromJson(Map<String, dynamic> json) {
    return CartItem(
      id: json['id'] as String,
      materialNumber: json['materialNumber'] as String?,
      name: json['name'] as String,
      quantityChange: (json['quantityChange'] as num?)?.toInt() ?? 0,
    );
  }
}

enum LogType {
  incoming('INCOMING'),
  dispatch('DISPATCH'),
  edit('EDIT'),
  requestAccepted('REQUEST ACCEPTED'),
  requestRejected('REQUEST REJECTED'),
  requestUndone('REQUEST UNDONE');

  final String label;
  const LogType(this.label);

  static LogType fromLabel(String label) {
    return LogType.values.firstWhere(
      (t) => t.label == label,
      orElse: () => LogType.incoming,
    );
  }
}

class TransactionLog {
  final String id;
  final DateTime timestamp;
  final LogType type;
  final String user;
  final List<CartItem> items;
  final String? notes;
  final String? bill;
  final String? billData;
  final String? proof;
  final String? proofData;
  final List<TransactionAttachment> proofs;
  final String? refLogId;
  final List<CartItem>? oldItems;
  final InventorySection? section;
  final String? factoryName;
  final String? person;
  final String? comingFrom;
  final String? dateOfArrival;
  final String? dateRequested;
  final String? dateLeaving;
  final String? truckNumber;
  final String? factoryId;
  final String? billFileId;
  final List<String> proofFileIds;
  final String? proofFileId;
  final int version;
  final DateTime? updatedAt;
  final DateTime? correctedAt;
  final DateTime? reversedAt;

  const TransactionLog({
    required this.id,
    required this.timestamp,
    required this.type,
    required this.user,
    required this.items,
    this.notes,
    this.bill,
    this.billData,
    this.proof,
    this.proofData,
    this.proofs = const [],
    this.refLogId,
    this.oldItems,
    this.section,
    this.factoryName,
    this.person,
    this.comingFrom,
    this.dateOfArrival,
    this.dateRequested,
    this.dateLeaving,
    this.truckNumber,
    this.factoryId,
    this.billFileId,
    this.proofFileIds = const [],
    this.proofFileId,
    this.version = 1,
    this.updatedAt,
    this.correctedAt,
    this.reversedAt,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'timestamp': timestamp.toIso8601String(),
        'type': type.label,
        'user': user,
        'items': items.map((i) => i.toJson()).toList(),
        if (notes != null) 'notes': notes,
        if (bill != null) 'bill': bill,
        if (billData != null) 'billData': billData,
        if (proof != null) 'proof': proof,
        if (proofData != null) 'proofData': proofData,
        'proofs': proofs
            .map((proof) => {
                  'fileName': proof.fileName,
                  if (proof.bytes != null) 'bytes': base64Encode(proof.bytes!),
                  if (proof.fileId != null) 'fileId': proof.fileId,
                  if (proof.contentType != null)
                    'contentType': proof.contentType,
                })
            .toList(),
        if (refLogId != null) 'refLogId': refLogId,
        if (oldItems != null)
          'oldItems': oldItems!.map((i) => i.toJson()).toList(),
        if (section != null) 'section': section!.label,
        if (factoryName != null) 'factoryName': factoryName,
        if (person != null) 'person': person,
        if (comingFrom != null) 'comingFrom': comingFrom,
        if (dateOfArrival != null) 'dateOfArrival': dateOfArrival,
        if (dateRequested != null) 'dateRequested': dateRequested,
        if (dateLeaving != null) 'dateLeaving': dateLeaving,
        if (truckNumber != null) 'truckNumber': truckNumber,
        if (factoryId != null) 'factoryId': factoryId,
        if (billFileId != null) 'billFileId': billFileId,
        'proofFileIds': proofFileIds,
        'version': version,
      };

  factory TransactionLog.fromJson(Map<String, dynamic> json) {
    return TransactionLog(
      id: json['id'] as String,
      timestamp: DateTime.tryParse(json['timestamp'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      type: LogType.fromLabel(json['type'] as String? ?? ''),
      user: json['user'] as String? ?? '',
      items: (json['items'] as List? ?? [])
          .map((e) => CartItem.fromJson(e as Map<String, dynamic>))
          .toList(),
      notes: json['notes'] as String?,
      bill: json['bill'] as String?,
      billData: json['billData'] as String?,
      // The former combined attachment represented proof when no typed fields
      // existed. Keep it as Proof when loading locally persisted legacy logs.
      proof: json['proof'] as String? ?? json['photo'] as String?,
      proofData: json['proofData'] as String? ?? json['photoData'] as String?,
      proofs: (json['proofs'] as List? ?? []).map((value) {
        final proof = value as Map<String, dynamic>;
        final encoded = proof['bytes'] as String?;
        return TransactionAttachment(
          fileName: proof['fileName'] as String? ?? 'Proof',
          bytes: encoded == null ? null : base64Decode(encoded),
          fileId: proof['fileId'] as String?,
          contentType: proof['contentType'] as String?,
        );
      }).toList(),
      refLogId: json['refLogId'] as String?,
      oldItems: (json['oldItems'] as List?)
          ?.map((e) => CartItem.fromJson(e as Map<String, dynamic>))
          .toList(),
      section: json['section'] == null
          ? null
          : InventorySection.fromLabel(json['section'] as String?),
      factoryName: json['factoryName'] as String?,
      person: json['person'] as String?,
      comingFrom: json['comingFrom'] as String?,
      dateOfArrival: json['dateOfArrival'] as String?,
      dateRequested: json['dateRequested'] as String?,
      dateLeaving: json['dateLeaving'] as String?,
      truckNumber: json['truckNumber'] as String?,
      factoryId: json['factoryId'] as String?,
      billFileId: json['billFileId'] as String?,
      proofFileIds: json.containsKey('proofFileIds')
          ? (json['proofFileIds'] as List? ?? const [])
              .whereType<String>()
              .toList()
          : [if (json['proofFileId'] is String) json['proofFileId'] as String],
      proofFileId: json['proofFileId'] as String?,
      version: (json['version'] as num?)?.toInt() ?? 1,
    );
  }

  factory TransactionLog.fromApi(Map<String, dynamic> json) {
    final scope = json['scope'] as String?;
    final createdAt = DateTime.tryParse(json['createdAt'] as String? ?? '');
    final type = switch (json['type']) {
      'INCOMING' => LogType.incoming,
      'DISPATCH' => LogType.dispatch,
      _ => throw const FormatException('Invalid transaction type'),
    };
    final section = switch (scope) {
      'DEPOT' => InventorySection.depot,
      'FACTORY' => InventorySection.sleeper,
      _ => throw const FormatException('Invalid transaction scope'),
    };
    if (createdAt == null) {
      throw const FormatException('Invalid transaction timestamp');
    }
    final hasCanonicalProofs =
        json.containsKey('proofFileIds') || json.containsKey('proofFiles');
    final proofFileIds = (json['proofFileIds'] as List? ?? const [])
        .whereType<String>()
        .toList();
    final proofs = (json['proofFiles'] as List? ?? const [])
        .whereType<Map>()
        .map((proof) => TransactionAttachment.fromApi(
              Map<String, dynamic>.from(proof),
            ))
        .toList();
    final legacyProofFile = json['proofFile'] as Map?;
    if (!hasCanonicalProofs && legacyProofFile != null) {
      proofs.add(TransactionAttachment.fromApi(
        Map<String, dynamic>.from(legacyProofFile),
      ));
    }
    return TransactionLog(
      id: json['id'] as String,
      timestamp: createdAt,
      type: type,
      user: ((json['createdBy'] as Map?)?['name'] as String?) ?? '',
      items: (json['items'] as List? ?? []).map((e) {
        final item = e as Map<String, dynamic>;
        return CartItem(
            id: item['materialId'] as String,
            materialNumber: item['materialNumberSnapshot'] as String?,
            name: item['materialNameSnapshot'] as String? ??
                item['materialId'] as String,
            quantityChange: (item['quantityChange'] as num).toInt());
      }).toList(),
      notes: json['notes'] as String?,
      section: section,
      factoryId: json['factoryId'] as String?,
      billFileId: json['billFileId'] as String?,
      proofFileIds: proofFileIds,
      proofFileId: hasCanonicalProofs ? null : json['proofFileId'] as String?,
      proofs: proofs,
      factoryName: json['factoryNameSnapshot'] as String?,
      person: json['person'] as String?,
      comingFrom: json['comingFrom'] as String?,
      dateOfArrival: json['dateOfArrival'] as String?,
      dateRequested: json['dateRequested'] as String?,
      dateLeaving: json['dateLeaving'] as String?,
      truckNumber: json['truckNumber'] as String?,
      bill: ((json['billFile'] as Map?)?['fileName'] as String?),
      proof: hasCanonicalProofs
          ? null
          : ((json['proofFile'] as Map?)?['fileName'] as String?),
      version: (json['version'] as num?)?.toInt() ?? 1,
      updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? ''),
      correctedAt: DateTime.tryParse(json['correctedAt'] as String? ?? ''),
      reversedAt: DateTime.tryParse(json['reversedAt'] as String? ?? ''),
    );
  }
}
