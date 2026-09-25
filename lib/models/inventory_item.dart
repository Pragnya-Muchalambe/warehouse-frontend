import 'purchase_order_status.dart';

enum InventorySection {
  depot('Depot'),
  sleeper('Sleeper'),
  both('Both');

  const InventorySection(this.label);

  final String label;

  static InventorySection fromLabel(String? label) {
    switch (label?.toLowerCase()) {
      case 'depot':
        return InventorySection.depot;
      case 'sleeper':
        return InventorySection.sleeper;
      default:
        return InventorySection.both;
    }
  }
}

class InventoryItem {
  final String id;
  final String materialNumber;
  final String name;
  final int quantity;
  final String uom;
  final String status;
  final InventorySection section;
  final int biIssued;
  final int searchFrequency;
  final DateTime? lastSearchedAt;
  final DateTime? lastEditedAt;
  final int incomingQuantity;
  final DateTime? expectedAvailabilityDate;
  final PurchaseOrderStatus purchaseOrderStatus;
  final int version;
  final int? _available;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const InventoryItem({
    required this.id,
    String? materialNumber,
    required this.name,
    required this.quantity,
    this.uom = 'Pieces',
    this.status = 'Available',
    this.section = InventorySection.both,
    this.biIssued = 0,
    this.searchFrequency = 0,
    this.lastSearchedAt,
    this.lastEditedAt,
    this.incomingQuantity = 0,
    this.expectedAvailabilityDate,
    this.purchaseOrderStatus = PurchaseOrderStatus.none,
    this.version = 1,
    int? available,
    this.createdAt,
    this.updatedAt,
  })  : materialNumber = materialNumber ?? id,
        _available = available;

  /// Quantity currently available: total minus what has already been issued.
  int get available {
    final value = _available ?? quantity - biIssued;
    return value < 0 ? 0 : value;
  }

  InventoryItem copyWith({
    String? id,
    String? materialNumber,
    String? name,
    int? quantity,
    String? uom,
    String? status,
    InventorySection? section,
    int? biIssued,
    int? searchFrequency,
    DateTime? lastSearchedAt,
    DateTime? lastEditedAt,
    int? incomingQuantity,
    DateTime? expectedAvailabilityDate,
    PurchaseOrderStatus? purchaseOrderStatus,
    int? version,
    int? available,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return InventoryItem(
      id: id ?? this.id,
      materialNumber: materialNumber ?? this.materialNumber,
      name: name ?? this.name,
      quantity: quantity ?? this.quantity,
      uom: uom ?? this.uom,
      status: status ?? this.status,
      section: section ?? this.section,
      biIssued: biIssued ?? this.biIssued,
      searchFrequency: searchFrequency ?? this.searchFrequency,
      lastSearchedAt: lastSearchedAt ?? this.lastSearchedAt,
      lastEditedAt: lastEditedAt ?? this.lastEditedAt,
      incomingQuantity: incomingQuantity ?? this.incomingQuantity,
      expectedAvailabilityDate:
          expectedAvailabilityDate ?? this.expectedAvailabilityDate,
      purchaseOrderStatus: purchaseOrderStatus ?? this.purchaseOrderStatus,
      version: version ?? this.version,
      available: available ?? _available,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  bool isOutOfStock() => available <= 0;

  bool isInSection(InventorySection section) {
    return this.section == InventorySection.both || this.section == section;
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'materialNumber': materialNumber,
        'name': name,
        'quantity': quantity,
        'uom': uom,
        'status': status,
        'section': section.label,
        'biIssued': biIssued,
        'searchFrequency': searchFrequency,
        'lastSearchedAt': lastSearchedAt?.toIso8601String(),
        'lastEditedAt': lastEditedAt?.toIso8601String(),
        'incomingQuantity': incomingQuantity,
        'expectedAvailabilityDate': expectedAvailabilityDate?.toIso8601String(),
        'purchaseOrderStatus': purchaseOrderStatus.label,
        'version': version,
        'available': available,
        'createdAt': createdAt?.toIso8601String(),
        'updatedAt': updatedAt?.toIso8601String(),
      };

  factory InventoryItem.fromJson(Map<String, dynamic> json) {
    return InventoryItem(
      id: json['id'] as String,
      materialNumber: json['materialNumber'] as String?,
      name: json['name'] as String,
      quantity: (json['quantity'] as num?)?.toInt() ?? 0,
      uom: json['uom'] as String? ?? 'Pieces',
      status: json['status'] as String? ?? 'Available',
      section: InventorySection.fromLabel(json['section'] as String?),
      biIssued: (json['biIssued'] as num?)?.toInt() ?? 0,
      searchFrequency: (json['searchFrequency'] as num?)?.toInt() ?? 0,
      lastSearchedAt: _parseDate(json['lastSearchedAt']),
      lastEditedAt: _parseDate(json['lastEditedAt']),
      incomingQuantity: (json['incomingQuantity'] as num?)?.toInt() ?? 0,
      expectedAvailabilityDate: _parseDate(json['expectedAvailabilityDate']),
      purchaseOrderStatus:
          PurchaseOrderStatus.fromLabel(json['purchaseOrderStatus'] as String?),
      version: (json['version'] as num?)?.toInt() ?? 1,
      available: (json['available'] as num?)?.toInt(),
      createdAt: _parseDate(json['createdAt']),
      updatedAt: _parseDate(json['updatedAt']),
    );
  }

  static DateTime? _parseDate(Object? value) {
    if (value is String) return DateTime.tryParse(value);
    if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
    return null;
  }
}
