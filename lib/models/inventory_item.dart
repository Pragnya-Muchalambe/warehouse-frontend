import 'dart:math';

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

  const InventoryItem({
    required this.id,
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
  });

  /// Quantity currently available: total minus what has already been issued.
  /// Never negative.
  int get available => max(quantity - biIssued, 0);

  factory InventoryItem.fromCsvRow(List<dynamic> row) {
    final id = (row.isNotEmpty ? row[0].toString() : '').trim();
    final name = (row.length > 1 ? row[1].toString() : '').trim();
    // Matches the React POC: random stock 0-20 on first seed.
    return InventoryItem(
      id: id,
      name: name,
      quantity: Random().nextInt(21),
    );
  }

  InventoryItem copyWith({
    String? id,
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
  }) {
    return InventoryItem(
      id: id ?? this.id,
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
    );
  }

  bool isOutOfStock() => available <= 0;

  bool isInSection(InventorySection section) {
    return this.section == InventorySection.both || this.section == section;
  }

  Map<String, dynamic> toJson() => {
        'id': id,
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
      };

  factory InventoryItem.fromJson(Map<String, dynamic> json) {
    return InventoryItem(
      id: json['id'] as String,
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
    );
  }

  static DateTime? _parseDate(Object? value) {
    if (value is String) return DateTime.tryParse(value);
    if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
    return null;
  }
}
