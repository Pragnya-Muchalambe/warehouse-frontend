import 'inventory_item.dart';

class CartItem {
  final String id;
  final String name;
  final int quantityChange;
  final int? max;

  const CartItem({
    required this.id,
    required this.name,
    required this.quantityChange,
    this.max,
  });

  CartItem copyWith({int? quantityChange}) {
    return CartItem(
      id: id,
      name: name,
      quantityChange: quantityChange ?? this.quantityChange,
      max: max,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'quantityChange': quantityChange,
      };

  factory CartItem.fromJson(Map<String, dynamic> json) {
    return CartItem(
      id: json['id'] as String,
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
  final String? photo;
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

  /// Optional base64-encoded proof image so the Audit view can display it.
  /// Only stored when the original capture is small enough (<= ~1MB).
  final String? photoData;

  const TransactionLog({
    required this.id,
    required this.timestamp,
    required this.type,
    required this.user,
    required this.items,
    this.notes,
    this.photo,
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
    this.photoData,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'timestamp': timestamp.toIso8601String(),
        'type': type.label,
        'user': user,
        'items': items.map((i) => i.toJson()).toList(),
        if (notes != null) 'notes': notes,
        if (photo != null) 'photo': photo,
        if (photoData != null) 'photoData': photoData,
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
      photo: json['photo'] as String?,
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
      photoData: json['photoData'] as String?,
    );
  }
}
