import 'package:flutter/material.dart';

Future<bool> showUndoRequestDialog(
  BuildContext context, {
  required String materialName,
  required int quantity,
  required String currentDecision,
  required ValueChanged<String?> onReasonChanged,
}) async =>
    await showDialog<bool>(
      context: context,
      builder: (_) => _UndoRequestDialog(
        materialName: materialName,
        quantity: quantity,
        currentDecision: currentDecision,
        onReasonChanged: onReasonChanged,
      ),
    ) ??
    false;

class _UndoRequestDialog extends StatefulWidget {
  final String materialName;
  final int quantity;
  final String currentDecision;
  final ValueChanged<String?> onReasonChanged;

  const _UndoRequestDialog({
    required this.materialName,
    required this.quantity,
    required this.currentDecision,
    required this.onReasonChanged,
  });

  @override
  State<_UndoRequestDialog> createState() => _UndoRequestDialogState();
}

class _UndoRequestDialogState extends State<_UndoRequestDialog> {
  late final TextEditingController _reasonController;

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

  void _confirm() {
    final trimmed = _reasonController.text.trim();
    widget.onReasonChanged(trimmed.isEmpty ? null : trimmed);
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final accepted = widget.currentDecision == 'Accepted';
    return AlertDialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      title: const Text('Undo Request Decision'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${widget.quantity} x ${widget.materialName}'),
              const SizedBox(height: 8),
              Text('Current decision: ${widget.currentDecision}'),
              const SizedBox(height: 8),
              Text(accepted
                  ? 'Undo restores the issued quantity to available stock and returns this request to Pending.'
                  : 'Undo does not change stock and returns this request to Pending.'),
              const SizedBox(height: 8),
              TextField(
                key: const ValueKey('undo-reason-field'),
                controller: _reasonController,
                maxLength: 500,
                minLines: 2,
                maxLines: 4,
                decoration:
                    const InputDecoration(labelText: 'Reason (Optional)'),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        TextButton(
          key: const ValueKey('confirm-undo-request'),
          onPressed: _confirm,
          child: const Text('Undo Request'),
        ),
      ],
    );
  }
}
