import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../controllers/inventory_controller.dart';
import '../models/factory.dart';
import '../models/inventory_item.dart';
import '../models/transaction_log.dart';
import '../services/auth_service.dart';
import '../theme.dart';
import '../widgets/brutal.dart';
import '../widgets/section_tabs.dart';

enum _TransactionForm { incoming, dispatch }

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

class TransactionsView extends StatefulWidget {
  final InventoryController controller;
  final Future<void> Function({
    required String type,
    required List<CartItem> items,
    String? notes,
    String? photo,
    String? photoData,
    required String user,
    InventorySection? section,
    String? factoryName,
    String? person,
    String? comingFrom,
    String? dateOfArrival,
    String? dateRequested,
    String? dateLeaving,
    String? truckNumber,
  }) addTransaction;
  final AuthSession session;

  const TransactionsView({
    super.key,
    required this.controller,
    required this.addTransaction,
    required this.session,
  });

  @override
  State<TransactionsView> createState() => _TransactionsViewState();
}

class _TransactionsViewState extends State<TransactionsView> {
  InventorySection _section = InventorySection.depot;
  String? _factoryName;
  _TransactionForm? _activeForm;
  final List<CartItem> _selectedItems = [];
  final Map<String, TextEditingController> _qtyControllers = {};
  final _searchController = TextEditingController();
  final _personController = TextEditingController();
  final _comingFromController = TextEditingController();
  final _requestedByController = TextEditingController();
  final _truckController = TextEditingController();
  DateTime? _dateOfArrival;
  DateTime? _dateRequested;
  DateTime? _dateLeaving;
  XFile? _photo;
  Uint8List? _photoBytes;
  String _searchTerm = '';
  bool _submitting = false;

  bool get _canOperate =>
      widget.session.role == 'superadmin' || widget.session.role == 'admin';

  bool get _isFactoryScope =>
      _section == InventorySection.sleeper && _factoryName != null;

  String get _scopeLabel =>
      _section == InventorySection.depot
          ? 'DEPOT'
          : 'SLEEPER${_factoryName != null ? ' · $_factoryName' : ''}';

  WarehouseFactory? get _scopeFactory {
    if (_factoryName == null) return null;
    for (final factory in widget.controller.factories) {
      if (factory.name == _factoryName) return factory;
    }
    return null;
  }

  List<InventoryItem> get _scopeInventory {
    return widget.controller.inventory
        .where((i) => i.isInSection(_section))
        .toList();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _personController.dispose();
    _comingFromController.dispose();
    _requestedByController.dispose();
    _truckController.dispose();
    for (final c in _qtyControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  TextEditingController _qtyControllerFor(CartItem item) {
    return _qtyControllers.putIfAbsent(
      item.id,
      () => TextEditingController(text: '${item.quantityChange}'),
    );
  }

  void _resetForm() {
    setState(() {
      _activeForm = null;
      _selectedItems.clear();
      for (final c in _qtyControllers.values) {
        c.dispose();
      }
      _qtyControllers.clear();
      _searchController.clear();
      _personController.clear();
      _comingFromController.clear();
      _requestedByController.clear();
      _truckController.clear();
      _dateOfArrival = null;
      _dateRequested = null;
      _dateLeaving = null;
      _photo = null;
      _photoBytes = null;
      _searchTerm = '';
      _submitting = false;
    });
  }

  void _selectSection(InventorySection section) {
    if (section == _section) return;
    _resetForm();
    setState(() {
      _section = section;
      _factoryName = null;
    });
  }

  void _selectFactory(String? name) {
    if (name == _factoryName) return;
    _resetForm();
    setState(() => _factoryName = name);
  }

  List<CartItem> get _searchResults {
    final term = _searchTerm.toLowerCase().trim();
    if (term.isEmpty) return [];
    final isIncoming = _activeForm == _TransactionForm.incoming;
    if (_isFactoryScope) {
      final factory = _scopeFactory;
      if (factory == null) return [];
      return factory.materials
          .where((m) =>
              m.name.toLowerCase().contains(term) ||
              m.id.toLowerCase().contains(term))
          .where((m) => isIncoming || m.available > 0)
          .take(5)
          .map((m) => CartItem(
                id: m.id,
                name: m.name,
                quantityChange: 1,
                max: isIncoming ? null : m.available,
              ))
          .toList();
    }
    return _scopeInventory
        .where((item) =>
            item.name.toLowerCase().contains(term) ||
            item.id.toLowerCase().contains(term))
        .where((item) => isIncoming || item.available > 0)
        .take(5)
        .map((item) => CartItem(
              id: item.id,
              name: item.name,
              quantityChange: 1,
              max: isIncoming ? null : item.available,
            ))
        .toList();
  }

  void _addItem(CartItem candidate) {
    if (_selectedItems.any((i) => i.id == candidate.id)) return;
    _qtyControllers[candidate.id] = TextEditingController(text: '1');
    setState(() {
      _selectedItems.add(candidate);
      _searchController.clear();
      _searchTerm = '';
    });
  }

  void _updateQty(String id, String value) {
    setState(() {
      final index = _selectedItems.indexWhere((i) => i.id == id);
      if (index == -1) return;
      final item = _selectedItems[index];
      final parsed = int.tryParse(value);
      var qty = parsed ?? 1;
      if (_activeForm == _TransactionForm.dispatch && item.max != null) {
        qty = qty.clamp(1, item.max!).toInt();
      } else {
        qty = qty < 1 ? 1 : qty;
      }
      _selectedItems[index] = item.copyWith(quantityChange: qty);
      _qtyControllers[id]?.text = '$qty';
    });
  }

  void _removeItem(String id) {
    _qtyControllers.remove(id)?.dispose();
    setState(() => _selectedItems.removeWhere((i) => i.id == id));
  }

  Future<void> _pickPhoto() async {
    final picker = ImagePicker();
    XFile? file;
    try {
      file = await picker.pickImage(source: ImageSource.camera);
    } catch (_) {
      // Camera unavailable on this platform; fall through to gallery.
    }
    file ??= await picker.pickImage(source: ImageSource.gallery);
    if (file != null && mounted) {
      final bytes = await file.readAsBytes();
      if (!mounted) return;
      setState(() {
        _photo = file;
        _photoBytes = bytes;
      });
    }
  }

  Future<void> _pickDate(
    DateTime? current,
    ValueChanged<DateTime> onPicked,
  ) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: current ?? now,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 5),
    );
    if (picked != null && mounted) {
      setState(() => onPicked(picked));
    }
  }

  String _formatDate(DateTime d) {
    final local = d.toLocal();
    return '${local.day} ${_months[local.month - 1]} ${local.year}';
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<void> _submit() async {
    if (_selectedItems.isEmpty) {
      _showMessage('Add at least one item.');
      return;
    }
    final hasInvalidQty = _selectedItems.any((i) => i.quantityChange < 1);
    if (hasInvalidQty) {
      _showMessage('All items must have a quantity of 1 or more.');
      return;
    }
    if (_photo == null) {
      _showMessage('Bill / proof is mandatory. Upload it at the top.');
      return;
    }

    final isIncoming = _activeForm == _TransactionForm.incoming;
    final person = _personController.text.trim();
    final comingFrom = _comingFromController.text.trim();
    final requestedBy = _requestedByController.text.trim();
    final truck = _truckController.text.trim();

    if (isIncoming) {
      if (person.isEmpty ||
          comingFrom.isEmpty ||
          _dateOfArrival == null ||
          truck.isEmpty) {
        _showMessage(
            'Fill person, coming from, date of arrival and truck number.');
        return;
      }
    } else {
      if (requestedBy.isEmpty ||
          _dateRequested == null ||
          _dateLeaving == null ||
          truck.isEmpty) {
        _showMessage(
            'Fill requested by, request date, leaving date and truck number.');
        return;
      }
      if (_dateLeaving!.isBefore(_dateRequested!)) {
        _showMessage('Leaving date cannot be before the request date.');
        return;
      }
      for (final sel in _selectedItems) {
        final stock = _scopeInventory
            .where((i) => i.id == sel.id)
            .firstOrNull
            ?.available;
        if (stock != null && stock < sel.quantityChange) {
          _showMessage('Insufficient available stock for dispatch.');
          return;
        }
      }
    }

    String? photoData;
    final bytes = _photoBytes;
    if (bytes != null && bytes.lengthInBytes <= 1024 * 1024) {
      photoData = base64Encode(bytes);
    }

    setState(() => _submitting = true);
    await widget.addTransaction(
      type: isIncoming
          ? LogType.incoming.label
          : LogType.dispatch.label,
      items: _selectedItems,
      photo: _photo!.name,
      photoData: photoData,
      user: widget.session.username,
      section: _section,
      factoryName: _isFactoryScope ? _factoryName : null,
      person: isIncoming ? person : requestedBy,
      comingFrom: isIncoming ? comingFrom : null,
      dateOfArrival: isIncoming ? _formatDate(_dateOfArrival!) : null,
      dateRequested: isIncoming ? null : _formatDate(_dateRequested!),
      dateLeaving: isIncoming ? null : _formatDate(_dateLeaving!),
      truckNumber: truck,
    );
    if (!mounted) return;
    _resetForm();
    _showMessage('Transaction completed successfully.');
  }

  List<TransactionLog> _filteredLogs() {
    return widget.controller.logs.where((log) {
      // Legacy logs predating sections are shown in both Depot and Sleeper.
      final sectionOk = log.section == null || log.section == _section;
      final factoryOk = !_isFactoryScope || log.factoryName == _factoryName;
      return sectionOk && factoryOk;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _buildHeader(),
        Expanded(
          child: _activeForm == null ? _buildLanding() : _buildForm(),
        ),
      ],
    );
  }

  Widget _buildHeader() {
    return Container(
      decoration: const BoxDecoration(
        color: kSurface,
        border: Border(bottom: BorderSide(color: kBorderDark, width: 1)),
      ),
      child: MaxWidth(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'ACTIONS',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  letterSpacing: -0.5,
                  color: kInk,
                ),
              ),
              const SizedBox(height: 14),
              SectionTabs(active: _section, onChanged: _selectSection),
              if (_section == InventorySection.sleeper) ...[
                const SizedBox(height: 10),
                FactoryFilterChips(
                  factories: widget.controller.factories,
                  selected: _factoryName,
                  onChanged: _selectFactory,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLanding() {
    if (_canOperate) return _buildChooser();
    return _buildViewerActions();
  }

  Widget _buildChooser() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: MaxWidth(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            MonoLabel('SCOPE: $_scopeLabel', color: kGray400),
            const SizedBox(height: 16),
            _ChoiceButton(
              icon: Icons.add,
              label: 'New Incoming',
              onTap: () =>
                  setState(() => _activeForm = _TransactionForm.incoming),
            ),
            const SizedBox(height: 24),
            _ChoiceButton(
              icon: Icons.remove,
              label: 'New Dispatch',
              onTap: () =>
                  setState(() => _activeForm = _TransactionForm.dispatch),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildViewerActions() {
    final records = _filteredLogs();
    if (records.isEmpty) {
      return const Center(child: MonoLabel('No Actions', color: kGray400));
    }
    return MaxWidth(
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: records.length,
        itemBuilder: (context, index) {
          return _ActionRecordCard(log: records[index]);
        },
      ),
    );
  }

  Widget _buildProofCard() {
    final bytes = _photoBytes;
    return BrutalCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const MonoLabel('UPLOAD BILL / PROOF *', weight: FontWeight.w600),
          const SizedBox(height: 12),
          InkWell(
            onTap: _pickPhoto,
            child: bytes != null
                ? Container(
                    width: double.infinity,
                    decoration: BoxDecoration(
                      border: Border.all(color: kBorderDark, width: 1),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        ClipRect(
                          child: Image.memory(
                            bytes,
                            height: 140,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Container(
                              height: 140,
                              color: kGray50,
                              child: const Center(
                                child: MonoLabel('Preview unavailable',
                                    color: kGray400),
                              ),
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 8),
                          decoration: const BoxDecoration(
                            color: kInk,
                            border: Border(
                              top: BorderSide(color: kBorderDark, width: 1),
                            ),
                          ),
                          child: const Row(
                            children: [
                              Icon(Icons.check_circle_outline,
                                  size: 14, color: kSurface),
                              SizedBox(width: 8),
                              Expanded(
                                child: MonoLabel(
                                  'Bill / proof attached - tap to change',
                                  size: 9,
                                  color: kSurface,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  )
                : Container(
                    width: double.infinity,
                    color: kGray50,
                    child: const DashedBorder(
                      color: kGray300,
                      width: 2,
                      padding: EdgeInsets.all(24),
                      child: Column(
                        children: [
                          Icon(Icons.upload_file_outlined,
                              size: 24, color: kGray400),
                          SizedBox(height: 8),
                          MonoLabel(
                            'Tap to upload bill / proof image',
                            color: kGray400,
                          ),
                        ],
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailsCard(bool isIncoming) {
    return BrutalCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          MonoLabel(
            isIncoming ? 'INCOMING DETAILS' : 'DISPATCH DETAILS',
            weight: FontWeight.w600,
          ),
          const SizedBox(height: 12),
          BrutalTextInput(
            controller:
                isIncoming ? _personController : _requestedByController,
            label: isIncoming ? 'Person Who Sent Order' : 'Requested By',
            hint: isIncoming ? 'Sender / vendor name' : 'Who the items are for',
          ),
          const SizedBox(height: 12),
          if (isIncoming) ...[
            BrutalTextInput(
              controller: _comingFromController,
              label: 'Coming From',
              hint: 'Origin / location',
            ),
            const SizedBox(height: 12),
            _FormDateButton(
              label: _dateOfArrival == null
                  ? 'SET DATE OF ARRIVAL'
                  : _formatDate(_dateOfArrival!),
              onTap: () =>
                  _pickDate(_dateOfArrival, (d) => _dateOfArrival = d),
            ),
          ] else ...[
            _FormDateButton(
              label: _dateRequested == null
                  ? 'SET DATE REQUESTED'
                  : _formatDate(_dateRequested!),
              onTap: () =>
                  _pickDate(_dateRequested, (d) => _dateRequested = d),
            ),
            const SizedBox(height: 12),
            _FormDateButton(
              label: _dateLeaving == null
                  ? 'SET DATE LEAVING DEPOT'
                  : _formatDate(_dateLeaving!),
              onTap: () => _pickDate(_dateLeaving, (d) => _dateLeaving = d),
            ),
          ],
          const SizedBox(height: 12),
          BrutalTextInput(
            controller: _truckController,
            label: 'Truck Number',
            hint: 'Vehicle registration',
            uppercase: true,
          ),
        ],
      ),
    );
  }

  Widget _buildForm() {
    final isIncoming = _activeForm == _TransactionForm.incoming;
    return Column(
      children: [
        // Black header bar (bg-black text-white).
        Container(
          width: double.infinity,
          color: kInk,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isIncoming ? 'RECEIVE GOODS' : 'DISPATCH GOODS',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      letterSpacing: -0.5,
                      color: kSurface,
                    ),
                  ),
                  MonoLabel(_scopeLabel, size: 9, color: kGray400),
                ],
              ),
              InkWell(
                onTap: _resetForm,
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    border: Border.all(color: kSurface, width: 1),
                  ),
                  child: const Icon(Icons.close, size: 16, color: kSurface),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: MaxWidth(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildProofCard(),
                  const SizedBox(height: 16),
                  _buildDetailsCard(isIncoming),
                  const SizedBox(height: 16),
                  BrutalCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const MonoLabel(
                          'Add Items to Batch',
                          weight: FontWeight.w600,
                        ),
                        const SizedBox(height: 12),
                        BrutalTextInput(
                          controller: _searchController,
                          hint: 'SEARCH INVENTORY...',
                          uppercase: true,
                          suffixIcon:
                              const Icon(Icons.search, size: 16, color: kGray400),
                          onChanged: (v) => setState(() => _searchTerm = v),
                        ),
                        if (_searchTerm.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          for (final item in _searchResults)
                            InkWell(
                              onTap: () => _addItem(item),
                              child: Container(
                                padding: const EdgeInsets.all(12),
                                decoration: const BoxDecoration(
                                  border: Border(
                                    bottom: BorderSide(color: kGray100),
                                  ),
                                ),
                                child: Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          MonoLabel(item.id, size: 9),
                                          Text(
                                            item.name.toUpperCase(),
                                            style: const TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.w600,
                                              color: kInk,
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    if (item.max != null)
                                      MonoLabel(
                                          'Available: ${item.max}', size: 10),
                                  ],
                                ),
                              ),
                            ),
                        ],
                        const SizedBox(height: 12),
                        if (_selectedItems.isEmpty)
                          const DashedBorder(
                            padding: EdgeInsets.all(16),
                            child: Center(
                              child: MonoLabel('Cart is empty',
                                  color: kGray400),
                            ),
                          )
                        else
                          for (final item in _selectedItems)
                            Container(
                              margin: const EdgeInsets.only(bottom: 8),
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: kGray50,
                                border: Border.all(color: kGray200),
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          item.name.toUpperCase(),
                                          style: const TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.bold,
                                            color: kInk,
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        MonoLabel(item.id, size: 9),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  SizedBox(
                                    width: 72,
                                    child: BrutalTextInput(
                                      controller: _qtyControllerFor(item),
                                      keyboardType: TextInputType.number,
                                      textAlign: TextAlign.center,
                                      minHeight: 36,
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                              vertical: 8, horizontal: 8),
                                      onChanged: (v) =>
                                          _updateQty(item.id, v),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  InkWell(
                                    onTap: () => _removeItem(item.id),
                                    child: Container(
                                      padding: const EdgeInsets.all(8),
                                      decoration: BoxDecoration(
                                        border:
                                            Border.all(color: kBorderDark),
                                      ),
                                      child: const Icon(Icons.close,
                                          size: 14, color: kInk),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  BrutalButton(
                    label:
                        _submitting ? 'Submitting...' : 'Submit Transaction',
                    filled: true,
                    padding: const EdgeInsets.all(16),
                    onPressed: _submitting ? null : _submit,
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _FormDateButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _FormDateButton({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        decoration: BoxDecoration(
          color: kGray50,
          border: Border.all(color: kBorderDark, width: 1),
        ),
        child: Row(
          children: [
            const Icon(Icons.calendar_today_outlined,
                size: 14, color: kGray400),
            const SizedBox(width: 8),
            Expanded(
              child: MonoLabel(
                label,
                size: 10,
                weight: FontWeight.w600,
                color: kInk,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionRecordCard extends StatelessWidget {
  final TransactionLog log;

  const _ActionRecordCard({required this.log});

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
                  MonoLabel(_formatTimestamp(log.timestamp), size: 9),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  MonoLabel(log.user, size: 11, weight: FontWeight.w700),
                ],
              ),
            ],
          ),
          if (log.section != null || log.factoryName != null) ...[
            const SizedBox(height: 10),
            Container(
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
            const SizedBox(height: 10),
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
                    _DetailLine(
                      label: log.type == LogType.incoming
                          ? 'SENT BY'
                          : 'REQUESTED BY',
                      value: log.person!,
                    ),
                  if (log.comingFrom != null)
                    _DetailLine(label: 'COMING FROM', value: log.comingFrom!),
                  if (log.dateOfArrival != null)
                    _DetailLine(
                        label: 'DATE OF ARRIVAL', value: log.dateOfArrival!),
                  if (log.dateRequested != null)
                    _DetailLine(
                        label: 'DATE REQUESTED', value: log.dateRequested!),
                  if (log.dateLeaving != null)
                    _DetailLine(label: 'DATE LEAVING', value: log.dateLeaving!),
                  if (log.truckNumber != null)
                    _DetailLine(label: 'TRUCK NO.', value: log.truckNumber!),
                ],
              ),
            ),
          ],
          const SizedBox(height: 10),
          for (final item in log.items)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
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
                    '${item.quantityChange} ${_qtySuffix(log.type)}',
                    style: monoStyle(
                      size: 11,
                      weight: FontWeight.w700,
                      color: kInk,
                      letterSpacing: 0,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  String _qtySuffix(LogType type) {
    switch (type) {
      case LogType.incoming:
        return 'IN';
      case LogType.requestAccepted:
      case LogType.requestRejected:
      case LogType.requestUndone:
        return 'REQUESTED';
      case LogType.dispatch:
      case LogType.edit:
        return 'OUT';
    }
  }
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

class _ChoiceButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _ChoiceButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: kSurface,
      child: InkWell(
        onTap: onTap,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(32),
          decoration: BoxDecoration(
            border: Border.all(color: kBorderDark, width: 1),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 48, color: kInk),
              const SizedBox(height: 16),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 2, // tracking-widest
                  color: kInk,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
