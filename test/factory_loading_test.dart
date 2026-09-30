import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:warehouse_poc/services/api_client.dart';
import 'package:warehouse_poc/services/inventory_service.dart';

void main() {
  test('factory materials load with bounded concurrency and preserve ordering',
      () async {
    final api = _FactoryApi(factoryCount: 7);
    final factories = await InventoryService(api: api).loadFactories();

    expect(api.maximumConcurrentLoads, inInclusiveRange(2, 4));
    expect(factories.map((factory) => factory.id), [
      'factory-0',
      'factory-1',
      'factory-2',
      'factory-3',
      'factory-4',
      'factory-5',
      'factory-6',
    ]);
    for (var index = 0; index < factories.length; index++) {
      expect(factories[index].materials.single.id, 'material-$index');
    }
  });

  test('archived factories are excluded from active material loading',
      () async {
    final api = _FactoryApi(factoryCount: 2, archiveLast: true);
    final factories = await InventoryService(api: api).loadFactories();

    expect(factories.map((factory) => factory.id), ['factory-0']);
    expect(api.loadedFactoryIds, ['factory-0']);
  });

  test('failed material loading is not represented as an empty factory',
      () async {
    final api = _FactoryApi(factoryCount: 2, failingFactoryId: 'factory-1');

    await expectLater(
      InventoryService(api: api).loadFactories(),
      throwsA(isA<ApiException>()),
    );
  });
}

class _FactoryApi extends ApiClient {
  _FactoryApi({
    required this.factoryCount,
    this.archiveLast = false,
    this.failingFactoryId,
  }) : super(httpClient: MockClient((_) async => http.Response('', 500)));

  final int factoryCount;
  final bool archiveLast;
  final String? failingFactoryId;
  int concurrentLoads = 0;
  int maximumConcurrentLoads = 0;
  final List<String> loadedFactoryIds = [];

  @override
  Future<List<dynamic>> getAll(
    String path, {
    Map<String, String>? query,
  }) async {
    if (path == '/factories') {
      return List.generate(factoryCount, (index) {
        return {
          'id': 'factory-$index',
          'name': 'Factory $index',
          'location': 'Location $index',
          'status':
              archiveLast && index == factoryCount - 1 ? 'ARCHIVED' : 'ACTIVE',
          'version': 1,
        };
      });
    }

    final factoryId = Uri.decodeComponent(path.split('/')[2]);
    loadedFactoryIds.add(factoryId);
    concurrentLoads++;
    if (concurrentLoads > maximumConcurrentLoads) {
      maximumConcurrentLoads = concurrentLoads;
    }
    await Future<void>.delayed(const Duration(milliseconds: 5));
    concurrentLoads--;
    if (factoryId == failingFactoryId) {
      throw const ApiException('Unable to load factory materials.', 503,
          retryable: true);
    }
    final index = int.parse(factoryId.split('-').last);
    return [
      {
        'id': 'material-$index',
        'name': 'Material $index',
        'total': 1,
        'version': 1,
      },
    ];
  }
}
