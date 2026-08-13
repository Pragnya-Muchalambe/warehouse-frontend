import 'package:flutter/material.dart';

import '../controllers/inventory_controller.dart';
import '../models/viewer_request.dart';
import '../services/auth_service.dart';
import '../services/request_service.dart';
import '../theme.dart';
import '../widgets/brutal.dart';

const List<String> _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

String _formatTimestamp(DateTime dt) {
  final d = dt.toLocal();
  final hh = d.hour.toString().padLeft(2, '0');
  final mm = d.minute.toString().padLeft(2, '0');
  return '${d.day} ${_months[d.month - 1]} ${d.year}, $hh:$mm';
}

/// Admin processing page for Viewer requests. Accepting a request raises BI
/// Issued on the matched depot item (Total unchanged); rejecting only records
/// the decision. Both decisions are persisted and appear in the audit trail.
class AdminRequestsView extends StatefulWidget {
  final InventoryController controller;
  final AuthSession session;

  const AdminRequestsView({
    super.key,
    required this.controller,
    required this.session,
  });

  @override
  State<AdminRequestsView> createState() => _AdminRequestsViewState();
}

class _AdminRequestsViewState extends State<AdminRequestsView> {
  final RequestService _service = RequestService();
  List<ViewerRequest> _requests = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final requests = await _service.loadRequests();
    if (mounted) {
      setState(() {
        _requests = requests;
        _loading = false;
      });
    }
  }

  Future<void> _accept(ViewerRequest request) async {
    final result = await widget.controller.acceptRequest(
      requestId: request.id,
      user: widget.session.username,
      role: widget.session.role,
    );
    if (!mounted) return;
    await _reload();
    final message = switch (result) {
      RequestDecision.accepted => 'Request accepted. Inventory updated.',
      RequestDecision.insufficientStock =>
        'Insufficient available stock for this request.',
      RequestDecision.alreadyProcessed =>
        'This request was already processed.',
      RequestDecision.rejected => 'This request was already processed.',
      RequestDecision.undone => 'This request was already processed.',
      RequestDecision.notAuthorized => 'Action not permitted.',
    };
    _showMessage(message);
  }

  Future<void> _reject(ViewerRequest request) async {
    final result = await widget.controller.rejectRequest(
      requestId: request.id,
      user: widget.session.username,
      role: widget.session.role,
    );
    if (!mounted) return;
    await _reload();
    final message = switch (result) {
      RequestDecision.rejected => 'Request rejected.',
      RequestDecision.alreadyProcessed =>
        'This request was already processed.',
      _ => 'This request was already processed.',
    };
    _showMessage(message);
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: const BoxDecoration(
            color: kSurface,
            border: Border(bottom: BorderSide(color: kBorderDark, width: 1)),
          ),
          child: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'REQUESTS',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  letterSpacing: -0.5,
                  color: kInk,
                ),
              ),
              SizedBox(height: 4),
              MonoLabel('Viewer material requests', size: 9),
            ],
          ),
        ),
        Expanded(
          child: _loading
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              : _requests.isEmpty
                  ? const Center(
                      child: MonoLabel('No requests', color: kGray400),
                    )
                  : MaxWidth(
                      child: ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: _requests.length,
                        itemBuilder: (context, index) {
                          final request = _requests[index];
                          return _RequestCard(
                            request: request,
                            onAccept: request.isPending
                                ? () => _accept(request)
                                : null,
                            onReject: request.isPending
                                ? () => _reject(request)
                                : null,
                          );
                        },
                      ),
                    ),
        ),
      ],
    );
  }
}

class _RequestCard extends StatelessWidget {
  final ViewerRequest request;
  final VoidCallback? onAccept;
  final VoidCallback? onReject;

  const _RequestCard({
    required this.request,
    this.onAccept,
    this.onReject,
  });

  Color get _statusColor {
    if (request.isPending) return const Color(0xFFB26A00);
    return request.status == 'Accepted' ? kGreen : kRed;
  }

  @override
  Widget build(BuildContext context) {
    final pending = request.isPending;
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
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
              Text(
                'Request ID: ${_shortId(request.id)}',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5,
                  color: kInk,
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: _statusColor,
                  border: Border.all(color: _statusColor),
                ),
                child: MonoLabel(
                  request.decisionLabel.toUpperCase(),
                  size: 9,
                  weight: FontWeight.w700,
                  color: kSurface,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          MonoLabel(_formatTimestamp(request.createdAt), size: 9),
          const SizedBox(height: 12),
          _RequestDetailRow(label: 'Viewer', value: request.viewerName),
          _RequestDetailRow(label: 'Viewer ID', value: request.viewerId),
          _RequestDetailRow(label: 'Material', value: request.itemName),
          _RequestDetailRow(label: 'PL Number', value: request.itemId),
          _RequestDetailRow(label: 'Quantity', value: '${request.quantity} pcs'),
          const SizedBox(height: 12),
          if (pending)
            Row(
              children: [
                Expanded(
                  child: BrutalButton(
                    label: 'ACCEPT',
                    filled: true,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    onPressed: onAccept,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: BrutalButton(
                    label: 'REJECT',
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    onPressed: onReject,
                  ),
                ),
              ],
            )
          else
            const MonoLabel(
              'Decision recorded - request cannot be processed again',
              size: 9,
              color: kGray400,
            ),
        ],
      ),
    );
  }
}

class _RequestDetailRow extends StatelessWidget {
  final String label;
  final String value;

  const _RequestDetailRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 96,
            child: MonoLabel(label, size: 9, weight: FontWeight.w600),
          ),
          Expanded(
            child: Text(
              value,
              style: monoStyle(size: 10, color: kInk),
            ),
          ),
        ],
      ),
    );
  }
}

String _shortId(String id) {
  if (id.length <= 6) return id;
  return id.substring(id.length - 6);
}
