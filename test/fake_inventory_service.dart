import 'package:warehouse_poc/models/audit_log.dart';
import 'package:warehouse_poc/models/factory.dart';
import 'package:warehouse_poc/models/inventory_item.dart';
import 'package:warehouse_poc/models/transaction_log.dart';
import 'package:warehouse_poc/services/inventory_service.dart';

class FakeInventoryService extends InventoryService {
  final List<WarehouseFactory> _factories;
  final List<InventoryItem> _inventory;
  int loadLogsCalls = 0;
  int loadAuditLogsCalls = 0;

  FakeInventoryService({
    List<WarehouseFactory> factories = const [],
    List<InventoryItem> inventory = const [],
  })  : _factories = [...factories],
        _inventory = [...inventory];

  @override
  Future<List<InventoryItem>> loadInventory() async =>
      List.unmodifiable(_inventory);

  @override
  Future<List<TransactionLog>> loadLogs() async {
    loadLogsCalls++;
    return [];
  }

  @override
  Future<List<AuditLog>> loadAuditLogs() async {
    loadAuditLogsCalls++;
    return [];
  }

  @override
  Future<List<WarehouseFactory>> loadFactories() async =>
      List.unmodifiable(_factories);

  @override
  Future<WarehouseFactory> createFactory(String name, String location) async {
    final factory = WarehouseFactory(
      id: '00000000-0000-4000-8000-000000000001',
      name: name,
      location: location,
    );
    _factories.add(factory);
    return factory;
  }

  @override
  Future<FactoryMaterial> createFactoryMaterial(
    String factoryId,
    Map<String, dynamic> body,
  ) async {
    return FactoryMaterial.fromJson({...body, 'version': 1});
  }
}
