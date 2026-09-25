import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:warehouse_poc/theme.dart';
import 'package:warehouse_poc/widgets/attachment_preview.dart';

final _png = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=');

Widget _preview({
  required String name,
  required Uint8List? bytes,
  String? type,
}) =>
    MaterialApp(
      theme: buildTheme(),
      home: Scaffold(
        body: AttachmentPreviewDialog(
          fileName: name,
          bytes: bytes,
          contentType: type,
        ),
      ),
    );

void main() {
  testWidgets('valid two-page PDF fixture initializes the page viewer',
      (tester) async {
    final bytes = await File('test/fixtures/two_page.pdf').readAsBytes();
    await tester.pumpWidget(_preview(
      name: 'two-page.pdf',
      bytes: bytes,
      type: 'application/pdf',
    ));
    await tester.pump(const Duration(seconds: 2));

    expect(find.byType(PdfViewer), findsOneWidget);
    expect(find.byKey(const ValueKey('pdf-error')), findsNothing);
    expect(find.byType(Image), findsNothing);
  }, skip: !kIsWeb);

  testWidgets('PDF MIME type opens byte-backed PdfViewer, never Image.memory',
      (tester) async {
    await tester.pumpWidget(_preview(
      name: 'misleading.png',
      bytes: Uint8List.fromList(utf8.encode('%PDF-1.4 fixture')),
      type: 'application/pdf',
    ));

    expect(find.byType(PdfViewer), findsOneWidget);
    expect(find.byType(Image), findsNothing);
    expect(find.text('misleading.png'), findsOneWidget);
  });

  testWidgets('PNG MIME type opens zoomable image preview', (tester) async {
    await tester.pumpWidget(
        _preview(name: 'proof.pdf', bytes: _png, type: 'image/png'));

    expect(
        find.byKey(const ValueKey('attachment-image-preview')), findsOneWidget);
    expect(find.byType(InteractiveViewer), findsOneWidget);
    expect(find.byType(PdfViewer), findsNothing);
  });

  testWidgets('missing attachment displays not-found state', (tester) async {
    await tester.pumpWidget(
        _preview(name: 'missing.pdf', bytes: null, type: 'application/pdf'));

    expect(find.byKey(const ValueKey('attachment-not-found')), findsOneWidget);
    expect(find.text('ATTACHMENT WAS NOT FOUND.'), findsOneWidget);
    expect(find.byType(PdfViewer), findsNothing);
  });

  testWidgets('unsupported MIME does not use PDF or image renderer',
      (tester) async {
    await tester.pumpWidget(_preview(
      name: 'proof.png',
      bytes: Uint8List.fromList([1, 2, 3]),
      type: 'text/plain',
    ));

    expect(find.text('UNSUPPORTED ATTACHMENT TYPE.'), findsOneWidget);
    expect(find.byType(PdfViewer), findsNothing);
    expect(find.byType(Image), findsNothing);
  });

  testWidgets('Close removes the preview dialog', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(),
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () => showAttachmentPreview(context,
              fileName: 'proof.png', bytes: _png, contentType: 'image/png'),
          child: const Text('OPEN'),
        ),
      ),
    ));
    await tester.tap(find.text('OPEN'));
    await tester.pumpAndSettle();
    expect(find.byType(AttachmentPreviewDialog), findsOneWidget);
    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
    expect(find.byType(AttachmentPreviewDialog), findsNothing);
  });
}
