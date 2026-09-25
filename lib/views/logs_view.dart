import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../models/audit_log.dart';
import '../models/factory.dart';
import '../models/inventory_item.dart';
import '../models/transaction_log.dart';
import '../presentation.dart';
import '../services/api_client.dart';
import '../services/auth_service.dart';
import '../theme.dart';
import '../widgets/brutal.dart';
import '../widgets/attachment_preview.dart';

class LogsView extends StatefulWidget {
  final List<AuditLog> logs;
  final List<TransactionLog> transactions;
  final List<WarehouseFactory> factories;
  final AuthSession session;
  final Future<void> Function({
    required String logId,
    required List<CartItem> updatedItems,
    required String user,
    String? reason,
  }) editTransaction;
  final InventorySection? fixedSection;
  final Future<Uint8List> Function(String fileId)? downloadFile;

  const LogsView({
    super.key,
    required this.logs,
    required this.transactions,
    required this.factories,
    required this.session,
    required this.editTransaction,
    this.fixedSection,
    this.downloadFile,
  });

  @override
  State<LogsView> createState() => _LogsViewState();
}

class _LogsViewState extends State<LogsView> {
  InventorySection? _section;
  String? _editingTransactionId;
  List<CartItem> _editItems = [];
  final Map<String, TextEditingController> _editControllers = {};

  bool get _isSuperadmin => widget.session.role == 'superadmin';

  @override
  void initState() {
    super.initState();
    _section = widget.fixedSection ?? InventorySection.depot;
  }

  List<AuditLog> get _filteredLogs => widget.logs.where((log) {
        if (_section == null) return true;
        final transaction = _transactionFor(log);
        final expectedScope =
            _section == InventorySection.depot ? 'DEPOT' : 'FACTORY';
        final transactionScope = transaction?.section == InventorySection.depot
            ? 'DEPOT'
            : transaction?.section == InventorySection.sleeper
                ? 'FACTORY'
                : null;
        if ((log.scope ?? transactionScope) != expectedScope) return false;
        return true;
      }).toList();

  TransactionLog? _transactionFor(AuditLog log) {
    if (log.entityType != 'TRANSACTION') return null;
    return widget.transactions
        .where((transaction) => transaction.id == log.entityId)
        .firstOrNull;
  }

  void _startEdit(TransactionLog transaction) {
    final controllers = <String, TextEditingController>{};
    final items = transaction.items.map((item) => item.copyWith()).toList();
    for (final item in items) {
      controllers[item.id] =
          TextEditingController(text: '${item.quantityChange}');
    }
    setState(() {
      _editingTransactionId = transaction.id;
      _editItems = items;
      for (final controller in _editControllers.values) {
        controller.dispose();
      }
      _editControllers
        ..clear()
        ..addAll(controllers);
    });
  }

  void _cancelEdit() {
    setState(() {
      _editingTransactionId = null;
      _editItems = [];
      for (final controller in _editControllers.values) {
        controller.dispose();
      }
      _editControllers.clear();
    });
  }

  void _updateQuantity(String id, String value) {
    final quantity = int.tryParse(value);
    if (quantity == null || quantity < 1 || quantity > 2147483647) return;
    final index = _editItems.indexWhere((item) => item.id == id);
    if (index == -1) return;
    setState(() {
      _editItems[index] = _editItems[index].copyWith(quantityChange: quantity);
    });
  }

  Future<void> _saveEdit(String transactionId) async {
    final updatedItems = <CartItem>[];
    for (final item in _editItems) {
      final quantity =
          int.tryParse(_editControllers[item.id]?.text.trim() ?? '');
      if (quantity == null || quantity < 1 || quantity > 2147483647) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content:
                Text('Quantities must be whole numbers from 1 to 2147483647.'),
          ),
        );
        return;
      }
      updatedItems.add(item.copyWith(quantityChange: quantity));
    }
    final controller = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Correct Transaction'),
        content: TextField(
          controller: controller,
          maxLength: 500,
          maxLines: 3,
          decoration: const InputDecoration(labelText: 'Reason (Optional)'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('CANCEL'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            child: const Text('SAVE'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (!mounted || reason == null) return;
    try {
      await widget.editTransaction(
        logId: transactionId,
        updatedItems: updatedItems,
        user: widget.session.username,
        reason: reason.isEmpty ? null : reason,
      );
      _cancelEdit();
    } on ApiException catch (error) {
      if (!mounted) return;
      if (error.isVersionConflict) _cancelEdit();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.message)),
      );
    }
  }

  @override
  void dispose() {
    for (final controller in _editControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final logs = _filteredLogs;
    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: const BoxDecoration(
            color: kSurface,
            border: Border(bottom: BorderSide(color: kBorderDark, width: 1)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _section == InventorySection.depot
                    ? 'DEPOT AUDIT'
                    : 'SLEEPER AUDIT',
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  letterSpacing: -0.5,
                  color: kInk,
                ),
              ),
              const SizedBox(height: 4),
              const MonoLabel('Immutable Business Event History'),
            ],
          ),
        ),
        Expanded(
          child: logs.isEmpty
              ? const Center(
                  child: MonoLabel('No Audit Events', color: kGray400),
                )
              : MaxWidth(
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: logs.length,
                    itemBuilder: (context, index) {
                      final log = logs[index];
                      final transaction = _transactionFor(log);
                      final canEdit = _isSuperadmin &&
                          log.eventType == 'TRANSACTION_CREATED' &&
                          transaction != null &&
                          transaction.reversedAt == null;
                      return _AuditCard(
                        log: log,
                        transaction: transaction,
                        isEditing: transaction != null &&
                            _editingTransactionId == transaction.id,
                        editControllers: _editControllers,
                        canEdit: canEdit,
                        onStartEdit: transaction == null
                            ? null
                            : () => _startEdit(transaction),
                        onCancelEdit: _cancelEdit,
                        onUpdateQuantity: _updateQuantity,
                        onSaveEdit: transaction == null
                            ? null
                            : () => _saveEdit(transaction.id),
                        downloadFile: widget.downloadFile,
                      );
                    },
                  ),
                ),
        ),
      ],
    );
  }
}

class _AuditCard extends StatelessWidget {
  final AuditLog log;
  final TransactionLog? transaction;
  final bool isEditing;
  final Map<String, TextEditingController> editControllers;
  final bool canEdit;
  final VoidCallback? onStartEdit;
  final VoidCallback onCancelEdit;
  final void Function(String id, String value) onUpdateQuantity;
  final VoidCallback? onSaveEdit;
  final Future<Uint8List> Function(String fileId)? downloadFile;

  const _AuditCard({
    required this.log,
    required this.transaction,
    required this.isEditing,
    required this.editControllers,
    required this.canEdit,
    required this.onStartEdit,
    required this.onCancelEdit,
    required this.onUpdateQuantity,
    required this.onSaveEdit,
    this.downloadFile,
  });

  Color get _eventColor {
    final type = log.eventType;
    if (type.contains('REJECTED') ||
        type.contains('REVERSED') ||
        type.contains('DELETED')) {
      return const Color(0xFFB71C1C);
    }
    if (type.contains('CREATED') || type.contains('ACCEPTED')) {
      return const Color(0xFF1B5E20);
    }
    if (type.contains('CORRECTED') ||
        type.contains('ADJUSTED') ||
        type.contains('UPDATED')) {
      return const Color(0xFF0D47A1);
    }
    return kInkMuted;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: kSurface,
        border: Border.all(color: kBorderDark),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      log.eventType.replaceAll('_', ' '),
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.5,
                        color: _eventColor,
                      ),
                    ),
                    const SizedBox(height: 4),
                    MonoLabel(
                      '${MaterialLocalizations.of(context).formatMediumDate(log.occurredAt.toLocal())}, ${MaterialLocalizations.of(context).formatTimeOfDay(TimeOfDay.fromDateTime(log.occurredAt.toLocal()))}',
                      size: 9,
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  MonoLabel(displayName(log.actor.name),
                      size: 11, weight: FontWeight.w700),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          _DetailLine(label: 'ENTITY', value: _entityLabel),
          _DetailLine(label: 'Role', value: displayRole(log.actor.role)),
          for (final summary in _summaryLines) ...[
            const SizedBox(height: 6),
            _ActivityLine(summary),
          ],
          if (transaction != null && !isEditing) ...[
            const SizedBox(height: 10),
            MonoLabel(
              'ITEMS: ${transaction!.items.length}',
              size: 9,
              weight: FontWeight.w700,
            ),
            const SizedBox(height: 6),
            for (var index = 0; index < transaction!.items.length; index++)
              _TransactionItemDetail(
                index: index,
                item: transaction!.items[index],
              ),
          ],
          if (log.reason != null && log.reason!.isNotEmpty) ...[
            const SizedBox(height: 10),
            _ReasonBox(value: log.reason!),
          ],
          if (transaction != null && isEditing) ...[
            const SizedBox(height: 10),
            for (final item in transaction!.items)
              _TransactionItem(
                item: item,
                editing: isEditing,
                controller: editControllers[item.id],
                onChanged: (value) => onUpdateQuantity(item.id, value),
              ),
          ],
          const SizedBox(height: 12),
          const MonoLabel('BILL', weight: FontWeight.w700),
          if (transaction?.bill != null)
            _AuditInlineAttachment(
              label: 'View Bill',
              fileName: transaction!.bill!,
              bytes: transaction!.billData == null
                  ? null
                  : base64Decode(transaction!.billData!),
            )
          else if (log.billFile != null)
            _Attachment(
              label: 'View Bill',
              file: log.billFile!,
              downloadFile: downloadFile,
            )
          else
            const MonoLabel('Bill: Not available', color: kGray400),
          const SizedBox(height: 12),
          MonoLabel(
            'PROOFS (${transaction?.proofs.length ?? (log.proofFile == null ? 0 : 1)})',
            weight: FontWeight.w700,
          ),
          if (transaction != null && transaction!.proofs.isNotEmpty)
            for (final indexed in transaction!.proofs.indexed)
              _AuditInlineAttachment(
                label: 'View Proof ${indexed.$1 + 1}',
                fileName: indexed.$2.fileName,
                bytes: indexed.$2.bytes,
                contentType: indexed.$2.contentType,
              )
          else if (log.proofFile != null)
            _Attachment(
              label: 'View Proof',
              file: log.proofFile!,
              downloadFile: downloadFile,
            )
          else
            const MonoLabel('No proof attached', color: kGray400),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (canEdit)
                isEditing
                    ? Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _SmallButton(icon: Icons.close, onTap: onCancelEdit),
                          const SizedBox(width: 8),
                          _SmallButton(
                            icon: Icons.check,
                            onTap: onSaveEdit!,
                            filled: true,
                          ),
                        ],
                      )
                    : _SmallButton(
                        icon: Icons.edit_outlined, onTap: onStartEdit!),
            ],
          ),
        ],
      ),
    );
  }

  String get _entityLabel {
    final name = _text('name') ??
        _text('itemName') ??
        _text('materialNameSnapshot') ??
        _text('viewerName') ??
        _text('requestedId');
    final id = _text('id') ?? _text('itemId') ?? _text('materialId');
    if (name != null && id != null) return '$name ($id)';
    if (name != null) return name;
    return log.entityType.replaceAll('_', ' ');
  }

  List<String> get _summaryLines {
    final lines = <String>[];
    switch (log.eventType) {
      case 'INVENTORY_CREATED':
      case 'INVENTORY_UPDATED':
        _addStockChanges(lines, totalKey: 'quantity', label: 'Total');
        break;
      case 'FACTORY_MATERIAL_CREATED':
      case 'FACTORY_MATERIAL_UPDATED':
        final factory = _text('factoryNameSnapshot') ?? _text('factoryName');
        if (factory != null) {
          lines.add('Factory: $factory');
        }
        _addStockChanges(lines, totalKey: 'total', label: 'Total');
        break;
      case 'REQUEST_ACCEPTED':
      case 'REQUEST_REJECTED':
      case 'REQUEST_UNDONE':
        final requester = _text('viewerName');
        final material = _text('itemName');
        final quantity = _number('quantity');
        if (requester != null) {
          lines.add('Requester: ${displayName(requester)}');
        }
        if (material != null && quantity != null) {
          lines.add('Requested: $quantity x $material');
        } else if (material != null) {
          lines.add('Material: $material');
        }
        _addChange(lines, 'Status', 'status');
        _addStockChanges(lines, totalKey: 'quantity', label: 'Stock total');
        break;
      case 'TRANSACTION_CREATED':
      case 'TRANSACTION_CORRECTED':
        final type = _text('type');
        final scope = _text('scope');
        if (type != null) {
          lines.add('Type: $type${scope == null ? '' : ' · $scope'}');
        }
        final itemCount = _itemCount();
        if (itemCount != null) lines.add('Items: $itemCount');
        final date = _text('dateOfArrival') ??
            _text('dateLeaving') ??
            _text('dateRequested');
        if (date != null) lines.add('Date: $date');
        break;
      case 'ACCOUNT_REQUEST_APPROVED':
      case 'ACCOUNT_REQUEST_REJECTED':
        final account = _text('name') ?? _text('requestedId');
        final role = _text('role');
        final status = _text('status');
        if (account != null) lines.add('Account: $account');
        if (role != null) lines.add('Role: $role');
        if (status != null) lines.add('Status: $status');
        break;
    }
    if (log.billFile != null || log.proofFile != null) {
      final files = [
        if (log.billFile != null) 'Bill: ${log.billFile!.fileName}',
        if (log.proofFile != null) 'Proof: ${log.proofFile!.fileName}',
      ];
      lines.add(files.join(' · '));
    }
    return lines;
  }

  void _addStockChanges(
    List<String> lines, {
    required String totalKey,
    required String label,
  }) {
    _addChange(lines, label, totalKey);
    _addChange(lines, 'BI Issued', 'biIssued');
    _addChange(lines, 'Available', 'available');
    _addChange(lines, 'Status', 'status');
  }

  void _addChange(List<String> lines, String label, String key) {
    final before = _value(log.before, key);
    final after = _value(log.after, key);
    if (before != null && after != null && before != after) {
      lines.add('$label: $before → $after');
    } else if (after != null) {
      lines.add('$label: $after');
    }
  }

  String? _text(String key) {
    final value = _value(log.after, key) ?? _value(log.before, key);
    return value is String && value.isNotEmpty ? value : null;
  }

  num? _number(String key) {
    final value = _value(log.after, key) ?? _value(log.before, key);
    return value is num ? value : null;
  }

  int? _itemCount() {
    final items = _value(log.after, 'items') ?? _value(log.before, 'items');
    return items is List ? items.length : transaction?.items.length;
  }

  Object? _value(Map<String, dynamic>? snapshot, String key) => snapshot?[key];
}

class _TransactionItem extends StatelessWidget {
  final CartItem item;
  final bool editing;
  final TextEditingController? controller;
  final ValueChanged<String> onChanged;

  const _TransactionItem({
    required this.item,
    required this.editing,
    required this.controller,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(child: Text(item.name, style: monoStyle(size: 11))),
          if (editing)
            SizedBox(
              width: 72,
              child: BrutalTextInput(
                controller: controller,
                keyboardType: TextInputType.number,
                textAlign: TextAlign.center,
                minHeight: 34,
                onChanged: onChanged,
              ),
            )
          else
            MonoLabel('${item.quantityChange} pcs', weight: FontWeight.w700),
        ],
      ),
    );
  }
}

class _TransactionItemDetail extends StatelessWidget {
  final int index;
  final CartItem item;

  const _TransactionItemDetail({required this.index, required this.item});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${index + 1}. ${item.name}',
              style: monoStyle(size: 10, weight: FontWeight.w700),
            ),
            MonoLabel('PL/Material No.: ${item.materialNumber}', size: 9),
            MonoLabel('Quantity: ${item.quantityChange}', size: 9),
          ],
        ),
      );
}

class _DetailLine extends StatelessWidget {
  final String label;
  final String value;

  const _DetailLine({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 100, child: MonoLabel(label, size: 9)),
          Expanded(child: Text(value, style: monoStyle(size: 10))),
        ],
      ),
    );
  }
}

class _ActivityLine extends StatelessWidget {
  final String value;

  const _ActivityLine(this.value);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: kGray50,
        border: Border.all(color: kGray200),
      ),
      child: Text(value, style: monoStyle(size: 10)),
    );
  }
}

class _ReasonBox extends StatelessWidget {
  final String value;

  const _ReasonBox({required this.value});

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: kGray50,
          border: Border.all(color: kGray200),
        ),
        child: Text('Reason: $value', style: monoStyle(size: 10)),
      );
}

class _AuditInlineAttachment extends StatelessWidget {
  final String label;
  final String fileName;
  final Uint8List? bytes;
  final String? contentType;

  const _AuditInlineAttachment({
    required this.label,
    required this.fileName,
    required this.bytes,
    this.contentType,
  });

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: bytes == null
          ? null
          : () => showAttachmentPreview(
                context,
                fileName: fileName,
                bytes: bytes!,
                contentType: contentType,
              ),
      icon: const Icon(Icons.visibility_outlined),
      label: Text('$label: $fileName'),
    );
  }
}

class _Attachment extends StatelessWidget {
  final String label;
  final AuditFileMetadata file;
  final Future<Uint8List> Function(String fileId)? downloadFile;

  const _Attachment({
    required this.label,
    required this.file,
    this.downloadFile,
  });

  Future<void> _open(BuildContext context) async {
    try {
      final loader = downloadFile;
      if (loader == null) return;
      final bytes = await loader(file.id);
      if (!context.mounted) return;
      await showAttachmentPreview(
        context,
        fileName: file.fileName,
        bytes: bytes,
        contentType: file.contentType,
      );
    } on ApiException catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error.message)),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => _open(context),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 240),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: kPaper,
          border: Border.all(color: kBorderDark),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.visibility_outlined, size: 12, color: kInkMuted),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                '$label: ${file.fileName}',
                overflow: TextOverflow.ellipsis,
                style: monoStyle(size: 9),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SmallButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final bool filled;

  const _SmallButton({
    required this.icon,
    required this.onTap,
    this.filled = false,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: filled ? kInk : kSurface,
          border: Border.all(color: kBorderDark),
        ),
        child: Icon(icon, size: 14, color: filled ? kSurface : kInk),
      ),
    );
  }
}
