import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

import '../controllers/inventory_controller.dart';
import '../models/factory.dart';
import '../models/inventory_item.dart';
import '../models/transaction_log.dart';
import '../models/viewer_request.dart';
import '../services/api_client.dart';
import '../services/auth_service.dart';
import '../services/request_service.dart';
import '../services/transaction_file_picker.dart';
import '../theme.dart';
import '../widgets/brutal.dart';
import '../widgets/attachment_preview.dart';
import '../widgets/section_tabs.dart' show FactoryFilterChips;

enum _TransactionForm { incoming, dispatch }

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

class TransactionsView extends StatefulWidget {
  final InventoryController controller;
  final Future<void> Function({
    required String type,
    required List<CartItem> items,
    String? notes,
    String? bill,
    String? billData,
    String? proof,
    String? proofData,
    required String user,
    InventorySection? section,
    String? person,
    String? comingFrom,
    String? dateOfArrival,
    String? dateRequested,
    String? dateLeaving,
    String? truckNumber,
    Uint8List? billBytes,
    Uint8List? proofBytes,
    List<TransactionAttachment> proofs,
    String? factoryId,
    List<String> sourceRequestIds,
  }) addTransaction;
  final AuthSession session;
  final InventorySection? fixedSection;
  final String? initialFactoryId;
  final TransactionFilePicker filePicker;
  final RequestService? requestService;

  const TransactionsView({
    super.key,
    required this.controller,
    required this.addTransaction,
    required this.session,
    this.fixedSection,
    this.initialFactoryId,
    this.filePicker = const PlatformTransactionFilePicker(),
    this.requestService,
  });

  @override
  State<TransactionsView> createState() => _TransactionsViewState();
}

class _TransactionsViewState extends State<TransactionsView> {
  late InventorySection _section;
  String? _factoryName;
  String? _factoryId;
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
  String? _bill;
  Uint8List? _billBytes;
  final List<TransactionAttachment> _proofs = [];
  String _searchTerm = '';
  bool _submitting = false;
  bool _pickingBill = false;
  bool _pickingProof = false;
  TransactionLog? _createdTransaction;
  late final RequestService _requestService;
  List<ViewerRequest> _acceptedRequests = const [];
  final Set<String> _sourceRequestIds = {};

  @override
  void initState() {
    super.initState();
    _section = widget.fixedSection ?? InventorySection.depot;
    _requestService = widget.requestService ?? RequestService();
    _selectInitialFactory();
    _loadAcceptedRequests();
  }

  Future<void> _loadAcceptedRequests() async {
    try {
      final requests = await _requestService.loadRequests();
      if (!mounted) return;
      setState(() {
        _acceptedRequests = requests
            .where((request) =>
                request.status == 'Accepted' &&
                request.relatedTransactionId == null)
            .toList();
      });
    } catch (_) {
      // Request linking is optional for transactions not fulfilling requests.
    }
  }

  List<ViewerRequest> get _linkableRequests {
    if (_activeForm != _TransactionForm.dispatch) return const [];
    final itemIds = _selectedItems.map((item) => item.id).toSet();
    final section = _section == InventorySection.sleeper ? 'Sleeper' : 'Depot';
    return _acceptedRequests
        .where((request) =>
            request.section == section &&
            (_section != InventorySection.sleeper ||
                request.factoryId == _factoryId) &&
            itemIds.contains(request.itemId))
        .toList();
  }

  void _selectInitialFactory() {
    final id = widget.initialFactoryId;
    if (id == null || _section != InventorySection.sleeper) return;
    final factory =
        widget.controller.factories.where((f) => f.id == id).firstOrNull;
    _factoryId = factory?.id;
    _factoryName = factory?.name;
  }

  bool get _canOperate =>
      widget.session.role == 'superadmin' || widget.session.role == 'admin';

  bool get _isFactoryScope =>
      _section == InventorySection.sleeper && _factoryId != null;

  String get _scopeLabel => _section == InventorySection.depot
      ? 'DEPOT'
      : 'SLEEPER${_factoryName != null ? ' · $_factoryName' : ''}';

  WarehouseFactory? get _scopeFactory {
    if (_factoryId == null) return null;
    for (final factory in widget.controller.factories) {
      if (factory.id == _factoryId) return factory;
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
      () => TextEditingController(
        text: item.quantityChange > 0 ? '${item.quantityChange}' : '',
      ),
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
      _bill = null;
      _billBytes = null;
      _proofs.clear();
      _sourceRequestIds.clear();
      _searchTerm = '';
      _submitting = false;
    });
  }

  void _selectFactory(String? id) {
    if (id == _factoryId) return;
    _resetForm();
    final factory = widget.controller.factories
        .where((factory) => factory.id == id)
        .firstOrNull;
    setState(() {
      _factoryName = factory?.name;
      _factoryId = factory?.id;
    });
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
                quantityChange: 0,
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
              materialNumber: item.materialNumber,
              name: item.name,
              quantityChange: 0,
              max: isIncoming ? null : item.available,
            ))
        .toList();
  }

  void _addItem(CartItem candidate) {
    if (_selectedItems.any((i) => i.id == candidate.id)) return;
    if (_selectedItems.length >= 100) {
      _showMessage('A transaction can contain at most 100 items.');
      return;
    }
    _qtyControllers[candidate.id] = TextEditingController();
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
      final parsed = int.tryParse(value.trim());
      final qty = parsed ?? 0;
      _selectedItems[index] = item.copyWith(quantityChange: qty);
    });
  }

  String? _quantityError(CartItem item) {
    final raw = _qtyControllers[item.id]?.text.trim() ?? '';
    if (raw.isEmpty) return 'Quantity is required';
    final quantity = int.tryParse(raw);
    if (quantity == null || quantity < 1) {
      return 'Enter a positive whole number';
    }
    if (quantity > 2147483647) return 'Quantity is too large';
    if (_activeForm == _TransactionForm.dispatch &&
        item.max != null &&
        quantity > item.max!) {
      return 'Maximum available: ${item.max}';
    }
    return null;
  }

  bool get _canSubmit {
    if (_submitting || _selectedItems.isEmpty || _billBytes == null) {
      return false;
    }
    if (_selectedItems.any((item) => _quantityError(item) != null)) {
      return false;
    }
    if (_section == InventorySection.sleeper && !_isFactoryScope) return false;
    final incoming = _activeForm == _TransactionForm.incoming;
    if (_truckController.text.trim().isEmpty) return false;
    if (incoming) {
      return _personController.text.trim().isNotEmpty &&
          _comingFromController.text.trim().isNotEmpty &&
          _dateOfArrival != null;
    }
    return _requestedByController.text.trim().isNotEmpty &&
        _dateRequested != null &&
        _dateLeaving != null &&
        !_dateLeaving!.isBefore(_dateRequested!);
  }

  List<String> get _validationProblems {
    final problems = <String>[];
    if (_billBytes == null) problems.add('Upload a Bill');
    if (_section == InventorySection.sleeper && !_isFactoryScope) {
      problems.add('Select a factory');
    }
    if (_selectedItems.isEmpty) {
      problems.add('Select at least one material');
    } else {
      for (final item in _selectedItems) {
        if (_quantityError(item) != null) {
          problems.add('Enter a valid quantity for ${item.name}');
        }
      }
    }
    final incoming = _activeForm == _TransactionForm.incoming;
    if (incoming) {
      if (_dateOfArrival == null) problems.add('Select the transaction date');
      if (_personController.text.trim().isEmpty) {
        problems.add('Enter the sender/vendor name');
      }
      if (_comingFromController.text.trim().isEmpty) {
        problems.add('Enter where the shipment came from');
      }
    } else {
      if (_dateRequested == null || _dateLeaving == null) {
        problems.add('Select the transaction dates');
      }
      if (_dateRequested != null &&
          _dateLeaving != null &&
          _dateLeaving!.isBefore(_dateRequested!)) {
        problems.add('Set leaving date on or after request date');
      }
      if (_requestedByController.text.trim().isEmpty) {
        problems.add('Enter who requested the materials');
      }
    }
    if (_truckController.text.trim().isEmpty) {
      problems.add('Enter the truck number');
    }
    return problems;
  }

  void _removeItem(String id) {
    _qtyControllers.remove(id)?.dispose();
    setState(() => _selectedItems.removeWhere((i) => i.id == id));
  }

  Future<void> _pickAttachment({
    required bool isBill,
    int? replaceProofIndex,
  }) async {
    if (isBill ? _pickingBill : _pickingProof) return;
    setState(() {
      if (isBill) {
        _pickingBill = true;
      } else {
        _pickingProof = true;
      }
    });
    List<PickedTransactionFile>? files;
    try {
      files = await widget.filePicker
          .pick(allowMultiple: !isBill && replaceProofIndex == null);
    } catch (error, stackTrace) {
      if (kDebugMode) {
        debugPrint(
            'Transaction file picker failed (${isBill ? 'Bill' : 'Proof'}, multiple: ${!isBill && replaceProofIndex == null}, picker: ${widget.filePicker.runtimeType}): $error\n$stackTrace');
      }
      _showMessage(kDebugMode
          ? 'Unable to open the file picker: ${error.runtimeType}: $error'
          : 'Unable to open the file picker. Please try again.');
      if (mounted) {
        setState(() {
          _pickingBill = false;
          _pickingProof = false;
        });
      }
      return;
    }
    if (!mounted) return;
    setState(() {
      _pickingBill = false;
      _pickingProof = false;
    });
    if (files == null) return;
    if (files.isEmpty) {
      _showMessage('No file was selected.');
      return;
    }
    final attachments = <TransactionAttachment>[];
    for (final file in files) {
      final extension = file.name.split('.').last.toLowerCase();
      if (!const {'pdf', 'jpg', 'jpeg', 'png', 'webp'}.contains(extension)) {
        _showMessage('This file type is not supported.');
        return;
      }
      final bytes = file.bytes;
      if (bytes == null) {
        _showMessage('Unable to read the selected file.');
        return;
      }
      if (bytes.isEmpty) {
        _showMessage('The selected file is empty.');
        return;
      }
      if (bytes.lengthInBytes > 10 * 1024 * 1024) {
        _showMessage('Files must be 10 MB or smaller.');
        return;
      }
      attachments.add(TransactionAttachment(
        fileName: file.name,
        bytes: bytes,
        contentType: extension == 'pdf'
            ? 'application/pdf'
            : 'image/${extension == 'jpg' ? 'jpeg' : extension}',
      ));
    }
    setState(() {
      if (isBill) {
        _bill = attachments.first.fileName;
        _billBytes = attachments.first.bytes;
      } else if (replaceProofIndex != null) {
        _proofs[replaceProofIndex] = attachments.first;
      } else {
        for (final attachment in attachments) {
          final duplicate = _proofs.any((proof) =>
              proof.fileName.toLowerCase() ==
                  attachment.fileName.toLowerCase() &&
              proof.bytes?.lengthInBytes == attachment.bytes?.lengthInBytes);
          if (!duplicate) _proofs.add(attachment);
        }
      }
    });
  }

  void _removeAttachment({required bool isBill}) {
    setState(() {
      if (isBill) {
        _bill = null;
        _billBytes = null;
      }
    });
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
    if (_section == InventorySection.sleeper && !_isFactoryScope) {
      _showMessage('Select a factory before creating a Sleeper transaction.');
      return;
    }
    if (_selectedItems.isEmpty) {
      _showMessage('Add at least one item.');
      return;
    }
    final parsedItems = <CartItem>[];
    final hasInvalidQty = _selectedItems.any((item) {
      final error = _quantityError(item);
      final parsed = int.tryParse(_qtyControllers[item.id]?.text.trim() ?? '');
      if (error == null && parsed != null) {
        parsedItems.add(item.copyWith(quantityChange: parsed));
      }
      return error != null;
    });
    if (hasInvalidQty) {
      _showMessage('All items must have a quantity of 1 or more.');
      return;
    }
    if (_bill == null || _billBytes == null) {
      _showMessage(
          'Please upload the Bill before submitting this transaction.');
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
        if (sel.max != null && sel.max! < sel.quantityChange) {
          _showMessage('Insufficient available stock for dispatch.');
          return;
        }
      }
    }

    setState(() => _submitting = true);
    final previousIds = widget.controller.logs.map((log) => log.id).toSet();
    try {
      await widget.addTransaction(
        type: isIncoming ? LogType.incoming.label : LogType.dispatch.label,
        items: parsedItems,
        bill: _bill!,
        billBytes: _billBytes,
        proof: null,
        proofBytes: null,
        proofs: List.unmodifiable(_proofs),
        user: widget.session.username,
        section: _section,
        factoryId: _factoryId,
        sourceRequestIds: _sourceRequestIds.toList(),
        person: isIncoming ? person : requestedBy,
        comingFrom: isIncoming ? comingFrom : null,
        dateOfArrival: isIncoming ? _isoDate(_dateOfArrival!) : null,
        dateRequested: isIncoming ? null : _isoDate(_dateRequested!),
        dateLeaving: isIncoming ? null : _isoDate(_dateLeaving!),
        truckNumber: truck,
      );
    } catch (error) {
      if (mounted) {
        setState(() => _submitting = false);
        _showMessage(error.toString());
      }
      return;
    }
    if (!mounted) return;
    final created = widget.controller.logs
        .where((log) => !previousIds.contains(log.id))
        .firstOrNull;
    _resetForm();
    setState(() => _createdTransaction = created);
    _showMessage('Transaction completed successfully.');
  }

  String _isoDate(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final created = _createdTransaction;
    if (created != null) {
      return SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: MaxWidth(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'TRANSACTION CREATED',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: kInk,
                ),
              ),
              const SizedBox(height: 16),
              ActionRecordCard(
                log: created,
                downloadFile: widget.controller.downloadFile,
              ),
              BrutalButton(
                label: 'BACK TO ACTIONS',
                onPressed: () => setState(() => _createdTransaction = null),
              ),
            ],
          ),
        ),
      );
    }
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
              Text(
                _section == InventorySection.depot
                    ? 'DEPOT ACTIONS'
                    : 'SLEEPER ACTIONS',
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  letterSpacing: -0.5,
                  color: kInk,
                ),
              ),
              const SizedBox(height: 14),
              if (_section == InventorySection.sleeper) ...[
                const MonoLabel('SELECT FACTORY', weight: FontWeight.w600),
                const SizedBox(height: 8),
                FactoryFilterChips(
                  factories: widget.controller.factories,
                  selectedFactoryId: _factoryId,
                  onChanged: _selectFactory,
                  includeAll: false,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLanding() {
    if (_canOperate) {
      return Column(
        children: [
          Expanded(child: _buildChooser()),
        ],
      );
    }
    return const SizedBox.shrink();
  }

  Widget _buildChooser() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: MaxWidth(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (_section == InventorySection.sleeper) ...[
                    MonoLabel(_scopeLabel, color: kGray400),
                    const SizedBox(height: 16),
                  ],
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
          ),
        ),
      ),
    );
  }

  Widget _buildAttachmentCard({
    required String label,
    required String? file,
    required Uint8List? bytes,
    required VoidCallback onPick,
    required VoidCallback onRemove,
    required bool requiredAttachment,
    Key? uploadKey,
  }) {
    return BrutalCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          MonoLabel(
            '${label.toUpperCase()}${requiredAttachment ? ' *' : ' (OPTIONAL)'}',
            weight: FontWeight.w600,
          ),
          const SizedBox(height: 12),
          if (file != null && bytes != null)
            Container(
              width: double.infinity,
              decoration: BoxDecoration(
                border: Border.all(color: kBorderDark, width: 1),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (file.toLowerCase().endsWith('.pdf'))
                    const SizedBox(
                      height: 140,
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.picture_as_pdf_outlined, size: 40),
                            SizedBox(height: 8),
                            MonoLabel('PDF DOCUMENT'),
                          ],
                        ),
                      ),
                    )
                  else
                    ClipRect(
                      child: Image.memory(
                        bytes,
                        height: 140,
                        fit: BoxFit.contain,
                        errorBuilder: (_, __, ___) => Container(
                          height: 140,
                          color: kGray50,
                          child: const Center(
                            child: MonoLabel(
                              'Unable to display this image.',
                              color: kRed,
                            ),
                          ),
                        ),
                      ),
                    ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    color: kInk,
                    child: Row(
                      children: [
                        const Icon(
                          Icons.check_circle_outline,
                          size: 14,
                          color: kSurface,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            file,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: monoStyle(size: 9, color: kSurface),
                          ),
                        ),
                        MonoLabel(
                          '${file.toLowerCase().endsWith('.pdf') ? 'PDF' : 'IMAGE'} | ${bytes.lengthInBytes} BYTES',
                          size: 8,
                          color: kSurface,
                        ),
                        const SizedBox(width: 8),
                        _AttachmentAction(
                          icon: Icons.visibility_outlined,
                          tooltip: 'Preview $label',
                          onTap: () => showAttachmentPreview(
                            context,
                            fileName: file,
                            bytes: bytes,
                            contentType: file.toLowerCase().endsWith('.pdf')
                                ? 'application/pdf'
                                : null,
                          ),
                        ),
                        const SizedBox(width: 6),
                        _AttachmentAction(
                          icon: Icons.refresh,
                          tooltip: 'Replace $label',
                          onTap: onPick,
                        ),
                        const SizedBox(width: 6),
                        _AttachmentAction(
                          icon: Icons.delete_outline,
                          tooltip: 'Remove $label',
                          onTap: onRemove,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            )
          else
            InkWell(
              key: uploadKey,
              onTap: onPick,
              child: Container(
                width: double.infinity,
                color: kGray50,
                child: DashedBorder(
                  color: kGray300,
                  width: 2,
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    children: [
                      const Icon(
                        Icons.upload_file_outlined,
                        size: 24,
                        color: kGray400,
                      ),
                      const SizedBox(height: 8),
                      MonoLabel(
                        requiredAttachment ? 'Upload Bill' : 'Add Proof',
                        color: kGray400,
                      ),
                      const SizedBox(height: 4),
                      const MonoLabel('PDF, JPG, PNG or WebP',
                          size: 8, color: kGray400),
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
            controller: isIncoming ? _personController : _requestedByController,
            label: isIncoming ? 'Person Who Sent Order' : 'Requested By',
            hint: isIncoming ? 'Sender / vendor name' : 'Who the items are for',
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 12),
          if (isIncoming) ...[
            BrutalTextInput(
              controller: _comingFromController,
              label: 'Coming From',
              hint: 'Origin / location',
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            _FormDateButton(
              label: _dateOfArrival == null
                  ? 'SET DATE OF ARRIVAL'
                  : _formatDate(_dateOfArrival!),
              onTap: () => _pickDate(_dateOfArrival, (d) => _dateOfArrival = d),
            ),
          ] else ...[
            _FormDateButton(
              label: _dateRequested == null
                  ? 'SET DATE REQUESTED'
                  : _formatDate(_dateRequested!),
              onTap: () => _pickDate(_dateRequested, (d) => _dateRequested = d),
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
            onChanged: (_) => setState(() {}),
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
              Expanded(
                child: Column(
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
                    Text(
                      _scopeLabel.toUpperCase(),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: monoStyle(size: 9, color: kGray400),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
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
                  _buildAttachmentCard(
                    label: 'Bill',
                    file: _bill,
                    bytes: _billBytes,
                    onPick: () => _pickAttachment(isBill: true),
                    onRemove: () => _removeAttachment(isBill: true),
                    requiredAttachment: true,
                    uploadKey: const ValueKey('upload-bill'),
                  ),
                  if (_proofs.isNotEmpty)
                    MonoLabel('PROOFS (${_proofs.length})',
                        weight: FontWeight.w700),
                  for (final indexed in _proofs.indexed) ...[
                    const SizedBox(height: 8),
                    _buildAttachmentCard(
                      label: 'Proof',
                      file: indexed.$2.fileName,
                      bytes: indexed.$2.bytes,
                      onPick: () => _pickAttachment(
                          isBill: false, replaceProofIndex: indexed.$1),
                      onRemove: () =>
                          setState(() => _proofs.removeAt(indexed.$1)),
                      requiredAttachment: false,
                    ),
                  ],
                  const SizedBox(height: 16),
                  _buildAttachmentCard(
                    label: _proofs.isEmpty ? 'Proof' : 'Add Another Proof',
                    file: null,
                    bytes: null,
                    onPick: () => _pickAttachment(isBill: false),
                    onRemove: () {},
                    requiredAttachment: false,
                    uploadKey: const ValueKey('add-proof'),
                  ),
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
                          suffixIcon: const Icon(Icons.search,
                              size: 16, color: kGray400),
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
                                          MonoLabel(item.materialNumber,
                                              size: 9),
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
                                      MonoLabel('Available: ${item.max}',
                                          size: 10),
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
                              child: MonoLabel(
                                'Search and add one or more materials to this transaction.',
                                color: kGray400,
                              ),
                            ),
                          )
                        else
                          for (final item in _selectedItems)
                            Container(
                              key: ValueKey('transaction-item-${item.id}'),
                              margin: const EdgeInsets.only(bottom: 8),
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: kGray50,
                                border: Border.all(color: kGray200),
                              ),
                              child: Column(
                                children: [
                                  Row(
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
                                            MonoLabel(item.materialNumber,
                                                size: 9),
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
                                  if (_quantityError(item)
                                      case final error?) ...[
                                    const SizedBox(height: 6),
                                    Align(
                                      alignment: Alignment.centerRight,
                                      child: MonoLabel(error,
                                          size: 8, color: kRed),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  if (_linkableRequests.isNotEmpty) ...[
                    BrutalCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const MonoLabel(
                            'FULFILLED VIEWER REQUESTS',
                            weight: FontWeight.w700,
                          ),
                          const SizedBox(height: 6),
                          const MonoLabel(
                            'Select accepted requests fulfilled by this dispatch.',
                            size: 9,
                            color: kGray400,
                          ),
                          const SizedBox(height: 8),
                          for (final request in _linkableRequests)
                            CheckboxListTile(
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              value: _sourceRequestIds.contains(request.id),
                              title: Text(
                                '${request.itemName} - ${request.quantity}',
                                style: monoStyle(size: 10, color: kInk),
                              ),
                              subtitle: MonoLabel(
                                '${request.viewerName} | ${request.materialNumber}',
                                size: 8,
                              ),
                              onChanged: _submitting
                                  ? null
                                  : (selected) => setState(() {
                                        if (selected == true) {
                                          _sourceRequestIds.add(request.id);
                                        } else {
                                          _sourceRequestIds.remove(request.id);
                                        }
                                      }),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],
                  if (_validationProblems.isNotEmpty) ...[
                    BrutalCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const MonoLabel(
                              'Complete the following before submitting:',
                              weight: FontWeight.w700,
                              color: kRed),
                          const SizedBox(height: 8),
                          for (final problem in _validationProblems)
                            Text('- $problem',
                                style: monoStyle(size: 9, color: kRed)),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  BrutalButton(
                    label: _submitting ? 'Submitting...' : 'Submit Transaction',
                    filled: true,
                    padding: const EdgeInsets.all(16),
                    onPressed: _canSubmit ? _submit : null,
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

class _AttachmentAction extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  const _AttachmentAction({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Icon(icon, size: 16, color: kSurface),
        ),
      ),
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

class ActionRecordCard extends StatelessWidget {
  final TransactionLog log;
  final Future<Uint8List> Function(String fileId)? downloadFile;

  const ActionRecordCard({super.key, required this.log, this.downloadFile});

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
          const SizedBox(height: 12),
          const MonoLabel('BILL', weight: FontWeight.w700),
          if (log.bill != null ||
              log.billFileId != null ||
              log.billData != null)
            _RecordAttachment(
              label: 'View Bill',
              fileName: log.bill,
              data: log.billData,
              fileId: log.billFileId,
              downloadFile: downloadFile,
            )
          else
            const MonoLabel('Bill: Not available', color: kGray400),
          const SizedBox(height: 12),
          MonoLabel(
              'PROOFS (${log.proofs.isNotEmpty ? log.proofs.length : (log.proof != null || log.proofFileId != null || log.proofData != null ? 1 : 0)})',
              weight: FontWeight.w700),
          if (log.proofs.isEmpty &&
              log.proof == null &&
              log.proofFileId == null &&
              log.proofData == null)
            const MonoLabel('No proof attached', color: kGray400)
          else if (log.proofs.isNotEmpty)
            for (final indexed in log.proofs.indexed)
              _RecordAttachment(
                label: 'View Proof ${indexed.$1 + 1}',
                fileName: indexed.$2.fileName,
                data: null,
                fileId: indexed.$2.fileId,
                attachmentBytes: indexed.$2.bytes,
                contentType: indexed.$2.contentType,
                downloadFile: downloadFile,
              )
          else
            _RecordAttachment(
              label: 'View Proof',
              fileName: log.proof,
              data: log.proofData,
              fileId: log.proofFileId,
              downloadFile: downloadFile,
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

class _RecordAttachment extends StatelessWidget {
  final String label;
  final String? fileName;
  final String? data;
  final String? fileId;
  final Uint8List? attachmentBytes;
  final String? contentType;
  final Future<Uint8List> Function(String fileId)? downloadFile;

  const _RecordAttachment({
    required this.label,
    required this.fileName,
    required this.data,
    required this.fileId,
    this.attachmentBytes,
    this.contentType,
    this.downloadFile,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: data == null && fileId == null && attachmentBytes == null
          ? null
          : () => _showPreview(context),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 260),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: kPaper,
          border: Border.all(color: kBorderDark),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              data == null && fileId == null
                  ? Icons.image_outlined
                  : Icons.visibility_outlined,
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

  Future<void> _showPreview(BuildContext context) async {
    Uint8List bytes;
    try {
      final encoded = data;
      if (attachmentBytes != null) {
        bytes = attachmentBytes!;
      } else if (encoded != null && encoded.isNotEmpty) {
        bytes = base64Decode(encoded);
      } else if (fileId != null) {
        final loader = downloadFile;
        if (loader == null) return;
        bytes = await loader(fileId!);
      } else {
        return;
      }
    } on ApiException catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error.message)),
        );
      }
      return;
    } catch (_) {
      return;
    }
    if (!context.mounted) return;
    await showAttachmentPreview(
      context,
      fileName: fileName ?? 'Attachment',
      bytes: bytes,
      contentType: contentType,
    );
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
