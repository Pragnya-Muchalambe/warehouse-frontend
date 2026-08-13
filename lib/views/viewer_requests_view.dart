import 'package:flutter/material.dart';

import '../controllers/inventory_controller.dart';
import '../models/inventory_item.dart';
import '../services/auth_service.dart';
import '../services/request_service.dart';
import '../theme.dart';
import '../widgets/brutal.dart';

class ViewerRequestsView extends StatefulWidget {
  final InventoryController controller;
  final AuthSession session;

  const ViewerRequestsView({
    super.key,
    required this.controller,
    required this.session,
  });

  @override
  State<ViewerRequestsView> createState() => _ViewerRequestsViewState();
}

class _ViewerRequestsViewState extends State<ViewerRequestsView> {
  final _formKey = GlobalKey<FormState>();
  final RequestService _service = RequestService();
  final _qtyController = TextEditingController();
  InventoryItem? _selectedItem;
  bool _submitting = false;

  @override
  void dispose() {
    _qtyController.dispose();
    super.dispose();
  }

  List<InventoryItem> get _depotItems {
    final items = widget.controller.itemsInSection(InventorySection.depot);
    items.sort(
      (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
    );
    return items;
  }

  Future<void> _pickItem() async {
    final picked = await showModalBottomSheet<InventoryItem>(
      context: context,
      isScrollControlled: true,
      backgroundColor: kPaper,
      shape: const RoundedRectangleBorder(),
      builder: (context) => _ItemPickerSheet(items: _depotItems),
    );
    if (picked != null && mounted) {
      setState(() => _selectedItem = picked);
    }
  }

  String? _validateQuantity(String? value) {
    final raw = (value ?? '').trim();
    if (raw.isEmpty) return 'Enter the number of items';
    final parsed = int.tryParse(raw);
    if (parsed == null || parsed < 1) return 'Enter a positive number';
    final item = _selectedItem;
    if (item != null && parsed > item.available) {
      return 'Cannot exceed available quantity (${item.available})';
    }
    return null;
  }

  Future<void> _submit() async {
    if (_submitting) return;
    final item = _selectedItem;
    if (item == null) {
      _showMessage('Select an item from the depot first.');
      return;
    }
    if (!_formKey.currentState!.validate()) return;
    setState(() => _submitting = true);
    await _service.addRequest(
      viewerId: widget.session.id,
      viewerName: widget.session.name,
      itemId: item.id,
      itemName: item.name,
      quantity: int.parse(_qtyController.text.trim()),
    );
    if (!mounted) return;
    setState(() {
      _submitting = false;
      _selectedItem = null;
      _qtyController.clear();
    });
    _showMessage('Request has been sent');
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final item = _selectedItem;
    final isUnavailable = item != null && item.isOutOfStock();
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: MaxWidth(
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'REQUESTS',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  letterSpacing: -0.5,
                  color: kInk,
                ),
              ),
              const SizedBox(height: 4),
              const MonoLabel('Request materials from the depot', size: 9),
              const SizedBox(height: 20),
              const MonoLabel('Item', weight: FontWeight.w600),
              const SizedBox(height: 8),
              InkWell(
                onTap: _submitting ? null : _pickItem,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  decoration: BoxDecoration(
                    color: kSurface,
                    border: Border.all(color: kBorderDark, width: 1),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.search, size: 16, color: kGray400),
                      const SizedBox(width: 8),
                      Expanded(
                        child: item == null
                            ? const MonoLabel(
                                'Select item from depot',
                                color: kGray400,
                                size: 11,
                              )
                            : Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  MonoLabel(item.id, size: 9),
                                  const SizedBox(height: 2),
                                  Text(
                                    item.name.toUpperCase(),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: kInk,
                                    ),
                                  ),
                                ],
                              ),
                      ),
                      const Icon(Icons.arrow_drop_down, size: 24, color: kInk),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              if (item != null)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: kGray50,
                    border: Border.all(
                      color: isUnavailable ? kRed : kGreen,
                      width: 1,
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      MonoLabel(
                        isUnavailable ? 'UNAVAILABLE' : 'AVAILABLE',
                        size: 9,
                        weight: FontWeight.w600,
                        color: isUnavailable ? kRed : kGreen,
                      ),
                      Text(
                        '${item.available}',
                        style: monoStyle(
                          size: 18,
                          weight: FontWeight.w700,
                          color: isUnavailable ? kRed : kGreen,
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 16),
              BrutalTextField(
                label: 'Number of Items',
                controller: _qtyController,
                keyboardType: TextInputType.number,
                validator: _validateQuantity,
              ),
              const SizedBox(height: 24),
              BrutalButton(
                label: _submitting ? 'SENDING...' : 'REQUEST',
                filled: true,
                padding: const EdgeInsets.all(16),
                onPressed: _submitting ? null : _submit,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ItemPickerSheet extends StatefulWidget {
  final List<InventoryItem> items;

  const _ItemPickerSheet({required this.items});

  @override
  State<_ItemPickerSheet> createState() => _ItemPickerSheetState();
}

class _ItemPickerSheetState extends State<_ItemPickerSheet> {
  final _searchController = TextEditingController();
  String _term = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<InventoryItem> get _filtered {
    final term = _term.toLowerCase().trim();
    if (term.isEmpty) return widget.items;
    return widget.items
        .where((item) =>
            item.id.toLowerCase().contains(term) ||
            item.name.toLowerCase().contains(term))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            color: kInk,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'SELECT ITEM',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      letterSpacing: -0.5,
                      color: kSurface,
                    ),
                  ),
                ),
                InkWell(
                  onTap: () => Navigator.of(context).pop(),
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      border: Border.all(color: kSurface, width: 1),
                    ),
                    child: const Icon(Icons.close, size: 14, color: kSurface),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: BrutalTextInput(
              controller: _searchController,
              hint: 'SEARCH DEPOT INVENTORY...',
              uppercase: true,
              prefixIcon:
                  const Icon(Icons.search, size: 18, color: kGray400),
              onChanged: (v) => setState(() => _term = v),
            ),
          ),
          if (filtered.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: MonoLabel('No matching items')),
            )
          else
            Flexible(
              child: ListView.builder(
                padding: const EdgeInsets.only(bottom: 16),
                itemCount: filtered.length,
                itemBuilder: (context, index) {
                  final item = filtered[index];
                  final unavailable = item.isOutOfStock();
                  return InkWell(
                    onTap: () => Navigator.of(context).pop(item),
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: const BoxDecoration(
                        border: Border(
                          bottom: BorderSide(color: kBorder),
                        ),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                MonoLabel(item.id, size: 9),
                                const SizedBox(height: 2),
                                Text(
                                  item.name.toUpperCase(),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: kInk,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          MonoLabel(
                            unavailable
                                ? 'UNAVAILABLE'
                                : 'Available: ${item.available}',
                            size: 10,
                            weight: FontWeight.w600,
                            color: unavailable ? kRed : kGreen,
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}
