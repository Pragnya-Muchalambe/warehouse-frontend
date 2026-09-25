import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

import '../theme.dart';
import 'brutal.dart';

enum AttachmentKind { pdf, image, unsupported }

AttachmentKind attachmentKind({String? contentType, required String fileName}) {
  final mime = contentType?.toLowerCase().split(';').first.trim();
  if (mime == 'application/pdf') return AttachmentKind.pdf;
  if (const {'image/jpeg', 'image/png', 'image/webp'}.contains(mime)) {
    return AttachmentKind.image;
  }
  if (mime != null && mime.isNotEmpty) return AttachmentKind.unsupported;
  final lower = fileName.toLowerCase();
  if (lower.endsWith('.pdf')) return AttachmentKind.pdf;
  if (lower.endsWith('.jpg') ||
      lower.endsWith('.jpeg') ||
      lower.endsWith('.png') ||
      lower.endsWith('.webp')) {
    return AttachmentKind.image;
  }
  return AttachmentKind.unsupported;
}

Future<void> showAttachmentPreview(
  BuildContext context, {
  required String fileName,
  required Uint8List? bytes,
  String? contentType,
}) {
  return showDialog<void>(
    context: context,
    builder: (_) => AttachmentPreviewDialog(
      fileName: fileName,
      bytes: bytes,
      contentType: contentType,
    ),
  );
}

class AttachmentPreviewDialog extends StatelessWidget {
  final String fileName;
  final Uint8List? bytes;
  final String? contentType;

  const AttachmentPreviewDialog({
    super.key,
    required this.fileName,
    required this.bytes,
    this.contentType,
  });

  @override
  Widget build(BuildContext context) {
    final data = bytes;
    final kind = attachmentKind(contentType: contentType, fileName: fileName);
    return Dialog(
      backgroundColor: kSurface,
      shape: const RoundedRectangleBorder(),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 900, maxHeight: 720),
        child: Column(
          children: [
            Container(
              width: double.infinity,
              color: kInk,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      fileName,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: monoStyle(
                          size: 11, color: kSurface, weight: FontWeight.w700),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close, color: kSurface),
                  ),
                ],
              ),
            ),
            Expanded(child: _content(kind, data)),
          ],
        ),
      ),
    );
  }

  Widget _content(AttachmentKind kind, Uint8List? data) {
    if (data == null || data.isEmpty) {
      return const _PreviewMessage(
        key: ValueKey('attachment-not-found'),
        message: 'Attachment was not found.',
      );
    }
    switch (kind) {
      case AttachmentKind.pdf:
        return PdfViewer.data(
          data,
          sourceName: fileName,
          params: const PdfViewerParams(
            loadingBannerBuilder: _pdfLoadingBanner,
            errorBannerBuilder: _pdfErrorBanner,
          ),
        );
      case AttachmentKind.image:
        return InteractiveViewer(
          minScale: 0.5,
          maxScale: 5,
          child: Center(
            child: Image.memory(
              data,
              key: const ValueKey('attachment-image-preview'),
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => const _PreviewMessage(
                message: 'Unable to display this image.',
              ),
            ),
          ),
        );
      case AttachmentKind.unsupported:
        return const _PreviewMessage(message: 'Unsupported attachment type.');
    }
  }
}

Widget _pdfLoadingBanner(
        BuildContext context, int bytesDownloaded, int? totalBytes) =>
    const Center(
      key: ValueKey('pdf-loading'),
      child: CircularProgressIndicator(strokeWidth: 2),
    );

Widget _pdfErrorBanner(BuildContext context, Object error,
        StackTrace? stackTrace, PdfDocumentRef documentRef) =>
    const _PreviewMessage(
      key: ValueKey('pdf-error'),
      message: 'The selected PDF is invalid or damaged.',
    );

class _PreviewMessage extends StatelessWidget {
  final String message;

  const _PreviewMessage({super.key, required this.message});

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: MonoLabel(message, color: kRed),
        ),
      );
}
