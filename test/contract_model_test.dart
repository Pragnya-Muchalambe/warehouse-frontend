import 'package:flutter_test/flutter_test.dart';
import 'package:warehouse_poc/models/account_request.dart';
import 'package:warehouse_poc/models/viewer_request.dart';
import 'package:warehouse_poc/services/request_service.dart';

void main() {
  test('pending request counts parse provided module and factory values', () {
    final counts = PendingRequestCounts.fromJson({
      'total': 4,
      'byModule': {'DEPOT': 1, 'SLEEPER': 3},
      'byFactory': {'factory-a': 2, 'factory-b': 1},
    });

    expect(counts.total, 4);
    expect(counts.depot, 1);
    expect(counts.sleeper, 3);
    expect(counts.factory('factory-a'), 2);
    expect(counts.factory('unrelated'), 0);
  });

  test('empty module and factory maps represent zero counts', () {
    final counts = PendingRequestCounts.fromJson({
      'total': 0,
      'byModule': <String, dynamic>{},
      'byFactory': <String, dynamic>{},
    });

    expect(counts.total, 0);
    expect(counts.depot, 0);
    expect(counts.sleeper, 0);
  });

  test('DEPOT-only pending count defaults Sleeper to zero', () {
    final counts = PendingRequestCounts.fromJson({
      'total': 2,
      'byModule': {'DEPOT': 2},
      'byFactory': <String, dynamic>{},
    });

    expect(counts.depot, 2);
    expect(counts.sleeper, 0);
  });

  test('SLEEPER-only pending count defaults Depot to zero', () {
    final counts = PendingRequestCounts.fromJson({
      'total': 3,
      'byModule': {'SLEEPER': 3},
      'byFactory': {'factory-a': 3},
    });

    expect(counts.depot, 0);
    expect(counts.sleeper, 3);
    expect(counts.factory('factory-a'), 3);
  });

  test('factory-filtered pending count accepts a sparse module map', () {
    final counts = PendingRequestCounts.fromJson({
      'total': 1,
      'byModule': {'SLEEPER': 1},
      'byFactory': {'factory-id': 1},
    });

    expect(counts.total, 1);
    expect(counts.factory('factory-id'), 1);
  });

  test('negative pending counts are rejected', () {
    for (final value in [
      {'total': -1, 'byModule': <String, dynamic>{}, 'byFactory': {}},
      {
        'total': 1,
        'byModule': {'DEPOT': -1},
        'byFactory': {}
      },
      {
        'total': 1,
        'byModule': {},
        'byFactory': {'factory': -1}
      },
    ]) {
      expect(() => PendingRequestCounts.fromJson(value), throwsFormatException);
    }
  });

  test('non-integer pending counts are rejected', () {
    for (final value in [
      {'total': '1', 'byModule': <String, dynamic>{}, 'byFactory': {}},
      {
        'total': 1,
        'byModule': {'DEPOT': 1.5},
        'byFactory': {}
      },
      {
        'total': 1,
        'byModule': {},
        'byFactory': {'factory': '1'}
      },
    ]) {
      expect(() => PendingRequestCounts.fromJson(value), throwsFormatException);
    }
  });

  test('missing pending count maps are rejected', () {
    expect(
      () => PendingRequestCounts.fromJson({'total': 0, 'byFactory': {}}),
      throwsFormatException,
    );
    expect(
      () => PendingRequestCounts.fromJson({'total': 0, 'byModule': {}}),
      throwsFormatException,
    );
  });

  test('unsupported pending-count module keys are rejected', () {
    expect(
      () => PendingRequestCounts.fromJson({
        'total': 1,
        'byModule': {'UNKNOWN': 1},
        'byFactory': {},
      }),
      throwsFormatException,
    );
  });

  test('request timestamps reject missing, invalid, and timezone-free values',
      () {
    final valid = _requestJson();
    expect(ViewerRequest.fromJson(valid).createdAt, DateTime.utc(2026, 9, 29));

    for (final createdAt in [null, 'not-a-time', '2026-09-29T00:00:00']) {
      expect(
        () => ViewerRequest.fromJson({...valid, 'createdAt': createdAt}),
        throwsFormatException,
      );
    }
    expect(
      () => ViewerRequest.fromJson({...valid, 'decisionAt': 'invalid'}),
      throwsFormatException,
    );
    expect(
      () => ViewerRequest.fromJson({
        ...valid,
        'history': [
          {'status': 'ACCEPTED', 'actor': 'ADMIN', 'at': 'invalid'},
        ],
      }),
      throwsFormatException,
    );
  });

  test('account request timestamps reject fabricated event time', () {
    final valid = {
      'id': 'request-id',
      'name': 'Viewer',
      'requestedId': 'VW-1',
      'role': 'VIEWER',
      'submittedAt': '2026-09-29T00:00:00Z',
      'status': 'PENDING',
      'version': 1,
    };
    expect(
        AccountRequest.fromJson(valid).submittedAt, DateTime.utc(2026, 9, 29));
    expect(
      () => AccountRequest.fromJson({...valid, 'submittedAt': null}),
      throwsFormatException,
    );
    expect(
      () => AccountRequest.fromJson({...valid, 'decisionAt': 'invalid'}),
      throwsFormatException,
    );
  });
}

Map<String, dynamic> _requestJson() => {
      'id': 'request-id',
      'viewerId': 'viewer-id',
      'viewerName': 'Viewer',
      'itemId': 'material-id',
      'itemName': 'Material',
      'quantity': 1,
      'createdAt': '2026-09-29T00:00:00Z',
      'module': 'DEPOT',
      'status': 'PENDING',
      'history': [],
      'version': 1,
    };
