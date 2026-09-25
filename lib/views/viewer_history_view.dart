import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../models/viewer_request.dart';
import '../models/transaction_log.dart';
import '../services/auth_service.dart';
import '../services/api_client.dart';
import '../services/request_service.dart';
import '../theme.dart';
import '../widgets/brutal.dart';
import '../widgets/attachment_preview.dart';

const List<String> _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

String _formatDate(DateTime date) {
  final local = date.toLocal();
  return '${local.day} ${_months[local.month - 1]} ${local.year}';
}

class ViewerHistoryView extends StatefulWidget {
  final AuthSession session;
  final String? section;
  final String? factoryId;
  final RequestService? requestService;
  final VoidCallback? onLoaded;

  const ViewerHistoryView({
    super.key,
    required this.session,
    this.section,
    this.factoryId,
    this.requestService,
    this.onLoaded,
  });

  @override
  State<ViewerHistoryView> createState() => _ViewerHistoryViewState();
}

class _ViewerHistoryViewState extends State<ViewerHistoryView> {
  late final RequestService _service;
  List<ViewerRequest>? _requests;
  String? _error;

  @override
  void initState() {
    super.initState();
    _service = widget.requestService ?? RequestService();
    _load();
  }

  Future<void> _load() async {
    try {
      final all = await _service.loadRequests();
      final mine = all
          .where((r) => r.viewerId == widget.session.id)
          .where((r) => widget.section == null || r.section == widget.section)
          .where((r) =>
              widget.factoryId == null || r.factoryId == widget.factoryId)
          .toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      if (mounted) {
        setState(() => _requests = mine);
        await _service.markDecisionsSeen(
          widget.session.id,
          widget.section ?? 'Depot',
          mine,
        );
        widget.onLoaded?.call();
      }
    } on ApiException catch (error) {
      if (mounted) {
        setState(() {
          _requests = const [];
          _error = error.message;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final requests = _requests;
    if (requests == null) {
      return const Center(
        child: SizedBox(
          width: 28,
          height: 28,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    if (_error != null) {
      return Center(child: MonoLabel(_error!, color: kRed));
    }
    return MaxWidth(
      child: requests.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.inbox_outlined, size: 32, color: kGray400),
                    SizedBox(height: 16),
                    MonoLabel('No requests yet', color: kGray400),
                  ],
                ),
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: requests.length,
              itemBuilder: (context, index) {
                return _RequestHistoryCard(
                  request: requests[index],
                  downloadFile: _service.downloadFile,
                );
              },
            ),
    );
  }
}

class _RequestHistoryCard extends StatefulWidget {
  final ViewerRequest request;
  final Future<Uint8List> Function(String fileId) downloadFile;

  const _RequestHistoryCard({
    required this.request,
    required this.downloadFile,
  });

  @override
  State<_RequestHistoryCard> createState() => _RequestHistoryCardState();
}

class _RequestHistoryCardState extends State<_RequestHistoryCard> {
  bool _loadingBill = false;

  Future<void> _showBill(TransactionAttachment bill) async {
    var bytes = bill.bytes;
    final fileId = bill.fileId;
    if (bytes == null && fileId != null) {
      setState(() => _loadingBill = true);
      try {
        bytes = await widget.downloadFile(fileId);
      } on ApiException catch (error) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(error.message)),
          );
        }
        return;
      } finally {
        if (mounted) setState(() => _loadingBill = false);
      }
    }
    if (!mounted || bytes == null) return;
    await showAttachmentPreview(
      context,
      fileName: bill.fileName,
      bytes: bytes,
      contentType: bill.contentType,
    );
  }

  @override
  Widget build(BuildContext context) {
    final request = widget.request;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: kSurface,
        border: Border.all(color: kBorderDark, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  request.itemName.toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: kInk,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              MonoLabel(
                request.decisionLabel.toUpperCase(),
                size: 8,
                weight: FontWeight.w600,
                color: request.isPending
                    ? const Color(0xFFB26A00)
                    : request.status == 'Accepted'
                        ? kGreen
                        : kRed,
              ),
            ],
          ),
          const SizedBox(height: 4),
          if (request.factoryName case final factoryName?) ...[
            MonoLabel('Factory: $factoryName',
                size: 9, weight: FontWeight.w700),
            const SizedBox(height: 4),
          ],
          MonoLabel('PL/Material No.: ${request.materialNumber}', size: 9),
          const SizedBox(height: 4),
          MonoLabel('Status: ${request.status}', size: 9),
          if (request.currentRejectionReason case final reason?) ...[
            const SizedBox(height: 8),
            Text(
              'Reason: $reason',
              softWrap: true,
              style: monoStyle(size: 10, color: kInk),
            ),
          ],
          const SizedBox(height: 12),
          const MonoLabel('BILL', weight: FontWeight.w700),
          if (request.billAttachment case final bill?) ...[
            MonoLabel('Filename: ${bill.fileName}', size: 9),
            const SizedBox(height: 6),
            BrutalButton(
              label: _loadingBill ? 'LOADING...' : 'VIEW BILL',
              onPressed:
                  _loadingBill || (bill.bytes == null && bill.fileId == null)
                      ? null
                      : () => _showBill(bill),
            ),
          ] else
            const MonoLabel('Bill: Not available', size: 9, color: kGray400),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              MonoLabel(
                'Requested Quantity: ${request.quantity}',
                size: 11,
                weight: FontWeight.w700,
                color: kInk,
              ),
              MonoLabel(_formatDate(request.createdAt), size: 9),
            ],
          ),
        ],
      ),
    );
  }
}
