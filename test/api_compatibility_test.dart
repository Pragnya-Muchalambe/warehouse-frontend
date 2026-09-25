import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:warehouse_poc/controllers/inventory_controller.dart';
import 'package:warehouse_poc/models/audit_log.dart';
import 'package:warehouse_poc/models/factory.dart';
import 'package:warehouse_poc/models/inventory_item.dart';
import 'package:warehouse_poc/models/transaction_log.dart';
import 'package:warehouse_poc/models/viewer_request.dart';
import 'package:warehouse_poc/services/api_client.dart';
import 'package:warehouse_poc/services/auth_service.dart';
import 'package:warehouse_poc/services/inventory_service.dart';
import 'package:warehouse_poc/services/request_service.dart';

import 'fake_inventory_service.dart';

void main() {
  test('unknown roles are rejected instead of receiving a privileged shell',
      () {
    expect(
      () => AuthSession.fromApi({'role': 'FUTURE_ROLE'}),
      throwsA(isA<ApiException>()),
    );
  });

  test('incomplete privileged users fail closed', () {
    expect(
      () => AuthSession.fromApi({'role': 'ADMIN'}),
      throwsA(isA<ApiException>()),
    );
  });

  test('viewer initialization skips protected transaction history', () async {
    final service = FakeInventoryService();
    final controller = InventoryController(inventoryService: service);

    await controller.init(role: 'viewer');

    expect(service.loadLogsCalls, 0);
    expect(service.loadAuditLogsCalls, 0);
    controller.dispose();
  });

  test('admin initialization loads transactions and audit logs', () async {
    final service = FakeInventoryService();
    final controller = InventoryController(inventoryService: service);

    await controller.init(role: 'admin');

    expect(service.loadLogsCalls, 1);
    expect(service.loadAuditLogsCalls, 1);
    controller.dispose();
  });

  test('viewer cannot invoke privileged controller mutations', () async {
    final service = FakeInventoryService();
    final controller = InventoryController(inventoryService: service);
    await controller.init(role: 'viewer');

    expect(
      await controller.addFactory(
        name: 'Factory',
        location: 'Location',
        materials: const [],
      ),
      isFalse,
    );
    expect(controller.factories, isEmpty);
    controller.dispose();
  });

  test('collection envelopes are followed through all cursors', () async {
    final cursors = <String?>[];
    final api = ApiClient(
      httpClient: MockClient((request) async {
        cursors.add(request.url.queryParameters['cursor']);
        final secondPage = request.url.queryParameters['cursor'] == 'next';
        return http.Response(
          jsonEncode({
            'data': [secondPage ? 2 : 1],
            'page': {
              'limit': 100,
              'nextCursor': secondPage ? null : 'next',
              'hasMore': !secondPage,
            },
            'meta': {'requestId': 'request-id'},
          }),
          200,
        );
      }),
    );

    expect(await api.getAll('/inventory'), [1, 2]);
    expect(cursors, [null, 'next']);
  });

  test('error envelopes expose only the API message', () async {
    final api = ApiClient(
      httpClient: MockClient(
        (_) async => http.Response(
          jsonEncode({
            'error': {
              'code': 'VALIDATION_ERROR',
              'message': 'Correct the highlighted fields.',
              'details': [
                {
                  'field': 'items[0].quantityChange',
                  'code': 'OUT_OF_RANGE',
                  'message': 'Quantity is invalid.',
                },
              ],
              'retryable': false,
            },
            'meta': {'requestId': 'request-id'},
          }),
          422,
        ),
      ),
    );

    await expectLater(
      api.get('/inventory'),
      throwsA(
        isA<ApiException>()
            .having((error) => error.code, 'code', 'VALIDATION_ERROR')
            .having(
              (error) => error.message,
              'message',
              'Correct the highlighted fields.',
            )
            .having((error) => error.statusCode, 'status', 422)
            .having((error) => error.retryable, 'retryable', false)
            .having((error) => error.requestId, 'requestId', 'request-id')
            .having((error) => error.details.single.field, 'detail field',
                'items[0].quantityChange')
            .having((error) => error.details.single.code, 'detail code',
                'OUT_OF_RANGE')
            .having((error) => error.details.single.message, 'detail message',
                'Quantity is invalid.'),
      ),
    );
  });

  test('auth retry reuses mutation idempotency key', () async {
    final keys = <String?>[];
    var calls = 0;
    final api = ApiClient(
      httpClient: MockClient((request) async {
        keys.add(request.headers['Idempotency-Key']);
        calls++;
        if (calls == 1) {
          return http.Response(
            jsonEncode({
              'error': {
                'code': 'TOKEN_EXPIRED',
                'message': 'Expired',
                'retryable': false,
              },
              'meta': {'requestId': 'request-id'},
            }),
            401,
          );
        }
        return http.Response(
          jsonEncode({
            'data': {'id': 'resource-id'},
            'meta': {'requestId': 'request-id'},
          }),
          201,
        );
      }),
    );
    api.refreshAccessToken = () async {
      api.accessToken = 'new-access-token';
      return true;
    };

    await api.sendJson('POST', '/inventory', body: {'id': 'T-1'});
    expect(keys, hasLength(2));
    expect(keys.first, isNotNull);
    expect(keys.last, keys.first);
  });

  test('retryable transport failures retain a mutation idempotency key',
      () async {
    final keys = <String?>[];
    var calls = 0;
    final api = ApiClient(
      httpClient: MockClient((request) async {
        keys.add(request.headers['Idempotency-Key']);
        calls++;
        if (calls == 1) throw http.ClientException('offline');
        return http.Response(
          jsonEncode({
            'data': {'id': 'resource-id'},
            'meta': {'requestId': 'request-id'},
          }),
          201,
        );
      }),
    );

    await expectLater(
      api.sendJson('POST', '/inventory', body: {'id': 'T-RETRY'}),
      throwsA(isA<ApiException>()),
    );
    await api.sendJson('POST', '/inventory', body: {'id': 'T-RETRY'});

    expect(keys, hasLength(2));
    expect(keys.first, keys.last);
  });

  test('non-expired unauthorized responses are not replayed', () async {
    var calls = 0;
    var refreshes = 0;
    final api = ApiClient(
      httpClient: MockClient((_) async {
        calls++;
        return http.Response(
          jsonEncode({
            'error': {
              'code': 'UNAUTHORIZED',
              'message': 'Not authorized',
              'retryable': false,
            },
            'meta': {'requestId': 'request-id'},
          }),
          401,
        );
      }),
    );
    api.refreshAccessToken = () async {
      refreshes++;
      return true;
    };

    await expectLater(api.get('/inventory'), throwsA(isA<ApiException>()));
    expect(calls, 1);
    expect(refreshes, 0);
  });

  test('state changes send If-Match and omit an empty reason', () async {
    http.Request? captured;
    final api = ApiClient(
      httpClient: MockClient((request) async {
        captured = request;
        return http.Response(
          jsonEncode({
            'data': {
              'id': 'request-uuid',
              'viewerId': 'viewer-uuid',
              'viewerAccountId': 'VW-1',
              'viewerName': 'Viewer',
              'itemId': 'T-1',
              'itemName': 'Material',
              'quantity': 1,
              'section': 'DEPOT',
              'status': 'PENDING',
              'history': [],
              'createdAt': '2026-09-01T10:00:00.000Z',
              'version': 8,
            },
            'meta': {'requestId': 'request-id'},
          }),
          200,
        );
      }),
    );

    await RequestService(api: api).decide(
      'request-uuid',
      'undo',
      7,
      reason: '   ',
    );

    expect(captured!.headers['If-Match'], '"7"');
    expect(captured!.headers['Idempotency-Key'], isNotEmpty);
    expect(jsonDecode(captured!.body), <String, dynamic>{});
  });

  test('optional reasons are trimmed when included', () async {
    http.Request? captured;
    final api = ApiClient(
      httpClient: MockClient((request) async {
        captured = request;
        return http.Response(
          jsonEncode({
            'data': {
              'id': 'request-uuid',
              'viewerId': 'viewer-uuid',
              'viewerAccountId': 'VW-1',
              'viewerName': 'Viewer',
              'itemId': 'T-1',
              'itemName': 'Material',
              'quantity': 1,
              'section': 'DEPOT',
              'status': 'REJECTED',
              'history': [],
              'createdAt': '2026-09-01T10:00:00.000Z',
              'version': 2,
            },
            'meta': {'requestId': 'request-id'},
          }),
          200,
        );
      }),
    );

    await RequestService(api: api)
        .decide('request-uuid', 'reject', 1, reason: '  damaged  ');

    expect(jsonDecode(captured!.body), {'reason': 'damaged'});
  });

  test('file content retrieval is authenticated', () async {
    http.Request? captured;
    final api = ApiClient(
      httpClient: MockClient((request) async {
        captured = request;
        return http.Response.bytes([1, 2, 3], 200);
      }),
    )..accessToken = 'access-token';

    expect(await api.downloadFile('file-uuid'), [1, 2, 3]);
    expect(captured!.url.path, '/api/v1/files/file-uuid/content');
    expect(captured!.headers['Authorization'], 'Bearer access-token');
  });

  test('invalid transaction type and scope are rejected', () {
    Map<String, dynamic> resource(
            {required String type, required String scope}) =>
        {
          'id': 'transaction-uuid',
          'type': type,
          'scope': scope,
          'items': const [],
          'createdBy': {'name': 'Admin'},
          'createdAt': '2026-09-02T10:00:00.000Z',
          'updatedAt': '2026-09-02T10:00:00.000Z',
          'version': 1,
        };

    expect(
      () => TransactionLog.fromApi(resource(type: 'OTHER', scope: 'DEPOT')),
      throwsFormatException,
    );
    expect(
      () => TransactionLog.fromApi(resource(type: 'INCOMING', scope: 'OTHER')),
      throwsFormatException,
    );
  });

  test('canonical proof responses take precedence over legacy singular fields',
      () {
    Map<String, dynamic> transaction(Map<String, dynamic> proofs) => {
          'id': 'transaction-id',
          'type': 'INCOMING',
          'scope': 'DEPOT',
          'items': const [],
          'createdBy': {'name': 'Admin'},
          'createdAt': '2026-09-02T10:00:00.000Z',
          'version': 1,
          'proofFileId': 'legacy-id',
          'proofFile': {
            'id': 'legacy-id',
            'fileName': 'legacy.jpg',
          },
          ...proofs,
        };

    final canonical = TransactionLog.fromApi(transaction({
      'proofFileIds': ['proof-1', 'proof-2'],
      'proofFiles': [
        {'id': 'proof-1', 'fileName': 'first.jpg'},
        {'id': 'proof-2', 'fileName': 'second.jpg'},
      ],
    }));
    expect(canonical.proofFileIds, ['proof-1', 'proof-2']);
    expect(
        canonical.proofs.map((proof) => proof.fileId), ['proof-1', 'proof-2']);
    expect(canonical.proofFileId, isNull);
    expect(canonical.proof, isNull);

    final explicitlyEmpty = TransactionLog.fromApi(transaction({
      'proofFileIds': const [],
      'proofFiles': const [],
    }));
    expect(explicitlyEmpty.proofFileIds, isEmpty);
    expect(explicitlyEmpty.proofs, isEmpty);
    expect(explicitlyEmpty.proofFileId, isNull);

    final legacy = TransactionLog.fromApi(transaction(const {}));
    expect(legacy.proofFileId, 'legacy-id');
    expect(legacy.proofs.single.fileId, 'legacy-id');
  });

  test('request creation serializes explicit Depot and Sleeper scope',
      () async {
    final bodies = <Map<String, dynamic>>[];
    final service = RequestService(
      api: ApiClient(
        httpClient: MockClient((request) async {
          bodies.add(jsonDecode(request.body) as Map<String, dynamic>);
          return http.Response(
            jsonEncode({
              'data': {
                'id': 'request-id',
                'viewerId': 'viewer-id',
                'viewerName': 'Viewer',
                'itemId': 'T-1',
                'itemName': 'Material',
                'quantity': 1,
                'section': bodies.last['module'],
                'createdAt': '2026-09-02T10:00:00.000Z',
              },
              'meta': {},
            }),
            201,
          );
        }),
      ),
    );

    await service.addRequest(
      viewerId: 'viewer-id',
      viewerName: 'Viewer',
      itemId: 'T-1',
      itemName: 'Material',
      quantity: 1,
    );
    await service.addRequest(
      viewerId: 'viewer-id',
      viewerName: 'Viewer',
      itemId: 'T-1',
      itemName: 'Material',
      quantity: 1,
      factoryId: 'factory-id',
    );

    expect(bodies[0]['module'], 'DEPOT');
    expect(bodies[0]['factoryId'], isNull);
    expect(bodies[1]['module'], 'SLEEPER');
    expect(bodies[1]['factoryId'], 'factory-id');
  });

  test('dispatch uploads typed files and omits incoming-only fields', () async {
    final client = _TransactionClient();
    final api = ApiClient(httpClient: client)..accessToken = 'access-token';
    final service = InventoryService(api: api);

    await service.createTransaction(
      type: 'DISPATCH',
      scope: 'FACTORY',
      factoryId: 'factory-uuid',
      items: const [
        CartItem(id: 'T-1', name: 'Material', quantityChange: 10),
      ],
      billBytes: Uint8List.fromList('%PDF-1.7'.codeUnits),
      billName: 'bill.pdf',
      proofBytes: Uint8List.fromList(
        [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a],
      ),
      proofName: 'proof.png',
      person: 'Engineering Team',
      dateRequested: '2026-09-01',
      dateLeaving: '2026-09-02',
      truckNumber: 'KA01AB1234',
    );

    expect(client.uploadPurposes, ['BILL', 'PROOF']);
    final body = client.transactionBody!;
    expect(body['type'], 'DISPATCH');
    expect(body['scope'], 'FACTORY');
    expect(body['factoryId'], 'factory-uuid');
    expect(body['person'], 'Engineering Team');
    expect(body['dateRequested'], '2026-09-01');
    expect(body['dateLeaving'], '2026-09-02');
    expect(body.containsKey('comingFrom'), isFalse);
    expect(body.containsKey('dateOfArrival'), isFalse);
    expect(body['billFileId'], 'bill-id');
    expect(body['proofFileIds'], ['proof-1-id']);
    expect(body.containsKey('proofFileId'), isFalse);
    expect((body['items'] as List).single['quantityChange'], 10);
  });

  test('incoming omits dispatch-only fields', () async {
    final client = _TransactionClient();
    final service = InventoryService(api: ApiClient(httpClient: client));

    await service.createTransaction(
      type: 'INCOMING',
      scope: 'DEPOT',
      factoryId: null,
      items: const [
        CartItem(id: 'T-1', name: 'Material', quantityChange: 5),
      ],
      billBytes: Uint8List.fromList('%PDF-1.7'.codeUnits),
      billName: 'bill.pdf',
      proofBytes: Uint8List.fromList([0xff, 0xd8, 0xff]),
      proofName: 'proof.jpg',
      person: 'Supplier',
      comingFrom: 'Delhi',
      dateOfArrival: '2026-09-02',
      truckNumber: 'KA01AB1234',
    );

    final body = client.transactionBody!;
    expect(body['type'], 'INCOMING');
    expect(body['scope'], 'DEPOT');
    expect(body.containsKey('factoryId'), isFalse);
    expect(body['comingFrom'], 'Delhi');
    expect(body['dateOfArrival'], '2026-09-02');
    expect(body.containsKey('dateRequested'), isFalse);
    expect(body.containsKey('dateLeaving'), isFalse);
  });

  test('transaction corrections omit fields for the other type', () async {
    final client = _TransactionClient();
    final service = InventoryService(api: ApiClient(httpClient: client));
    final transaction = TransactionLog(
      id: 'transaction-uuid',
      timestamp: DateTime.utc(2026, 9, 2),
      type: LogType.dispatch,
      user: 'Admin',
      items: const [
        CartItem(id: 'T-1', name: 'Material', quantityChange: 2),
      ],
      person: 'Engineering Team',
      dateRequested: '2026-09-01',
      dateLeaving: '2026-09-02',
      truckNumber: 'KA01AB1234',
      billFileId: 'bill-id',
      proofFileIds: const ['proof-id'],
      version: 4,
    );

    await service.correctTransaction(transaction, transaction.items, '  ');

    expect(client.transactionBody!.containsKey('comingFrom'), isFalse);
    expect(client.transactionBody!.containsKey('dateOfArrival'), isFalse);
    expect(client.transactionBody!.containsKey('reason'), isFalse);
    expect(client.transactionBody!.containsKey('proofFileIds'), isFalse);
    expect(client.transactionBody!.containsKey('proofFileId'), isFalse);
  });

  test('create preserves every selected proof in canonical order', () async {
    final client = _TransactionClient();
    final service = InventoryService(api: ApiClient(httpClient: client));

    await service.createTransaction(
      type: 'INCOMING',
      scope: 'DEPOT',
      factoryId: null,
      items: const [
        CartItem(id: 'T-1', name: 'Material', quantityChange: 5),
      ],
      billBytes: Uint8List.fromList('%PDF-1.7'.codeUnits),
      billName: 'bill.pdf',
      proofs: [
        TransactionAttachment(
          fileName: 'first.jpg',
          bytes: Uint8List.fromList([0xff, 0xd8, 0xff]),
        ),
        TransactionAttachment(
          fileName: 'second.png',
          bytes: Uint8List.fromList(
            [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a],
          ),
        ),
      ],
      sourceRequestIds: const ['request-1', 'request-2'],
      person: 'Supplier',
      comingFrom: 'Delhi',
      dateOfArrival: '2026-09-02',
      truckNumber: 'KA01AB1234',
    );

    expect(
        client.transactionBody!['proofFileIds'], ['proof-1-id', 'proof-2-id']);
    expect(client.transactionBody!['sourceRequestIds'],
        ['request-1', 'request-2']);
    expect(client.transactionBody!.containsKey('proofFileId'), isFalse);
  });

  test('correction supports multiple, empty, and omitted proof updates',
      () async {
    final client = _TransactionClient();
    final service = InventoryService(api: ApiClient(httpClient: client));
    final transaction = TransactionLog(
      id: 'transaction-uuid',
      timestamp: DateTime.utc(2026, 9, 2),
      type: LogType.dispatch,
      user: 'Admin',
      items: const [
        CartItem(id: 'T-1', name: 'Material', quantityChange: 2),
      ],
      person: 'Engineering Team',
      dateRequested: '2026-09-01',
      dateLeaving: '2026-09-02',
      truckNumber: 'KA01AB1234',
      billFileId: 'bill-id',
      proofFileIds: const ['existing-1', 'existing-2'],
      version: 4,
    );

    await service.correctTransaction(
      transaction,
      transaction.items,
      null,
      proofs: [
        const TransactionAttachment(
          fileName: 'existing-1.jpg',
          fileId: 'existing-1',
        ),
        TransactionAttachment(
          fileName: 'new.jpg',
          bytes: Uint8List.fromList([0xff, 0xd8, 0xff]),
        ),
        const TransactionAttachment(
          fileName: 'existing-2.jpg',
          fileId: 'existing-2',
        ),
      ],
    );
    expect(client.transactionBody!['proofFileIds'],
        ['existing-1', 'proof-1-id', 'existing-2']);

    await service.correctTransaction(
      transaction,
      transaction.items,
      null,
      proofs: const [],
    );
    expect(client.transactionBody!.containsKey('proofFileIds'), isTrue);
    expect(client.transactionBody!['proofFileIds'], isEmpty);

    await service.correctTransaction(transaction, transaction.items, null);
    expect(client.transactionBody!.containsKey('proofFileIds'), isFalse);
    expect(client.transactionBody!.containsKey('proofFileId'), isFalse);
  });

  test('transaction payload validation enforces proof and bill requirements',
      () async {
    final client = _TransactionClient();
    final service = InventoryService(api: ApiClient(httpClient: client));
    final proofs = List.generate(
      11,
      (index) => TransactionAttachment(
        fileName: 'proof-$index.jpg',
        bytes: Uint8List.fromList([0xff, 0xd8, 0xff]),
      ),
    );

    await expectLater(
      service.createTransaction(
        type: 'INCOMING',
        scope: 'DEPOT',
        factoryId: null,
        items: const [
          CartItem(id: 'T-1', name: 'Material', quantityChange: 1),
        ],
        billBytes: Uint8List.fromList('%PDF-1.7'.codeUnits),
        billName: 'bill.pdf',
        proofs: proofs,
        person: 'Supplier',
        comingFrom: 'Delhi',
        dateOfArrival: '2026-09-02',
        truckNumber: 'KA01AB1234',
      ),
      throwsA(isA<ApiException>()),
    );
    expect(client.uploadPurposes, isEmpty);

    final missingBill = TransactionLog(
      id: 'transaction-uuid',
      timestamp: DateTime.utc(2026, 9, 2),
      type: LogType.dispatch,
      user: 'Admin',
      items: const [
        CartItem(id: 'T-1', name: 'Material', quantityChange: 2),
      ],
      person: 'Engineering Team',
      dateRequested: '2026-09-01',
      dateLeaving: '2026-09-02',
      truckNumber: 'KA01AB1234',
    );
    await expectLater(
      service.correctTransaction(missingBill, missingBill.items, null),
      throwsA(isA<ApiException>()),
    );
    expect(client.transactionBody, isNull);
  });

  test('transaction item validation rejects invalid API integers', () async {
    final service = InventoryService(
      api: ApiClient(
          httpClient: MockClient((_) async => http.Response('', 500))),
    );

    for (final quantity in [0, -1, 2147483648]) {
      await expectLater(
        _createDepotIncoming(service, [
          CartItem(id: 'T-1', name: 'Material', quantityChange: quantity),
        ]),
        throwsA(isA<ApiException>()),
      );
    }
    await expectLater(
      _createDepotIncoming(service, const [
        CartItem(id: 'T-1', name: 'Material', quantityChange: 1),
        CartItem(id: 'T-1', name: 'Material', quantityChange: 2),
      ]),
      throwsA(isA<ApiException>()),
    );
    await expectLater(
      _createDepotIncoming(
        service,
        List.generate(
          101,
          (index) => CartItem(
            id: 'T-$index',
            name: 'Material $index',
            quantityChange: 1,
          ),
        ),
      ),
      throwsA(isA<ApiException>()),
    );
  });

  test('unsupported and oversized uploads fail before HTTP', () async {
    var calls = 0;
    final api = ApiClient(
      httpClient: MockClient((_) async {
        calls++;
        return http.Response('', 500);
      }),
    );

    await expectLater(
      api.uploadFile(
        purpose: 'BILL',
        fileName: 'bill.gif',
        bytes: Uint8List.fromList([0x47, 0x49, 0x46]),
      ),
      throwsA(isA<ApiException>()),
    );
    await expectLater(
      api.uploadFile(
        purpose: 'PROOF',
        fileName: 'proof.jpg',
        bytes: Uint8List(10 * 1024 * 1024 + 1),
      ),
      throwsA(isA<ApiException>()),
    );
    expect(calls, 0);
  });

  test('audit model preserves actor snapshots and complete file metadata', () {
    final log = AuditLog.fromJson({
      'id': 'log-uuid',
      'eventType': 'TRANSACTION_CORRECTED',
      'entityType': 'TRANSACTION',
      'entityId': 'transaction-uuid',
      'actor': {
        'id': 'actor-uuid',
        'accountId': 'SA-1',
        'name': 'Superadmin',
        'role': 'SUPERADMIN',
      },
      'occurredAt': '2026-09-02T10:00:00.000Z',
      'requestId': 'request-id',
      'reason': 'Corrected count',
      'before': {'quantityChange': 1},
      'after': {'quantityChange': 2},
      'billFile': {
        'id': 'bill-id',
        'purpose': 'BILL',
        'fileName': 'bill.pdf',
        'contentType': 'application/pdf',
        'sizeBytes': 42,
        'sha256': 'hash',
        'status': 'READY',
        'createdBy': {'id': 'actor-uuid'},
        'createdAt': '2026-09-02T09:00:00.000Z',
        'referenced': true,
        'version': 3,
      },
    });

    expect(log.actor.accountId, 'SA-1');
    expect(log.actor.role, 'SUPERADMIN');
    expect(log.entityId, 'transaction-uuid');
    expect(log.requestId, 'request-id');
    expect(log.reason, 'Corrected count');
    expect(log.before, {'quantityChange': 1});
    expect(log.after, {'quantityChange': 2});
    expect(log.billFile!.purpose, 'BILL');
    expect(log.billFile!.sizeBytes, 42);
    expect(log.billFile!.sha256, 'hash');
    expect(log.billFile!.status, 'READY');
    expect(log.billFile!.createdBy, {'id': 'actor-uuid'});
    expect(log.billFile!.createdAt, DateTime.utc(2026, 9, 2, 9));
    expect(log.billFile!.referenced, isTrue);
    expect(log.billFile!.version, 3);
  });

  test('optional factory failure preserves loaded inventory', () async {
    final controller = InventoryController(
      inventoryService: _PartiallyFailingLoadService(),
    );

    await controller.init(role: 'viewer');

    expect(controller.inventory.single.id, 'T-1');
    expect(controller.factories, isEmpty);
    expect(controller.lastErrorMessage, 'Factories unavailable');
    controller.dispose();
  });

  test('failed search hit rolls back its optimistic update', () async {
    final service = _FailingSearchService();
    final controller = InventoryController(inventoryService: service);
    await controller.init(role: 'viewer');

    final registration = controller.registerSearch(['T-1']);
    expect(controller.inventory.single.searchFrequency, 1);
    expect(controller.inventory.single.lastSearchedAt, isNotNull);

    service.fail.complete();
    expect(await registration, isFalse);
    expect(controller.inventory.single.searchFrequency, 0);
    expect(controller.inventory.single.lastSearchedAt, isNull);
    controller.dispose();
  });

  test('partial factory creation keeps the confirmed server resource',
      () async {
    final controller = InventoryController(
      inventoryService: _PartialFactoryService(),
    );
    await controller.init(role: 'admin');

    final created = await controller.addFactory(
      name: 'Factory One',
      location: 'Delhi',
      materials: const [
        FactoryMaterial(id: 'T-1', name: 'Material', total: 5),
      ],
    );

    expect(created, isTrue);
    expect(controller.factories.single.id, 'factory-uuid');
    expect(controller.factories.single.materials, isEmpty);
    expect(controller.lastErrorMessage, contains('material T-1 failed'));
    controller.dispose();
  });

  test('accept refreshes authoritative inventory and notifies listeners',
      () async {
    final inventoryService = _RequestDecisionInventoryService([
      _serverInventory(quantity: 70, biIssued: 0, available: 70, version: 1),
      _serverInventory(quantity: 70, biIssued: 20, available: 50, version: 2),
    ]);
    final requestService = _DecisionRequestService(
      _viewerRequest(status: 'Pending', version: 1),
    );
    final controller = InventoryController(
      inventoryService: inventoryService,
      requestService: requestService,
    );
    await controller.init(role: 'admin');
    var notifications = 0;
    controller.addListener(() => notifications++);

    final result = await controller.acceptRequest(
      requestId: 'request-uuid',
      user: 'admin',
      role: 'admin',
    );

    expect(result, RequestDecision.accepted);
    expect(inventoryService.loadInventoryCalls, 2);
    expect(requestService.decisions, ['accept']);
    expect(controller.inventory.single.quantity, 70);
    expect(controller.inventory.single.biIssued, 20);
    expect(controller.inventory.single.available, 50);
    expect(controller.inventory.single.status, 'AVAILABLE');
    expect(controller.inventory.single.version, 2);
    expect(notifications, greaterThan(0));
    controller.dispose();
  });

  test('undo refreshes authoritative restored inventory', () async {
    final inventoryService = _RequestDecisionInventoryService([
      _serverInventory(quantity: 70, biIssued: 20, available: 50, version: 2),
      _serverInventory(quantity: 70, biIssued: 0, available: 70, version: 3),
    ]);
    final requestService = _DecisionRequestService(
      _viewerRequest(status: 'Accepted', version: 2),
    );
    final controller = InventoryController(
      inventoryService: inventoryService,
      requestService: requestService,
    );
    await controller.init(role: 'superadmin');

    final result = await controller.undoRequest(
      requestId: 'request-uuid',
      user: 'superadmin',
      role: 'superadmin',
    );

    expect(result, RequestDecision.undone);
    expect(inventoryService.loadInventoryCalls, 2);
    expect(requestService.decisions, ['undo']);
    expect(controller.inventory.single.quantity, 70);
    expect(controller.inventory.single.biIssued, 0);
    expect(controller.inventory.single.available, 70);
    expect(controller.inventory.single.status, 'AVAILABLE');
    expect(controller.inventory.single.version, 3);
    controller.dispose();
  });
}

Future<TransactionLog> _createDepotIncoming(
  InventoryService service,
  List<CartItem> items,
) {
  return service.createTransaction(
    type: 'INCOMING',
    scope: 'DEPOT',
    factoryId: null,
    items: items,
    billBytes: Uint8List.fromList('%PDF-1.7'.codeUnits),
    billName: 'bill.pdf',
    proofBytes: Uint8List.fromList([0xff, 0xd8, 0xff]),
    proofName: 'proof.jpg',
    person: 'Supplier',
    comingFrom: 'Delhi',
    dateOfArrival: '2026-09-02',
    truckNumber: 'KA01AB1234',
  );
}

const _inventoryItem = InventoryItem(
  id: 'T-1',
  name: 'Material',
  quantity: 5,
  section: InventorySection.depot,
);

InventoryItem _serverInventory({
  required int quantity,
  required int biIssued,
  required int available,
  required int version,
}) {
  return InventoryItem.fromJson({
    'id': 'T-70',
    'name': 'Requested Material',
    'quantity': quantity,
    'biIssued': biIssued,
    'available': available,
    'status': available == 0 ? 'UNAVAILABLE' : 'AVAILABLE',
    'section': 'DEPOT',
    'version': version,
  });
}

ViewerRequest _viewerRequest({required String status, required int version}) {
  return ViewerRequest(
    id: 'request-uuid',
    viewerId: 'viewer-uuid',
    viewerName: 'Viewer',
    itemId: 'T-70',
    itemName: 'Requested Material',
    quantity: 20,
    createdAt: DateTime.utc(2026, 9, 10),
    status: status,
    version: version,
  );
}

class _RequestDecisionInventoryService extends InventoryService {
  _RequestDecisionInventoryService(this.responses);

  final List<InventoryItem> responses;
  int loadInventoryCalls = 0;

  @override
  Future<List<InventoryItem>> loadInventory() async {
    final index = loadInventoryCalls.clamp(0, responses.length - 1);
    loadInventoryCalls++;
    return [responses[index]];
  }

  @override
  Future<List<WarehouseFactory>> loadFactories() async => [];
}

class _DecisionRequestService extends RequestService {
  _DecisionRequestService(this.request);

  ViewerRequest request;
  final List<String> decisions = [];

  @override
  Future<List<ViewerRequest>> loadRequests() async => [request];

  @override
  Future<ViewerRequest> decide(
    String id,
    String action,
    int version, {
    String? reason,
  }) async {
    decisions.add(action);
    request = request.copyWith(
      status: action == 'undo' ? 'Pending' : 'Accepted',
      version: version + 1,
    );
    return request;
  }
}

class _PartiallyFailingLoadService extends InventoryService {
  @override
  Future<List<InventoryItem>> loadInventory() async => const [_inventoryItem];

  @override
  Future<List<WarehouseFactory>> loadFactories() async =>
      throw const ApiException('Factories unavailable', 503);
}

class _FailingSearchService extends InventoryService {
  final Completer<void> fail = Completer<void>();

  @override
  Future<List<InventoryItem>> loadInventory() async => const [_inventoryItem];

  @override
  Future<List<WarehouseFactory>> loadFactories() async => [];

  @override
  Future<List<SearchHitUpdate>> registerSearch(List<String> ids) async {
    await fail.future;
    throw const ApiException('Search unavailable', 503);
  }
}

class _PartialFactoryService extends InventoryService {
  @override
  Future<List<InventoryItem>> loadInventory() async => [];

  @override
  Future<List<WarehouseFactory>> loadFactories() async => [];

  @override
  Future<WarehouseFactory> createFactory(String name, String location) async =>
      WarehouseFactory(id: 'factory-uuid', name: name, location: location);

  @override
  Future<FactoryMaterial> createFactoryMaterial(
    String factoryId,
    Map<String, dynamic> body,
  ) async =>
      throw const ApiException('Material unavailable', 503);

  @override
  Future<List<FactoryMaterial>> loadFactoryMaterials(String factoryId) async =>
      [];
}

class _TransactionClient extends http.BaseClient {
  final List<String> uploadPurposes = [];
  Map<String, dynamic>? transactionBody;
  int _proofUploads = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (request is http.MultipartRequest) {
      final purpose = request.fields['purpose']!;
      uploadPurposes.add(purpose);
      final id = purpose == 'BILL' ? 'bill-id' : 'proof-${++_proofUploads}-id';
      return _jsonResponse({
        'data': {'id': id},
        'meta': {}
      });
    }

    final jsonRequest = request as http.Request;
    transactionBody = jsonDecode(jsonRequest.body) as Map<String, dynamic>;
    return _jsonResponse({
      'data': {
        'id': 'transaction-uuid',
        ...transactionBody!,
        'type': transactionBody!['type'] ?? 'DISPATCH',
        'scope': transactionBody!['scope'] ?? 'DEPOT',
        'factoryNameSnapshot': null,
        'items': (transactionBody!['items'] as List)
            .map((item) => {
                  ...item as Map<String, dynamic>,
                  'materialNameSnapshot': 'Material'
                })
            .toList(),
        'createdBy': {'name': 'Admin'},
        'createdAt': '2026-09-02T10:00:00.000Z',
        'updatedAt': '2026-09-02T10:00:00.000Z',
        'version': 1,
      },
      'meta': {'requestId': 'request-id'},
    });
  }

  http.StreamedResponse _jsonResponse(Map<String, dynamic> body) {
    return http.StreamedResponse(
      Stream.value(utf8.encode(jsonEncode(body))),
      200,
      headers: {'content-type': 'application/json'},
    );
  }
}
