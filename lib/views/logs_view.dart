import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../models/factory.dart';
import '../models/inventory_item.dart';
import '../models/transaction_log.dart';
import '../services/auth_service.dart';
import '../theme.dart';
import '../widgets/brutal.dart';
import '../widgets/section_tabs.dart';

class LogsView extends StatefulWidget {
  final List<TransactionLog> logs;
  final List<WarehouseFactory> factories;
  final AuthSession session;
  final Future<void> Function({
    required String logId,
    required List<CartItem> updatedItems,
    required String user,
  }) editTransaction;

  const LogsView({
    super.key,
    required this.logs,
    required this.factories,
    required this.session,
    required this.editTransaction,
  });

  @override
  State<LogsView> createState() => _LogsViewState();
}

class _LogsViewState extends State<LogsView> {
  InventorySection _section = InventorySection.depot;
  String? _factoryName;
  String? _editingLogId;
  List<CartItem> _editItems = [];
  final Map<String, TextEditingController> _editControllers = {};

  bool get _isSuperadmin => widget.session.role == 'superadmin';

  bool get _isFactoryScope =>
      _section == InventorySection.sleeper && _factoryName != null;

  void _selectSection(InventorySection section) {
    if (section == _section) return;
    setState(() {
      _section = section;
      _factoryName = null;
    });
  }

  void _selectFactory(String? name) {
    if (name == _factoryName) return;
    setState(() => _factoryName = name);
  }

  List<TransactionLog> get _filteredLogs {
    return widget.logs.where((log) {
      // Legacy logs predating sections are shown in both Depot and Sleeper.
      final sectionOk = log.section == null || log.section == _section;
      final factoryOk = !_isFactoryScope || log.factoryName == _factoryName;
      return sectionOk && factoryOk;
    }).toList();
  }

  @override
  void dispose() {
    for (final c in _editControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _startEdit(TransactionLog log) {
    final items = log.items.map((i) => i.copyWith()).toList();
    final controllers = <String, TextEditingController>{};
    for (final item in items) {
      controllers[item.id] =
          TextEditingController(text: '${item.quantityChange}');
    }
    setState(() {
      _editingLogId = log.id;
      _editItems = items;
      for (final c in _editControllers.values) {
        c.dispose();
      }
      _editControllers
        ..clear()
        ..addAll(controllers);
    });
  }

  void _cancelEdit() {
    setState(() {
      _editingLogId = null;
      _editItems = [];
      for (final c in _editControllers.values) {
        c.dispose();
      }
      _editControllers.clear();
    });
  }

  void _updateEditQty(String id, String value) {
    final parsed = int.tryParse(value);
    final qty = (parsed ?? 1) < 1 ? 1 : (parsed ?? 1);
    final index = _editItems.indexWhere((i) => i.id == id);
    if (index == -1) return;
    setState(() {
      _editItems[index] = _editItems[index].copyWith(quantityChange: qty);
      _editControllers[id]?.text = '$qty';
    });
  }

  Future<void> _saveEdit(String logId) async {
    await widget.editTransaction(
      logId: logId,
      updatedItems: _editItems,
      user: widget.session.username,
    );
    _cancelEdit();
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
              const Text(
                'AUDIT LOGS',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  letterSpacing: -0.5,
                  color: kInk,
                ),
              ),
              const SizedBox(height: 4),
              const MonoLabel('Immutable Transaction History'),
              const SizedBox(height: 14),
              SectionTabs(active: _section, onChanged: _selectSection),
              if (_section == InventorySection.sleeper) ...[
                const SizedBox(height: 10),
                FactoryFilterChips(
                  factories: widget.factories,
                  selected: _factoryName,
                  onChanged: _selectFactory,
                ),
              ],
            ],
          ),
        ),
        Expanded(
          child: logs.isEmpty
              ? const _NoLogs()
              : MaxWidth(
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: logs.length,
                    itemBuilder: (context, index) {
                      final log = logs[index];
                      return _LogCard(
                        log: log,
                        isEditing: _editingLogId == log.id,
                        editControllers: _editControllers,
                        canEdit: _isSuperadmin,
                        onStartEdit: () => _startEdit(log),
                        onCancelEdit: _cancelEdit,
                        onUpdateQty: _updateEditQty,
                        onSaveEdit: () => _saveEdit(log.id),
                      );
                    },
                  ),
                ),
        ),
      ],
    );
  }
}

class _LogCard extends StatelessWidget {
  final TransactionLog log;
  final bool isEditing;
  final Map<String, TextEditingController> editControllers;
  final bool canEdit;
  final VoidCallback onStartEdit;
  final VoidCallback onCancelEdit;
  final void Function(String id, String value) onUpdateQty;
  final VoidCallback onSaveEdit;

  const _LogCard({
    required this.log,
    required this.isEditing,
    required this.editControllers,
    required this.canEdit,
    required this.onStartEdit,
    required this.onCancelEdit,
    required this.onUpdateQty,
    required this.onSaveEdit,
  });

  Color get _typeColor {
    switch (log.type) {
      case LogType.incoming:
        return const Color(0xFF1B5E20);
      case LogType.dispatch:
        return const Color(0xFFB71C1C);
      case LogType.edit:
        return const Color(0xFF0D47A1);
      case LogType.requestAccepted:
        return const Color(0xFF00695C);
      case LogType.requestRejected:
        return const Color(0xFFBF360C);
      case LogType.requestUndone:
        return const Color(0xFF4A148C);
    }
  }

  @override
  Widget build(BuildContext context) {
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
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    log.type.label,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                      color: _typeColor,
                    ),
                  ),
                  const SizedBox(height: 4),
                  MonoLabel(
                    _formatDate(log.timestamp),
                    size: 9,
                  ),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  MonoLabel(log.user, size: 11, weight: FontWeight.w700),
                  const SizedBox(height: 4),
                  Text(
                    'ID: ${_shortId(log.id)}',
                    style: monoStyle(size: 9),
                  ),
                ],
              ),
            ],
          ),
          if (log.notes != null && log.notes!.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: kGray50,
                border: Border.all(color: kGray200),
              ),
              child: Text(
                'NOTES: ${log.notes}',
                style: monoStyle(size: 12, color: kInk),
              ),
            ),
          ],
          if (log.section != null || log.factoryName != null) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: kGray50,
                border: Border.all(color: kGray200),
              ),
              child: MonoLabel(
                '${log.section?.label ?? '—'}${log.factoryName != null ? ' · ${log.factoryName}' : ''}',
                size: 9,
                weight: FontWeight.w600,
              ),
            ),
          ],
          if (log.person != null ||
              log.comingFrom != null ||
              log.dateOfArrival != null ||
              log.dateRequested != null ||
              log.dateLeaving != null ||
              log.truckNumber != null) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: kGray50,
                border: Border.all(color: kGray200),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (log.person != null)
                    _AuditLine(
                      label: log.type == LogType.incoming
                          ? 'SENT BY'
                          : 'REQUESTED BY',
                      value: log.person!,
                    ),
                  if (log.comingFrom != null)
                    _AuditLine(label: 'COMING FROM', value: log.comingFrom!),
                  if (log.dateOfArrival != null)
                    _AuditLine(
                        label: 'DATE OF ARRIVAL', value: log.dateOfArrival!),
                  if (log.dateRequested != null)
                    _AuditLine(
                        label: 'DATE REQUESTED', value: log.dateRequested!),
                  if (log.dateLeaving != null)
                    _AuditLine(label: 'DATE LEAVING', value: log.dateLeaving!),
                  if (log.truckNumber != null)
                    _AuditLine(label: 'TRUCK NO.', value: log.truckNumber!),
                ],
              ),
            ),
          ],
          const SizedBox(height: 12),
          for (var i = 0; i < log.items.length; i++)
            _buildItemRow(log.items[i], i),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (log.bill != null || log.billData != null)
                _buildAttachment(
                  context,
                  label: 'Bill',
                  fileName: log.bill,
                  data: log.billData,
                ),
              if (log.proof != null || log.proofData != null)
                _buildAttachment(
                  context,
                  label: 'Proof',
                  fileName: log.proof,
                  data: log.proofData,
                ),
              if (canEdit &&
                  (log.type == LogType.incoming ||
                      log.type == LogType.dispatch))
                isEditing
                    ? Row(
                        children: [
                          _IconButton(
                            icon: Icons.close,
                            onTap: onCancelEdit,
                          ),
                          const SizedBox(width: 8),
                          _IconButton(
                            icon: Icons.check,
                            filled: true,
                            onTap: onSaveEdit,
                          ),
                        ],
                      )
                    : InkWell(
                        onTap: onStartEdit,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            border: Border.all(color: kBorderDark),
                          ),
                          child: const Row(
                            children: [
                              Icon(Icons.edit_outlined, size: 12, color: kInk),
                              SizedBox(width: 4),
                              MonoLabel('Edit',
                                  size: 10, weight: FontWeight.w600),
                            ],
                          ),
                        ),
                      ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAttachment(
    BuildContext context, {
    required String label,
    required String? fileName,
    required String? data,
  }) {
    return InkWell(
      onTap: data == null
          ? null
          : () => _showAttachment(
                context,
                label: label,
                fileName: fileName,
                data: data,
              ),
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
            Icon(
              data != null
                  ? Icons.visibility_outlined
                  : Icons.photo_camera_outlined,
              size: 12,
              color: kInkMuted,
            ),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                '$label: ${fileName ?? 'Attached image'}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: monoStyle(size: 9, color: kInk),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showAttachment(
    BuildContext context, {
    required String label,
    required String? fileName,
    required String data,
  }) {
    if (data.isEmpty) return;
    final Uint8List bytes;
    try {
      bytes = base64Decode(data);
    } catch (_) {
      return;
    }
    showDialog<void>(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: kSurface,
        shape: const RoundedRectangleBorder(),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '$label: ${fileName ?? 'Attached image'}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: monoStyle(size: 11, weight: FontWeight.w600),
              ),
              const SizedBox(height: 12),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 420),
                child: ClipRect(
                  child: Image.memory(
                    bytes,
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => const Padding(
                      padding: EdgeInsets.all(24),
                      child:
                          Center(child: MonoLabel('Unable to display image')),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              BrutalButton(
                label: 'CLOSE',
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildItemRow(CartItem item, int index) {
    if (log.type == LogType.edit) {
      // Show the edit diff: old qty struck through -> new qty.
      final oldQty = log.oldItems
              ?.where((o) => o.id == item.id)
              .firstOrNull
              ?.quantityChange ??
          0;
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 6),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: kBorder)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                item.name,
                style: monoStyle(size: 11, color: kInk),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '$oldQty',
              style: monoStyle(
                size: 11,
                color: kGray400,
                letterSpacing: 0,
              ).copyWith(decoration: TextDecoration.lineThrough),
            ),
            const SizedBox(width: 8),
            Text(
              '${item.quantityChange} pcs',
              style: monoStyle(
                size: 11,
                weight: FontWeight.w700,
                color: kInk,
                letterSpacing: 0,
              ),
            ),
          ],
        ),
      );
    }

    final isEditingThis = isEditing;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 6),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: kBorder)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              item.name,
              style: monoStyle(size: 11, color: kInk),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          if (isEditingThis)
            SizedBox(
              width: 72,
              child: BrutalTextInput(
                controller: editControllers[item.id],
                keyboardType: TextInputType.number,
                textAlign: TextAlign.center,
                minHeight: 34,
                contentPadding:
                    const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
                onChanged: (v) => onUpdateQty(item.id, v),
              ),
            )
          else
            Text(
              '${item.quantityChange} pcs',
              style: monoStyle(
                size: 11,
                weight: FontWeight.w700,
                color: kInk,
                letterSpacing: 0,
              ),
            ),
        ],
      ),
    );
  }

  String _formatDate(DateTime dt) => dt.toLocal().toString();
}

class _AuditLine extends StatelessWidget {
  final String label;
  final String value;

  const _AuditLine({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 118,
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

class _IconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final bool filled;

  const _IconButton({
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

class _NoLogs extends StatelessWidget {
  const _NoLogs();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: MonoLabel('No Transactions', color: kGray400),
    );
  }
}

String _shortId(String id) {
  if (id.length <= 6) return id;
  return id.substring(id.length - 6);
}
