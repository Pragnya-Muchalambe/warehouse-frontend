import 'package:flutter_test/flutter_test.dart';
import 'package:warehouse_poc/models/account_request.dart';
import 'package:warehouse_poc/models/viewer_request.dart';
import 'package:warehouse_poc/services/request_service.dart';

void main() {
  test('pending request counts parse required module and factory values', () {
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

  test('malformed pending request counts never become zero', () {
    for (final value in [
      {'total': 0, 'byModule': <String, int>{}, 'byFactory': {}},
      {
        'total': 1,
        'byModule': {'DEPOT': 1, 'SLEEPER': 0},
        'byFactory': {'factory': -1},
      },
      {
        'total': '1',
        'byModule': {'DEPOT': 1, 'SLEEPER': 0},
        'byFactory': {},
      },
    ]) {
      expect(
        () => PendingRequestCounts.fromJson(value),
        throwsFormatException,
      );
    }
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
