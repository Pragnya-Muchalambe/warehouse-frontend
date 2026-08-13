import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:csv/csv.dart';

import '../models/factory.dart';
import '../models/inventory_item.dart';
import '../models/purchase_order_status.dart';
import '../models/transaction_log.dart';

class InventoryService {
  static const inventoryKey = 'warehouse_inventory';
  static const logsKey = 'warehouse_logs';
  static const factoriesKey = 'warehouse_factories';
  static const csvAssetPath = 'assets/material_serial_mappings.csv';

  Future<List<InventoryItem>> loadInventory() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(inventoryKey);
    if (stored != null) {
      return _decodeItems(stored);
    }
    // First run: seed from the bundled CSV (matches React POC behavior).
    final items = await _seedFromCsv();
    await saveInventory(items);
    return items;
  }

  Future<List<InventoryItem>> _seedFromCsv() async {
    final raw = await rootBundle.loadString(csvAssetPath);
    final rows = const CsvToListConverter(
      shouldParseNumbers: false,
    ).convert(raw);
    // Skip the header row, drop empty rows, validate id/name.
    return rows
        .skip(1)
        .where((r) => r.isNotEmpty)
        .map(InventoryItem.fromCsvRow)
        .where((i) => i.id.isNotEmpty && i.name.isNotEmpty)
        .toList();
  }

  Future<void> saveInventory(List<InventoryItem> items) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      inventoryKey,
      jsonEncode(items.map((i) => i.toJson()).toList()),
    );
  }

  Future<List<TransactionLog>> loadLogs() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(logsKey);
    if (stored == null) return [];
    return _decodeLogs(stored);
  }

  Future<void> saveLogs(List<TransactionLog> logs) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      logsKey,
      jsonEncode(logs.map((l) => l.toJson()).toList()),
    );
  }

  Future<List<WarehouseFactory>> loadFactories() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(factoriesKey);
    if (stored != null) {
      return _decodeFactories(stored);
    }
    // First run: seed demo factories. Only happens when nothing is stored,
    // so factories created by the user are never overwritten.
    final seeded = _seedDemoFactories();
    await saveFactories(seeded);
    return seeded;
  }

  Future<void> saveFactories(List<WarehouseFactory> factories) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      factoriesKey,
      jsonEncode(factories.map((f) => f.toJson()).toList()),
    );
  }

  List<WarehouseFactory> _decodeFactories(String raw) {
    final decoded = jsonDecode(raw) as List;
    return decoded
        .map((e) => WarehouseFactory.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  FactoryMaterial _m(String id, String name, int total, {int biIssued = 0}) =>
      FactoryMaterial(id: id, name: name, total: total, biIssued: biIssued);

  FactoryMaterial _incoming(
    FactoryMaterial m,
    int qty,
    DateTime expected, [
    PurchaseOrderStatus status = PurchaseOrderStatus.pending,
  ]) =>
      m.copyWith(
        incomingQuantity: qty,
        expectedAvailabilityDate: expected,
        purchaseOrderStatus: status,
      );

  List<WarehouseFactory> _seedDemoFactories() {
    final expected = DateTime(2026, 8, 25);
    return [
      WarehouseFactory(
        id: 'factory-1',
        name: 'FACTORY_NAME_1',
        location: 'Bangalore',
        materials: [
          _m('F1-001', 'GRSP Sleepers 60 Kg', 300, biIssued: 60),
          _m('F1-002', 'Elastic Rail Clips Mark-V', 1200, biIssued: 250),
          _incoming(
            _m('F1-003', 'GFN Liner 60 Kg', 120, biIssued: 120),
            50,
            expected,
          ),
          _m('F1-004', 'Metal Liner 60 Kg', 500, biIssued: 90),
          _m('F1-005', 'Fish Plate 60 Kg', 160, biIssued: 30),
        ],
      ),
      WarehouseFactory(
        id: 'factory-2',
        name: 'FACTORY_NAME_2',
        location: 'Mysore',
        materials: [
          _m('F2-001', 'Concrete Sleepers 60 Kg', 700, biIssued: 180),
          _incoming(
            _m('F2-002', 'Rubber Pad 60 Kg', 40, biIssued: 40),
            25,
            expected,
          ),
          _m('F2-003', 'H.D. Clips 60 Kg', 375, biIssued: 75),
        ],
      ),
      WarehouseFactory(
        id: 'factory-3',
        name: 'FACTORY_NAME_3',
        location: 'Hubli',
        materials: [
          _m('F3-001', 'GRSP Sleepers 52 Kg', 400, biIssued: 220),
          _m('F3-002', 'MCI Inserts 60 Kg', 700, biIssued: 60),
          _m('F3-003', 'Fixing Screws 60 Kg', 810, biIssued: 90),
          _incoming(
            _m('F3-004', 'GS Fastenings Kit', 15, biIssued: 15),
            40,
            expected,
            PurchaseOrderStatus.ordered,
          ),
        ],
      ),
    ];
  }

  List<InventoryItem> _decodeItems(String raw) {
    final decoded = jsonDecode(raw) as List;
    return decoded
        .map((e) => InventoryItem.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  List<TransactionLog> _decodeLogs(String raw) {
    final decoded = jsonDecode(raw) as List;
    return decoded
        .map((e) => TransactionLog.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}
