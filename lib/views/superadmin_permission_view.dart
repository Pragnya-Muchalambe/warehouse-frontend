import 'package:flutter/material.dart';

import '../models/account_request.dart';
import '../models/user_account.dart';
import '../services/account_request_service.dart';
import '../services/api_client.dart';
import '../services/auth_service.dart';
import '../services/user_account_service.dart';
import '../theme.dart';
import '../widgets/brutal.dart';

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
  final AuthSession session;
  final UserAccountService? userService;
  final ValueChanged<UserAccount>? onAccountDeleted;
  final VoidCallback? onRequestsChanged;
  final AccountRequestService? accountRequestService;

  const SuperadminPermissionView({
    super.key,
    required this.session,
    this.userService,
    this.onAccountDeleted,
    this.onRequestsChanged,
    this.accountRequestService,
  });

  @override
  State<SuperadminPermissionView> createState() =>
      _SuperadminPermissionViewState();
}

class _SuperadminPermissionViewState extends State<SuperadminPermissionView> {
  late final AccountRequestService _service;
  late final UserAccountService _userService;
  List<AccountRequest> _requests = [];
  List<UserAccount> _users = [];
  bool _loading = true;
  bool _busy = false;
  String? _deletingUserId;
  String? _error;

  @override
  void initState() {
    super.initState();
    _service = widget.accountRequestService ?? AccountRequestService();
    _userService = widget.userService ?? UserAccountService();
    _reload();
  }

  Future<void> _reload() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final requests = await _service.loadRequests();
      final users = await _userService.loadUsers();
      if (mounted) {
        setState(() {
          _requests = List.of(requests);
          _requests.sort((a, b) {
            final pending =
                (b.isPending ? 1 : 0).compareTo(a.isPending ? 1 : 0);
            return pending != 0
                ? pending
                : b.submittedAt.compareTo(a.submittedAt);
          });
          _users = List.of(users);
          _loading = false;
          _error = null;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Unable to load Permission data.';
        });
      }
    }
  }

  Future<void> _deleteUser(UserAccount user) async {
    if (_busy || user.id == widget.session.id) return;
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Delete Employee Account?'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Employee: ${user.name}'),
                Text('User ID: ${user.username}'),
                Text('Role: ${user.role == 'admin' ? 'Admin' : 'Viewer'}'),
                const SizedBox(height: 12),
                const Text(
                    'This account will no longer be able to sign in.\nExisting requests, transactions and Audit history will remain preserved.'),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('Delete Account'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed || !mounted) return;
    setState(() {
      _busy = true;
      _deletingUserId = user.id;
    });
    try {
      await _userService.deleteUser(user.id, user.version);
      await _reload();
      widget.onAccountDeleted?.call(user);
      widget.onRequestsChanged?.call();
      _showMessage('Account deleted. The user can no longer log in.');
    } on ApiException catch (error) {
      if (error.isVersionConflict) await _reload();
      _showMessage(error.message);
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _deletingUserId = null;
        });
      }
    }
  }

  Future<void> _showEmployeeSelector() async {
    final employees = _users
        .where((user) => user.id != widget.session.id)
        .where((user) => user.role == 'viewer' || user.role == 'admin')
        .where((user) => user.status.toUpperCase() == 'ACTIVE')
        .toList();
    final controller = TextEditingController();
    String term = '';
    final selected = await showDialog<UserAccount>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          final normalized = term.trim().toLowerCase();
          final filtered = employees
              .where((user) =>
                  normalized.isEmpty ||
                  user.username.toLowerCase().contains(normalized) ||
                  user.accountId.toLowerCase().contains(normalized) ||
                  user.name.toLowerCase().contains(normalized) ||
                  user.role.toLowerCase().contains(normalized))
              .toList();
          return AlertDialog(
            title: const Text('Delete Employee Account'),
            content: SizedBox(
              width: 480,
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                TextField(
                  controller: controller,
                  decoration: const InputDecoration(
                    labelText: 'Search by User ID or name',
                    prefixIcon: Icon(Icons.search),
                  ),
                  onChanged: (value) => setDialogState(() => term = value),
                ),
                const SizedBox(height: 12),
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    children: filtered
                        .map((user) => ListTile(
                              title: Text(
                                  '${user.name} — ${user.username} — ${user.role == 'admin' ? 'Admin' : 'Viewer'}'),
                              onTap: () => Navigator.pop(dialogContext, user),
                            ))
                        .toList(),
                  ),
                ),
              ]),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Cancel'),
              )
            ],
          );
        },
      ),
    );
    controller.dispose();
    if (selected != null && mounted) await _deleteUser(selected);
  }

  Future<void> _accept(AccountRequest request) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await _service.decide(request, 'approve');
      await _reload();
      widget.onRequestsChanged?.call();
      _showMessage('Account created. The user can now log in.');
    } on ApiException catch (error) {
      if (error.isVersionConflict) await _reload();
      _showMessage(error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reject(AccountRequest request) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final decision = await _optionalReason();
      if (!decision.confirmed) return;
      await _service.decide(request, 'reject', reason: decision.reason);
      await _reload();
      widget.onRequestsChanged?.call();
      _showMessage('Request rejected. The user cannot log in.');
    } on ApiException catch (error) {
      if (error.isVersionConflict) await _reload();
      _showMessage(error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<({bool confirmed, String? reason})> _optionalReason() async {
    final controller = TextEditingController();
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Reject Request'),
            content: TextField(
              controller: controller,
              decoration: const InputDecoration(labelText: 'Reason (Optional)'),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Reject'),
              ),
            ],
          ),
        ) ??
        false;
    final reason = controller.text.trim();
    controller.dispose();
    return (confirmed: confirmed, reason: reason.isEmpty ? null : reason);
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
              : _error != null
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          MonoLabel(_error!, color: kRed),
                          const SizedBox(height: 12),
                          BrutalButton(label: 'RETRY', onPressed: _reload),
                        ],
                      ),
                    )
                  : MaxWidth(
                      child: ListView(
                        padding: const EdgeInsets.all(16),
                        children: [
                          const MonoLabel(
                            'EMPLOYEE ACCOUNTS',
                            size: 11,
                            weight: FontWeight.w700,
                          ),
                          const SizedBox(height: 10),
                          MonoLabel(
                            'Active employees: ${_users.where((user) => user.role == 'viewer' || user.role == 'admin').length}',
                          ),
                          const SizedBox(height: 10),
                          BrutalButton(
                            label: _deletingUserId == null
                                ? 'DELETE EMPLOYEE ACCOUNT'
                                : 'DELETING...',
                            onPressed:
                                widget.session.role == 'superadmin' && !_busy
                                    ? _showEmployeeSelector
                                    : null,
                          ),
                          const SizedBox(height: 12),
                          const MonoLabel(
                            'ACCOUNT REQUESTS',
                            size: 11,
                            weight: FontWeight.w700,
                          ),
                          const SizedBox(height: 10),
                          if (_requests.isEmpty)
                            const Padding(
                              padding: EdgeInsets.symmetric(vertical: 16),
                              child: MonoLabel(
                                'No pending account requests.',
                                color: kGray400,
                              ),
                            )
                          else
                            for (final request in _requests)
                              _AccountRequestCard(
                                request: request,
                                busy: _busy,
                                onAccept: request.isPending && !_busy
                                    ? () => _accept(request)
                                    : null,
                                onReject: request.isPending && !_busy
                                    ? () => _reject(request)
                                    : null,
                              ),
                        ],
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
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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
