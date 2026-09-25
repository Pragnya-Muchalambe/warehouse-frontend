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
  final int version;
  final int? _available;
  final String status;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const FactoryMaterial({
    required this.id,
    required this.name,
    required this.total,
    this.biIssued = 0,
    this.incomingQuantity = 0,
    this.expectedAvailabilityDate,
    this.purchaseOrderStatus = PurchaseOrderStatus.none,
    this.version = 1,
    int? available,
    this.status = 'AVAILABLE',
    this.createdAt,
    this.updatedAt,
  }) : _available = available;

  /// Quantity currently available in the factory: total minus what has
  int get available => _available ?? total - biIssued;

  bool isOutOfStock() => available <= 0;

  FactoryMaterial copyWith({
    String? id,
    String? name,
    int? total,
    int? biIssued,
    int? incomingQuantity,
    DateTime? expectedAvailabilityDate,
    PurchaseOrderStatus? purchaseOrderStatus,
    int? version,
    int? available,
    String? status,
    DateTime? createdAt,
    DateTime? updatedAt,
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
      version: version ?? this.version,
      available: available ?? _available,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
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
        'version': version,
        'available': available,
        'status': status,
        'createdAt': createdAt?.toIso8601String(),
        'updatedAt': updatedAt?.toIso8601String(),
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
      biIssued:
          hasTotal ? (json['biIssued'] as num?)?.toInt() ?? 0 : legacyDeported,
      incomingQuantity: (json['incomingQuantity'] as num?)?.toInt() ?? 0,
      expectedAvailabilityDate: _parseDate(json['expectedAvailabilityDate']),
      purchaseOrderStatus:
          PurchaseOrderStatus.fromLabel(json['purchaseOrderStatus'] as String?),
      version: (json['version'] as num?)?.toInt() ?? 1,
      available: (json['available'] as num?)?.toInt(),
      status: json['status'] as String? ?? 'AVAILABLE',
      createdAt: _parseDate(json['createdAt']),
      updatedAt: _parseDate(json['updatedAt']),
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
  final int version;
  final int materialCount;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const WarehouseFactory({
    required this.id,
    required this.name,
    required this.location,
    this.materials = const [],
    this.version = 1,
    this.materialCount = 0,
    this.createdAt,
    this.updatedAt,
  });

  WarehouseFactory copyWith({
    String? id,
    String? name,
    String? location,
    List<FactoryMaterial>? materials,
    int? version,
    int? materialCount,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return WarehouseFactory(
      id: id ?? this.id,
      name: name ?? this.name,
      location: location ?? this.location,
      materials: materials ?? this.materials,
      version: version ?? this.version,
      materialCount: materialCount ?? this.materialCount,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'location': location,
        'materials': materials.map((m) => m.toJson()).toList(),
        'version': version,
        'materialCount': materialCount,
        'createdAt': createdAt?.toIso8601String(),
        'updatedAt': updatedAt?.toIso8601String(),
      };

  factory WarehouseFactory.fromJson(Map<String, dynamic> json) {
    return WarehouseFactory(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      location: json['location'] as String? ?? '',
      materials: (json['materials'] as List? ?? [])
          .map((e) => FactoryMaterial.fromJson(e as Map<String, dynamic>))
          .toList(),
      version: (json['version'] as num?)?.toInt() ?? 1,
      materialCount: (json['materialCount'] as num?)?.toInt() ??
          (json['materials'] as List?)?.length ??
          0,
      createdAt: FactoryMaterial._parseDate(json['createdAt']),
      updatedAt: FactoryMaterial._parseDate(json['updatedAt']),
    );
  }
}
