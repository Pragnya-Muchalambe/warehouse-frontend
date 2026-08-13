import 'dart:math';

import 'purchase_order_status.dart';

/// A material entry owned by a warehouse factory.
///
/// Factories track [total] stock and [biIssued] quantity; [available] is
/// always derived as `max(total - biIssued, 0)`. Incoming / purchase order
/// information (quantity, expected date, status) is stored alongside.
class FactoryMaterial {
  final String id;
  final String name;
  final int total;
  final int biIssued;
  final int incomingQuantity;
  final DateTime? expectedAvailabilityDate;
  final PurchaseOrderStatus purchaseOrderStatus;

  const FactoryMaterial({
    required this.id,
    required this.name,
    required this.total,
    this.biIssued = 0,
    this.incomingQuantity = 0,
    this.expectedAvailabilityDate,
    this.purchaseOrderStatus = PurchaseOrderStatus.none,
  });

  /// Quantity currently available in the factory: total minus what has
  /// already been issued. Never negative.
  int get available => max(total - biIssued, 0);

  bool isOutOfStock() => available <= 0;

  FactoryMaterial copyWith({
    String? id,
    String? name,
    int? total,
    int? biIssued,
    int? incomingQuantity,
    DateTime? expectedAvailabilityDate,
    PurchaseOrderStatus? purchaseOrderStatus,
  }) {
    return FactoryMaterial(
      id: id ?? this.id,
      name: name ?? this.name,
      total: total ?? this.total,
      biIssued: biIssued ?? this.biIssued,
      incomingQuantity: incomingQuantity ?? this.incomingQuantity,
      expectedAvailabilityDate:
          expectedAvailabilityDate ?? this.expectedAvailabilityDate,
      purchaseOrderStatus: purchaseOrderStatus ?? this.purchaseOrderStatus,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'total': total,
        'biIssued': biIssued,
        'incomingQuantity': incomingQuantity,
        'expectedAvailabilityDate': expectedAvailabilityDate?.toIso8601String(),
        'purchaseOrderStatus': purchaseOrderStatus.label,
      };

  factory FactoryMaterial.fromJson(Map<String, dynamic> json) {
    // Legacy records stored available/deported instead of total/biIssued.
    // Migrate them: total = available + deported, biIssued = deported.
    final hasTotal = json.containsKey('total');
    final legacyAvailable = (json['available'] as num?)?.toInt() ?? 0;
    final legacyDeported = (json['deported'] as num?)?.toInt() ?? 0;
    return FactoryMaterial(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      total: hasTotal
          ? (json['total'] as num?)?.toInt() ?? 0
          : legacyAvailable + legacyDeported,
      biIssued: hasTotal
          ? (json['biIssued'] as num?)?.toInt() ?? 0
          : legacyDeported,
      incomingQuantity: (json['incomingQuantity'] as num?)?.toInt() ?? 0,
      expectedAvailabilityDate: _parseDate(json['expectedAvailabilityDate']),
      purchaseOrderStatus:
          PurchaseOrderStatus.fromLabel(json['purchaseOrderStatus'] as String?),
    );
  }

  static DateTime? _parseDate(Object? value) {
    if (value is String) return DateTime.tryParse(value);
    return null;
  }
}

/// A warehouse factory that groups materials under the Sleeper section.
class WarehouseFactory {
  final String id;
  final String name;
  final String location;
  final List<FactoryMaterial> materials;

  const WarehouseFactory({
    required this.id,
    required this.name,
    required this.location,
    this.materials = const [],
  });

  WarehouseFactory copyWith({
    String? id,
    String? name,
    String? location,
    List<FactoryMaterial>? materials,
  }) {
    return WarehouseFactory(
      id: id ?? this.id,
      name: name ?? this.name,
      location: location ?? this.location,
      materials: materials ?? this.materials,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'location': location,
        'materials': materials.map((m) => m.toJson()).toList(),
      };

  factory WarehouseFactory.fromJson(Map<String, dynamic> json) {
    return WarehouseFactory(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      location: json['location'] as String? ?? '',
      materials: (json['materials'] as List? ?? [])
          .map((e) => FactoryMaterial.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}
