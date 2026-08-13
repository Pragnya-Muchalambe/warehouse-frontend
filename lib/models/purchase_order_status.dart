/// Status of incoming / purchase order stock for a material.
enum PurchaseOrderStatus {
  none('No Incoming Order'),
  pending('Purchase Order Pending'),
  ordered('Ordered / Awaiting Delivery');

  const PurchaseOrderStatus(this.label);

  final String label;

  bool get hasIncoming => this != none;

  static PurchaseOrderStatus fromLabel(String? label) {
    if (label == null) return none;
    final trimmed = label.trim();
    for (final status in values) {
      if (status.label.toLowerCase() == trimmed.toLowerCase()) return status;
      if (status.name.toLowerCase() == trimmed.toLowerCase()) return status;
    }
    return none;
  }
}
