import 'package:flutter/material.dart';

import '../models/viewer_request.dart';
import '../services/auth_service.dart';
import '../services/request_service.dart';
import '../theme.dart';
import '../widgets/brutal.dart';

const List<String> _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

String _formatDate(DateTime date) {
  final local = date.toLocal();
  return '${local.day} ${_months[local.month - 1]} ${local.year}';
}

class ViewerHistoryView extends StatefulWidget {
  final AuthSession session;

  const ViewerHistoryView({super.key, required this.session});

  @override
  State<ViewerHistoryView> createState() => _ViewerHistoryViewState();
}

class _ViewerHistoryViewState extends State<ViewerHistoryView> {
  final RequestService _service = RequestService();
  List<ViewerRequest>? _requests;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final all = await _service.loadRequests();
    final mine = all
        .where((r) => r.viewerId == widget.session.id)
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    if (mounted) {
      setState(() => _requests = mine);
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
                return _RequestHistoryCard(request: requests[index]);
              },
            ),
    );
  }
}

class _RequestHistoryCard extends StatelessWidget {
  final ViewerRequest request;

  const _RequestHistoryCard({required this.request});

  @override
  Widget build(BuildContext context) {
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
                request.status.toUpperCase(),
                size: 8,
                weight: FontWeight.w600,
                color: kGreen,
              ),
            ],
          ),
          const SizedBox(height: 4),
          MonoLabel(request.itemId, size: 9),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              MonoLabel(
                '${request.quantity} items',
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
