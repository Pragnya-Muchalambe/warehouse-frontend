import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:warehouse_poc/models/transaction_log.dart';
import 'package:warehouse_poc/models/viewer_request.dart';
import 'package:warehouse_poc/services/auth_service.dart';
import 'package:warehouse_poc/services/request_service.dart';
import 'package:warehouse_poc/theme.dart';
import 'package:warehouse_poc/views/viewer_history_view.dart';

void main() {
  testWidgets('Viewer History displays only a current rejection reason',
      (tester) async {
    const viewer = AuthSession(
      username: 'viewer',
      role: 'viewer',
      name: 'Viewer User',
      id: 'viewer-id',
    );
    final rejected = ViewerRequest(
      id: 'rejected-request',
      viewerId: viewer.id,
      viewerName: viewer.name,
      itemId: 'item-1',
      itemName: 'Rejected Material',
      quantity: 1,
      createdAt: DateTime.utc(2026, 9, 13),
      status: 'Rejected',
      history: [
        RequestHistoryEntry(
          status: 'Rejected',
          actor: 'admin',
          at: DateTime.utc(2026, 9, 13),
          reason: '<script>alert(1)</script>\nDamaged',
        ),
      ],
    );
    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(),
      home: Scaffold(
        body: ViewerHistoryView(
          session: viewer,
          requestService: _RequestService([rejected]),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.textContaining('<script>alert(1)</script>'), findsOneWidget);
    expect(find.textContaining('Reason:'), findsOneWidget);
  });

  const session = AuthSession(
    username: 'viewer',
    role: 'viewer',
    name: 'Viewer User',
    id: 'viewer-id',
  );

  testWidgets(
      'Viewer History shows only authorized Bill previews and no proofs',
      (tester) async {
    final png = base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=');
    final requests = [
      _request(
          'pdf',
          'viewer-id',
          TransactionAttachment(
            fileName: 'invoice-001.pdf',
            bytes: Uint8List.fromList('%PDF-1.4\n%%EOF'.codeUnits),
            contentType: 'application/pdf',
          )),
      _request(
          'image',
          'viewer-id',
          TransactionAttachment(
            fileName: 'invoice-001.png',
            bytes: png,
            contentType: 'image/png',
          )),
      _request('none', 'viewer-id', null),
      _request(
          'other',
          'another-viewer',
          TransactionAttachment(
            fileName: 'private.pdf',
            bytes: Uint8List.fromList([1]),
            contentType: 'application/pdf',
          )),
    ];
    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(),
      home: Scaffold(
        body: ViewerHistoryView(
          session: session,
          section: 'Depot',
          requestService: _RequestService(requests),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('FILENAME: INVOICE-001.PDF'), findsOneWidget);
    expect(find.text('FILENAME: INVOICE-001.PNG'), findsOneWidget);
    expect(find.text('BILL: NOT AVAILABLE'), findsOneWidget);
    expect(find.textContaining('private.pdf'), findsNothing);
    expect(find.textContaining('PROOF'), findsNothing);

    await tester.tap(find.text('VIEW BILL').first);
    await tester.pump();
    expect(find.byType(PdfViewer), findsOneWidget);
    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('VIEW BILL').last);
    await tester.pump();
    expect(find.byType(Image), findsWidgets);
  });

  testWidgets('Viewer History downloads a canonical remote Bill',
      (tester) async {
    final request = ViewerRequest.fromJson({
      'id': 'remote',
      'viewerId': session.id,
      'viewerName': session.name,
      'itemId': 'T-1',
      'itemName': 'Material',
      'quantity': 1,
      'createdAt': '2026-09-13T00:00:00.000Z',
      'billAttachment': {
        'id': 'bill-id',
        'fileName': 'remote.png',
        'contentType': 'image/png',
      },
    });
    final service = _RequestService([request]);
    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(),
      home: Scaffold(
        body: ViewerHistoryView(
          session: session,
          section: 'Depot',
          requestService: service,
        ),
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('VIEW BILL'));
    await tester.pumpAndSettle();

    expect(service.downloadedFileIds, ['bill-id']);
    expect(find.byType(Image), findsWidgets);
  });
}

ViewerRequest _request(
        String id, String viewerId, TransactionAttachment? bill) =>
    ViewerRequest(
      id: id,
      viewerId: viewerId,
      viewerName: 'Viewer',
      itemId: 'material-$id',
      itemName: 'Material $id',
      quantity: 1,
      createdAt: DateTime.utc(2026),
      billAttachment: bill,
    );

class _RequestService extends RequestService {
  _RequestService(this.requests);
  final List<ViewerRequest> requests;
  final List<String> downloadedFileIds = [];

  @override
  Future<List<ViewerRequest>> loadRequests() async => requests;

  @override
  Future<Uint8List> downloadFile(String fileId) async {
    downloadedFileIds.add(fileId);
    return base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=');
  }
}
