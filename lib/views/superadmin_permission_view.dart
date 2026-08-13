import 'package:flutter/material.dart';

import '../models/account_request.dart';
import '../services/account_request_service.dart';
import '../services/auth_service.dart';
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

/// Superadmin-only section for NEW USER account requests. Accepting creates a
/// real login account through the existing authentication architecture;
/// rejecting keeps the account unusable but visible for the record.
class SuperadminPermissionView extends StatefulWidget {
  const SuperadminPermissionView({super.key});

  @override
  State<SuperadminPermissionView> createState() => _SuperadminPermissionViewState();
}

class _SuperadminPermissionViewState extends State<SuperadminPermissionView> {
  final AccountRequestService _service = AccountRequestService();
  final AuthService _authService = AuthService();
  List<AccountRequest> _requests = [];
  bool _loading = true;
  bool _busy = false;

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

  Future<void> _accept(AccountRequest request) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      // Duplicate guard: never overwrite an active account.
      final taken = await _authService.isAccountIdTaken(request.requestedId);
      if (taken) {
        _showMessage(
            'An active account with this ID already exists. Request kept pending.');
        return;
      }
      final created = await _authService.createAccount(
        name: request.name,
        id: request.requestedId,
        password: request.password,
        role: request.role,
      );
      if (!created) {
        _showMessage(
            'An active account with this ID already exists. Request kept pending.');
        return;
      }
      await _applyDecision(request, status: 'Accepted');
      _showMessage('Account created. The user can now log in.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reject(AccountRequest request) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await _applyDecision(request, status: 'Rejected');
      _showMessage('Request rejected. The user cannot log in.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _applyDecision(AccountRequest request,
      {required String status}) async {
    final all = await _service.loadRequests();
    final updated = all.map((r) {
      if (r.id != request.id) return r;
      return r.copyWith(
        status: status,
        decisionBy: 'superadmin',
        decisionAt: DateTime.now(),
      );
    }).toList();
    await _service.saveRequests(updated);
    await _reload();
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
                'PERMISSION',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  letterSpacing: -0.5,
                  color: kInk,
                ),
              ),
              SizedBox(height: 4),
              MonoLabel('New user account requests', size: 9),
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
                      child: MonoLabel('No account requests', color: kGray400),
                    )
                  : MaxWidth(
                      child: ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: _requests.length,
                        itemBuilder: (context, index) {
                          final request = _requests[index];
                          return _AccountRequestCard(
                            request: request,
                            busy: _busy,
                            onAccept: request.isPending && !_busy
                                ? () => _accept(request)
                                : null,
                            onReject: request.isPending && !_busy
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

class _AccountRequestCard extends StatelessWidget {
  final AccountRequest request;
  final bool busy;
  final VoidCallback? onAccept;
  final VoidCallback? onReject;

  const _AccountRequestCard({
    required this.request,
    required this.busy,
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
              Expanded(
                child: Text(
                  request.name.toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                    color: kInk,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: _statusColor,
                  border: Border.all(color: _statusColor),
                ),
                child: MonoLabel(
                  request.statusLabel.toUpperCase(),
                  size: 9,
                  weight: FontWeight.w700,
                  color: kSurface,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _DetailRow(label: 'ID', value: request.requestedId),
          _DetailRow(label: 'ROLE', value: request.role.toUpperCase()),
          _DetailRow(
            label: 'REQUESTED',
            value: _formatTimestamp(request.submittedAt),
          ),
          if (!pending && request.decisionAt != null) ...[
            const SizedBox(height: 6),
            _DetailRow(
              label: 'DECIDED',
              value: _formatTimestamp(request.decisionAt!),
            ),
          ],
          if (pending) ...[
            const SizedBox(height: 12),
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
            ),
          ] else ...[
            const SizedBox(height: 12),
            const MonoLabel(
              'Request processed — decision is final',
              size: 9,
              color: kGray400,
            ),
          ],
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;

  const _DetailRow({required this.label, required this.value});

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
