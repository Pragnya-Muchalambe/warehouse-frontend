import 'package:flutter/material.dart';

import '../controllers/inventory_controller.dart';
import '../models/inventory_item.dart';
import '../models/factory.dart';
import '../services/auth_service.dart';
import '../services/api_client.dart';
import '../services/request_service.dart';
import '../theme.dart';
import '../widgets/brutal.dart';

class ViewerRequestsView extends StatefulWidget {
  final InventoryController controller;
  final AuthSession session;
  final String? section;
  final ValueChanged<String?>? onAllRequestsSubmitted;
  final RequestService? requestService;

  const ViewerRequestsView({
    super.key,
    required this.controller,
    required this.session,
    this.section,
    this.onAllRequestsSubmitted,
    this.requestService,
  });

  @override
  State<ViewerRequestsView> createState() => _ViewerRequestsViewState();
}

class _ViewerRequestsViewState extends State<ViewerRequestsView> {
  final _formKey = GlobalKey<FormState>();
  late final RequestService _service;
  final _qtyController = TextEditingController();
  InventoryItem? _selectedItem;
  final List<_CartItem> _cart = [];
  DateTime? _reviewedAt;
  bool _reviewing = false;
  bool _submitting = false;
  WarehouseFactory? _selectedFactory;

  @override
  void initState() {
    super.initState();
    _service = widget.requestService ?? RequestService();
  }

  @override
  void dispose() {
    _qtyController.dispose();
    for (final entry in _cart) {
      entry.controller.dispose();
    }
    super.dispose();
  }

  List<InventoryItem> get _depotItems {
    final items = widget.controller.itemsInSection(InventorySection.depot);
    items.sort(
      (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
    );
    return items;
  }

  bool get _isFactory => widget.section == 'Sleeper';

  List<InventoryItem> get _requestItems {
    if (!_isFactory) return _depotItems;
    final factory = _selectedFactory;
    if (factory == null) return const [];
    return factory.materials
        .where((item) => item.status.toUpperCase() != 'INACTIVE')
        .map((item) => InventoryItem(
              id: item.id,
              materialNumber: item.id,
              name: item.name,
              quantity: item.total,
              biIssued: item.biIssued,
              status: item.status,
              section: InventorySection.sleeper,
            ))
        .toList()
      ..sort((a, b) => a.name.compareTo(b.name));
  }

  Future<void> _pickItem() async {
    final picked = await showModalBottomSheet<InventoryItem>(
      context: context,
      isScrollControlled: true,
      backgroundColor: kPaper,
      shape: const RoundedRectangleBorder(),
      builder: (context) => _ItemPickerSheet(items: _requestItems),
    );
    if (picked != null && mounted) {
      if (_cart.any((entry) => entry.item.id == picked.id)) {
        _showMessage('${picked.name} is already in the cart.');
        return;
      }
      setState(() => _selectedItem = picked);
    }
  }

  String? _validateQuantity(String? value) {
    final raw = (value ?? '').trim();
    if (raw.isEmpty) return 'Enter the number of items';
    final parsed = int.tryParse(raw);
    if (parsed == null || parsed < 1) return 'Enter a positive number';
    if (parsed > 2147483647) return 'Must be 2147483647 or less';
    final item = _selectedItem;
    if (item != null && parsed > item.available) {
      return 'Cannot exceed available quantity (${item.available})';
    }
    return null;
  }

  void _addToCart() {
    if (_submitting) return;
    final item = _selectedItem;
    if (item == null) {
      _showMessage(_isFactory
          ? 'Select a factory and material first.'
          : 'Select an item from the depot first.');
      return;
    }
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _cart.add(_CartItem(item, _qtyController.text.trim()));
      _selectedItem = null;
      _qtyController.clear();
    });
  }

  void _reviewCart() {
    if (_cart.isEmpty) {
      _showMessage('Add at least one item to the cart.');
      return;
    }
    if (_cart.any((entry) => _cartQuantityError(entry) != null)) {
      setState(() {});
      _showMessage('Correct the highlighted quantities before review.');
      return;
    }
    setState(() {
      _reviewedAt = DateTime.now();
      _reviewing = true;
    });
  }

  String? _cartAvailabilityError() {
    final depotItems = {for (final item in _requestItems) item.id: item};
    for (final entry in _cart) {
      final item = depotItems[entry.item.id];
      if (item == null || entry.quantity > item.available) {
        return '${entry.item.name} no longer has enough available stock.';
      }
    }
    return null;
  }

  String? _cartQuantityError(_CartItem entry) {
    final raw = entry.controller.text.trim();
    if (raw.isEmpty) return 'How Many is required';
    final quantity = int.tryParse(raw);
    if (quantity == null || quantity < 1) {
      return 'Enter a positive whole number';
    }
    if (quantity > entry.item.available) {
      return 'Cannot exceed available quantity (${entry.item.available})';
    }
    return null;
  }

  void _removeCartItem(_CartItem entry) {
    entry.controller.dispose();
    setState(() => _cart.remove(entry));
  }

  Future<void> _confirmRequests() async {
    if (_submitting) return;
    final availabilityError = _cartAvailabilityError();
    if (availabilityError != null) {
      setState(() => _reviewing = false);
      _showMessage(availabilityError);
      return;
    }

    setState(() => _submitting = true);
    var failed = <_CartItem>[];
    var successNames = <String>[];
    final errors = <String>[];
    try {
      await _service.addBatch(
        viewerId: widget.session.id,
        viewerName: widget.session.name,
        items: _cart
            .map((entry) => (
                  itemId: entry.item.id,
                  itemName: entry.item.name,
                  quantity: entry.quantity,
                ))
            .toList(),
        factoryId: _selectedFactory?.id,
        factoryName: _selectedFactory?.name,
      );
    } on RequestBatchException catch (error) {
      failed = _cart
          .where((entry) => error.failedItems.containsKey(entry.item.id))
          .toList();
      successNames = _cart
          .where((entry) => error.succeededItemIds.contains(entry.item.id))
          .map((entry) => entry.item.name)
          .toList();
      for (final entry in failed) {
        errors.add('${entry.item.name}: ${error.failedItems[entry.item.id]}');
      }
    } on ApiException catch (error) {
      failed.addAll(_cart);
      errors.add(error.message);
    } catch (_) {
      failed.addAll(_cart);
      errors.add('Request could not be sent.');
    }
    if (!mounted) return;
    final allSucceeded = failed.isEmpty;
    setState(() {
      _submitting = false;
      for (final entry in _cart.where((entry) => !failed.contains(entry))) {
        entry.controller.dispose();
      }
      _cart
        ..clear()
        ..addAll(failed);
      _reviewing = !allSucceeded;
    });
    if (allSucceeded) {
      widget.onAllRequestsSubmitted?.call(_selectedFactory?.id);
    } else {
      final succeeded =
          successNames.isEmpty ? '' : 'Succeeded: ${successNames.join(', ')}. ';
      _showMessage('${succeeded}Failed: ${errors.join(' ')}');
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_reviewing) return _buildReview();
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
              Text(
                _isFactory ? 'SLEEPER REQUESTS' : 'DEPOT REQUESTS',
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  letterSpacing: -0.5,
                  color: kInk,
                ),
              ),
              const SizedBox(height: 4),
              MonoLabel(
                  _isFactory
                      ? 'Request materials from one factory'
                      : 'Request materials from the depot',
                  size: 9),
              const SizedBox(height: 20),
              if (_isFactory) ...[
                const MonoLabel('SELECT FACTORY', weight: FontWeight.w600),
                const SizedBox(height: 8),
                DropdownButtonFormField<WarehouseFactory>(
                  key: const ValueKey('request-factory-selector'),
                  initialValue: _selectedFactory,
                  decoration:
                      const InputDecoration(border: OutlineInputBorder()),
                  hint: const Text('Select Factory'),
                  items: widget.controller.factories
                      .map((factory) => DropdownMenuItem(
                            value: factory,
                            child: Text('${factory.name} (${factory.id})'),
                          ))
                      .toList(),
                  onChanged: _cart.isNotEmpty || _submitting
                      ? null
                      : (factory) => setState(() {
                            _selectedFactory = factory;
                            _selectedItem = null;
                          }),
                ),
                if (_selectedFactory case final factory?) ...[
                  const SizedBox(height: 8),
                  MonoLabel(
                      'Selected Factory: ${factory.name} | ${factory.location}',
                      weight: FontWeight.w700),
                ],
                const SizedBox(height: 20),
              ],
              const MonoLabel('Item', weight: FontWeight.w600),
              const SizedBox(height: 8),
              InkWell(
                key: const ValueKey('request-material-selector'),
                onTap: _submitting || (_isFactory && _selectedFactory == null)
                    ? null
                    : _pickItem,
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
                            ? MonoLabel(
                                _isFactory
                                    ? 'Select material from factory'
                                    : 'Select item from depot',
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
                label: 'ADD TO CART',
                filled: true,
                padding: const EdgeInsets.all(16),
                onPressed: _submitting ? null : _addToCart,
              ),
              if (_cart.isNotEmpty) ...[
                const SizedBox(height: 24),
                const MonoLabel('REQUEST CART', weight: FontWeight.w600),
                const SizedBox(height: 8),
                ..._cart.map(
                  (entry) => Container(
                    key: ValueKey('request-item-${entry.item.id}'),
                    padding: const EdgeInsets.all(12),
                    decoration: const BoxDecoration(
                      border: Border(bottom: BorderSide(color: kBorder)),
                    ),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(entry.item.name.toUpperCase(),
                                      style: const TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600)),
                                  if (_isFactory)
                                    MonoLabel(
                                        'Factory: ${_selectedFactory!.name}',
                                        size: 9),
                                  MonoLabel(
                                      'PL/Material No.: ${entry.item.materialNumber}',
                                      size: 9),
                                  MonoLabel(
                                      'Available quantity: ${entry.item.available}',
                                      size: 9),
                                ],
                              ),
                            ),
                            SizedBox(
                              width: 92,
                              child: BrutalTextInput(
                                controller: entry.controller,
                                label: 'How Many',
                                keyboardType: TextInputType.number,
                                textAlign: TextAlign.center,
                                onChanged: (_) => setState(() {}),
                              ),
                            ),
                            IconButton(
                              tooltip: 'Remove ${entry.item.name}',
                              onPressed: () => _removeCartItem(entry),
                              icon: const Icon(Icons.close,
                                  size: 18, color: kRed),
                            ),
                          ],
                        ),
                        if (_cartQuantityError(entry) case final error?)
                          Align(
                            alignment: Alignment.centerRight,
                            child: MonoLabel(error, size: 8, color: kRed),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                BrutalButton(
                  label:
                      'REVIEW REQUEST (${_cart.length} MATERIAL${_cart.length == 1 ? '' : 'S'})',
                  filled: true,
                  onPressed:
                      _cart.any((entry) => _cartQuantityError(entry) != null)
                          ? null
                          : _reviewCart,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildReview() {
    final reviewedAt = _reviewedAt ?? DateTime.now();
    final date =
        '${reviewedAt.year.toString().padLeft(4, '0')}-${reviewedAt.month.toString().padLeft(2, '0')}-${reviewedAt.day.toString().padLeft(2, '0')}';
    final time =
        '${reviewedAt.hour.toString().padLeft(2, '0')}:${reviewedAt.minute.toString().padLeft(2, '0')}';
    final totalQuantity =
        _cart.fold<int>(0, (sum, entry) => sum + entry.quantity);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: MaxWidth(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('REVIEW REQUEST',
                style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    letterSpacing: -0.5,
                    color: kInk)),
            const SizedBox(height: 4),
            MonoLabel('DATE: $date  TIME: $time', size: 9),
            const SizedBox(height: 20),
            BrutalCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  MonoLabel(
                      '${_cart.length} ITEMS / $totalQuantity TOTAL UNITS',
                      weight: FontWeight.w700),
                  const SizedBox(height: 12),
                  ..._cart.map((entry) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(children: [
                          Expanded(
                              child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(entry.item.name.toUpperCase(),
                                  style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600)),
                              MonoLabel(
                                  'PL/Material No.: ${entry.item.materialNumber}',
                                  size: 9),
                              MonoLabel(
                                  'Available quantity: ${entry.item.available}',
                                  size: 9),
                            ],
                          )),
                          MonoLabel('Quantity: ${entry.quantity}',
                              weight: FontWeight.w700),
                        ]),
                      )),
                ],
              ),
            ),
            const SizedBox(height: 24),
            BrutalButton(
                label: _submitting ? 'SENDING...' : 'CONFIRM REQUESTS',
                filled: true,
                onPressed: _submitting ? null : _confirmRequests),
            const SizedBox(height: 12),
            BrutalButton(
                label: 'BACK TO CART',
                onPressed: _submitting
                    ? null
                    : () => setState(() => _reviewing = false)),
          ],
        ),
      ),
    );
  }
}

class _CartItem {
  final InventoryItem item;
  final TextEditingController controller;

  int get quantity => int.tryParse(controller.text.trim()) ?? 0;

  _CartItem(this.item, String quantity)
      : controller = TextEditingController(text: quantity);
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
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
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
              prefixIcon: const Icon(Icons.search, size: 18, color: kGray400),
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
