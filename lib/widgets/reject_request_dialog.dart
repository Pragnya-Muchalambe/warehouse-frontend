import 'package:flutter/material.dart';

import '../theme.dart';

Future<bool> showRejectRequestDialog(
  BuildContext context, {
  required Future<String?> Function(String? reason) onReject,
}) async =>
    await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _RejectRequestDialog(onReject: onReject),
    ) ??
    false;

class _RejectRequestDialog extends StatefulWidget {
  final Future<String?> Function(String? reason) onReject;

  const _RejectRequestDialog({required this.onReject});

  @override
  State<_RejectRequestDialog> createState() => _RejectRequestDialogState();
}

class _RejectRequestDialogState extends State<_RejectRequestDialog> {
  late final TextEditingController _reasonController;
  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _reasonController = TextEditingController();
  }

  @override
  void dispose() {
    _reasonController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitting) return;
    final trimmed = _reasonController.text.trim();
    final reason = trimmed.isEmpty ? null : trimmed;
    setState(() {
      _submitting = true;
      _error = null;
    });

    final error = await widget.onReject(reason);
    if (!mounted) return;
    if (error == null) {
      Navigator.of(context).pop(true);
      return;
    }
    setState(() {
      _submitting = false;
      _error = error;
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      title: const Text('Reject Request'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                key: const ValueKey('rejection-reason-field'),
                controller: _reasonController,
                maxLength: 500,
                minLines: 3,
                maxLines: 5,
                enabled: !_submitting,
                decoration:
                    const InputDecoration(labelText: 'Reason (Optional)'),
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(
                  _error!,
                  key: const ValueKey('rejection-error'),
                  softWrap: true,
                  style: const TextStyle(color: kRed),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _submitting ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        TextButton(
          key: const ValueKey('confirm-rejection'),
          onPressed: _submitting ? null : _submit,
          child: Text(_submitting ? 'Rejecting...' : 'Reject'),
        ),
      ],
    );
  }
}
