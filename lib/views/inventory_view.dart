import 'package:flutter/material.dart';

import '../controllers/inventory_controller.dart';
import '../models/factory.dart';
import '../models/inventory_item.dart';
import '../models/purchase_order_status.dart';
import '../services/auth_service.dart';
import '../theme.dart';
import '../widgets/brutal.dart';

enum _InventorySort {
  recentSearched('Recent Searched'),
  recentEdited('Recent Edited'),
  nameAsc('Alphabetical A-Z'),
  nameDesc('Alphabetical Z-A');

  const _InventorySort(this.label);

  final String label;
}

void _noop() {}

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

String _formatDate(DateTime date) {
  final local = date.toLocal();
  return '${local.day} ${_months[local.month - 1]} ${local.year}';
}

String? _purchaseOrderError(
  int incoming,
  DateTime? expected,
  PurchaseOrderStatus status,
) {
  if (status == PurchaseOrderStatus.none) {
    return incoming == 0 && expected == null
        ? null
        : 'No Incoming Order requires zero incoming quantity and no date.';
  }
  if (incoming < 1) {
    return 'Select an incoming quantity greater than zero.';
  }
  if (status == PurchaseOrderStatus.ordered && expected == null) {
    return 'Ordered stock requires an expected availability date.';
  }
  return null;
}

class InventoryView extends StatefulWidget {
  final InventoryController controller;
  final AuthSession session;

  /// When provided, the view pins itself to this section on mount. Used by
  /// the Viewer shell so Depot and Sleeper are separate pages. The section
  /// selector is hidden for the Viewer via [showSectionTabs].
  final InventorySection? initialSection;
  final bool showSectionTabs;
  final ValueChanged<String?>? onOpenSleeperActions;

  const InventoryView({
    super.key,
    required this.controller,
    required this.session,
    this.initialSection,
    this.showSectionTabs = true,
    this.onOpenSleeperActions,
  });

  @override
  State<InventoryView> createState() => _InventoryViewState();
}

class _InventoryViewState extends State<InventoryView> {
  final _searchController = TextEditingController();
  String _searchTerm = '';
  String? _lastRegisteredTerm;
  bool _frequentOnly = false;
  _InventorySort _sort = _InventorySort.recentSearched;
  String? _selectedFactoryId;
  String? _deletingFactoryId;

  @override
  void initState() {
    super.initState();
    final initial = widget.initialSection;
    if (initial != null && _controller.activeSection != initial) {
      // Set without notifying: this subtree is already being built, so the
      // view reads the value directly and no rebuild needs to be scheduled.
      _controller.setSection(initial, notify: false);
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  InventoryController get _controller => widget.controller;

  // Mirrors the existing permission gate in HomeShell (_canOperate):
  // superadmin and admin may manage materials; viewer stays read-only.
  bool get _canManage =>
      widget.session.role == 'superadmin' || widget.session.role == 'admin';

  bool get _canDeleteFactory => widget.session.role == 'superadmin';
  bool get _factoryDeletionSupported => _controller.supportsFactoryDeletion;

  List<InventoryItem> get _sectionItems =>
      _controller.itemsInSection(_controller.activeSection);

  /// The factory currently open under the Sleeper section, if any.
  WarehouseFactory? get _openFactory {
    for (final factory in _controller.factories) {
      if (factory.id == _selectedFactoryId) return factory;
    }
    return null;
  }

  bool get _showingFactoryList =>
      _controller.activeSection == InventorySection.sleeper &&
      _openFactory == null;

  /// Links a factory material PL to the matching main-inventory item (by id)
  /// so recency/frequency data is reused where applicable.
  InventoryItem? _linkedItem(String pl) {
    final key = pl.trim().toLowerCase();
    for (final item in _controller.inventory) {
      if (item.id.trim().toLowerCase() == key) return item;
    }
    return null;
  }

  List<InventoryItem> get _displayItems {
    final term = _searchTerm.toLowerCase().trim();
    final filtered = _sectionItems.where((item) {
      if (term.isEmpty) return true;
      return item.id.toLowerCase().contains(term) ||
          item.name.toLowerCase().contains(term);
    }).toList();

    if (_frequentOnly) {
      // Most Frequently Searched: highest count first; zero-stock still sinks.
      filtered.sort((a, b) {
        final freq = b.searchFrequency.compareTo(a.searchFrequency);
        if (freq != 0) return freq;
        return _zeroStockCompare(a, b);
      });
      return filtered;
    }

    filtered.sort(_compareItems);
    return filtered;
  }

  int _compareItems(InventoryItem a, InventoryItem b) {
    switch (_sort) {
      case _InventorySort.recentSearched:
        return _compareByRecent(a.lastSearchedAt, b.lastSearchedAt, a, b);
      case _InventorySort.recentEdited:
        return _compareByRecent(a.lastEditedAt, b.lastEditedAt, a, b);
      case _InventorySort.nameAsc:
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      case _InventorySort.nameDesc:
        return b.name.toLowerCase().compareTo(a.name.toLowerCase());
    }
  }

  int _compareByRecent(
    DateTime? at,
    DateTime? bt,
    InventoryItem a,
    InventoryItem b,
  ) {
    if (at != null && bt != null) return bt.compareTo(at);
    if (at != null) return -1;
    if (bt != null) return 1;
    // No history for either: fall back to the normal inventory ordering.
    return _zeroStockCompare(a, b);
  }

  int _zeroStockCompare(InventoryItem a, InventoryItem b) {
    if (a.isOutOfStock() && !b.isOutOfStock()) return 1;
    if (!a.isOutOfStock() && b.isOutOfStock()) return -1;
    return 0;
  }

  List<FactoryMaterial> get _factoryDisplayMaterials {
    final factory = _openFactory;
    if (factory == null) return const [];
    final term = _searchTerm.toLowerCase().trim();
    final filtered = factory.materials.where((m) {
      if (term.isEmpty) return true;
      return m.id.toLowerCase().contains(term) ||
          m.name.toLowerCase().contains(term);
    }).toList();

    if (_frequentOnly) {
      filtered.sort((a, b) {
        final fa = _linkedItem(a.id)?.searchFrequency ?? 0;
        final fb = _linkedItem(b.id)?.searchFrequency ?? 0;
        final freq = fb.compareTo(fa);
        if (freq != 0) return freq;
        return _zeroStockCompareM(a, b);
      });
      return filtered;
    }

    filtered.sort(_compareFactoryMaterials);
    return filtered;
  }

  int _compareFactoryMaterials(FactoryMaterial a, FactoryMaterial b) {
    switch (_sort) {
      case _InventorySort.recentSearched:
        return _compareByRecentM(
          _linkedItem(a.id)?.lastSearchedAt,
          _linkedItem(b.id)?.lastSearchedAt,
          a,
          b,
        );
      case _InventorySort.recentEdited:
        return _compareByRecentM(
          _linkedItem(a.id)?.lastEditedAt,
          _linkedItem(b.id)?.lastEditedAt,
          a,
          b,
        );
      case _InventorySort.nameAsc:
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      case _InventorySort.nameDesc:
        return b.name.toLowerCase().compareTo(a.name.toLowerCase());
    }
  }

  int _compareByRecentM(
    DateTime? at,
    DateTime? bt,
    FactoryMaterial a,
    FactoryMaterial b,
  ) {
    if (at != null && bt != null) return bt.compareTo(at);
    if (at != null) return -1;
    if (bt != null) return 1;
    return _zeroStockCompareM(a, b);
  }

  int _zeroStockCompareM(FactoryMaterial a, FactoryMaterial b) {
    if (a.isOutOfStock() && !b.isOutOfStock()) return 1;
    if (!a.isOutOfStock() && b.isOutOfStock()) return -1;
    return 0;
  }

  bool get _hasSearchHistory => _sectionItems.any((i) => i.searchFrequency > 0);

  bool get _hasFactorySearchHistory {
    final factory = _openFactory;
    if (factory == null) return false;
    return factory.materials
        .any((m) => (_linkedItem(m.id)?.searchFrequency ?? 0) > 0);
  }

  Future<void> _onSearchChanged(String value) async {
    setState(() => _searchTerm = value);
    final term = value.toLowerCase().trim();
    if (term.isEmpty || term == _lastRegisteredTerm) return;
    final openFactory = _openFactory;
    if (openFactory != null) return;
    final List<String> ids;
    ids = _sectionItems
        .where((item) =>
            item.id.toLowerCase().contains(term) ||
            item.name.toLowerCase().contains(term))
        .map((m) => m.id)
        .toList();
    if (ids.isEmpty) return;
    _lastRegisteredTerm = term;
    final registered = await _controller.registerSearch(ids);
    if (!registered && mounted && _lastRegisteredTerm == term) {
      setState(() => _lastRegisteredTerm = null);
    }
  }

  void _selectSection(InventorySection section) {
    setState(() {
      _controller.setSection(section);
      _selectedFactoryId = null;
      _lastRegisteredTerm = null;
    });
  }

  void _enterFactory(String id) {
    widget.onOpenSleeperActions?.call(id);
    setState(() {
      _selectedFactoryId = id;
      _searchTerm = '';
      _searchController.clear();
      _lastRegisteredTerm = null;
      _frequentOnly = false;
    });
  }

  void _closeFactory() {
    widget.onOpenSleeperActions?.call(null);
    setState(() {
      _selectedFactoryId = null;
      _searchTerm = '';
      _searchController.clear();
      _lastRegisteredTerm = null;
      _frequentOnly = false;
    });
  }

  void _toggleFrequentOnly() => setState(() => _frequentOnly = !_frequentOnly);

  void _setSort(_InventorySort sort) => setState(() => _sort = sort);

  void _openAddSheet() {
    // Admin/Superadmin adds are Depot-only: no section chooser, always lands
    // in Depot. Viewer stays read-only (never reaches this sheet).
    final isManagedAdd =
        widget.session.role == 'admin' || widget.session.role == 'superadmin';
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: kPaper,
      shape: const RoundedRectangleBorder(),
      builder: (context) => _MaterialFormSheet(
        item: null,
        showSectionPicker: !isManagedAdd,
        title: isManagedAdd ? 'ADD MATERIALS - DEPOT' : null,
        validatePl: (value) {
          final v = value.trim().toLowerCase();
          if (v.isEmpty) return null;
          return _controller.inventory
                  .any((i) => i.id.trim().toLowerCase() == v)
              ? 'PL Number already exists'
              : null;
        },
        failureMessage: () => _controller.lastErrorMessage,
        onSubmit: _controller.addMaterial,
      ),
    );
  }

  void _openEditSheet(InventoryItem item) {
    // Admin/Superadmin editing preserves the item's current section
    // (Depot-only flow).
    final isManagedEdit =
        widget.session.role == 'admin' || widget.session.role == 'superadmin';
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: kPaper,
      shape: const RoundedRectangleBorder(),
      builder: (context) => _MaterialFormSheet(
        item: item,
        showSectionPicker: !isManagedEdit,
        validatePl: (value) {
          final v = value.trim().toLowerCase();
          if (v.isEmpty) return null;
          return _controller.inventory
                  .any((i) => i.id.trim().toLowerCase() == v && i.id != item.id)
              ? 'PL Number already exists'
              : null;
        },
        failureMessage: () => _controller.lastErrorMessage,
        onSubmit: ({
          required String id,
          required String name,
          required InventorySection section,
          required int total,
          required int biIssued,
          required int incomingQuantity,
          required DateTime? expectedAvailabilityDate,
          required PurchaseOrderStatus purchaseOrderStatus,
          String? reason,
        }) =>
            _controller.editMaterial(
          originalId: item.id,
          id: id,
          name: name,
          section: section,
          total: total,
          biIssued: biIssued,
          incomingQuantity: incomingQuantity,
          expectedAvailabilityDate: expectedAvailabilityDate,
          purchaseOrderStatus: purchaseOrderStatus,
          reason: reason,
        ),
      ),
    );
  }

  void _openEditFactoryMaterialSheet(
      WarehouseFactory factory, FactoryMaterial material) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: kPaper,
      shape: const RoundedRectangleBorder(),
      builder: (context) => _FactoryMaterialFormSheet(
        factoryName: factory.name,
        material: material,
        validatePl: (value) {
          final v = value.trim().toLowerCase();
          if (v.isEmpty) return null;
          return factory.materials.any(
                  (m) => m.id != material.id && m.id.trim().toLowerCase() == v)
              ? 'PL Number already exists in this factory'
              : null;
        },
        failureMessage: () => _controller.lastErrorMessage,
        onSubmit: ({
          required String id,
          required String name,
          required int total,
          required int biIssued,
          required int incomingQuantity,
          required DateTime? expectedAvailabilityDate,
          required PurchaseOrderStatus purchaseOrderStatus,
          String? reason,
        }) =>
            _controller.editFactoryMaterial(
          factoryId: factory.id,
          materialId: material.id,
          id: id,
          name: name,
          total: total,
          biIssued: biIssued,
          incomingQuantity: incomingQuantity,
          expectedAvailabilityDate: expectedAvailabilityDate,
          purchaseOrderStatus: purchaseOrderStatus,
          reason: reason,
        ),
      ),
    );
  }

  void _openAddFactoryMaterialSheet(WarehouseFactory factory) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: kPaper,
      shape: const RoundedRectangleBorder(),
      builder: (context) => _FactoryMaterialFormSheet(
        factoryName: factory.name,
        material: null,
        validatePl: (value) {
          final v = value.trim().toLowerCase();
          if (v.isEmpty) return null;
          return factory.materials.any((m) => m.id.trim().toLowerCase() == v)
              ? 'PL Number already exists in this factory'
              : null;
        },
        failureMessage: () => _controller.lastErrorMessage,
        onSubmit: ({
          required String id,
          required String name,
          required int total,
          required int biIssued,
          required int incomingQuantity,
          required DateTime? expectedAvailabilityDate,
          required PurchaseOrderStatus purchaseOrderStatus,
          String? reason,
        }) =>
            _controller.addFactoryMaterial(
          factoryId: factory.id,
          id: id,
          name: name,
          total: total,
          biIssued: biIssued,
          incomingQuantity: incomingQuantity,
          expectedAvailabilityDate: expectedAvailabilityDate,
          purchaseOrderStatus: purchaseOrderStatus,
          reason: reason,
        ),
      ),
    );
  }

  void _openAddFactorySheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: kPaper,
      shape: const RoundedRectangleBorder(),
      builder: (context) => _FactoryFormSheet(
        onSubmit: _controller.addFactory,
        failureMessage: () => _controller.lastErrorMessage,
      ),
    );
  }

  Future<void> _confirmDeleteFactory(WarehouseFactory factory) async {
    if (!_canDeleteFactory ||
        !_factoryDeletionSupported ||
        _deletingFactoryId != null) {
      return;
    }
    final factoryId = factory.id;
    final factoryName = factory.name;
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (_) => _DeleteFactoryDialog(factoryName: factoryName),
        ) ??
        false;
    if (!confirmed || !mounted) return;

    final wasSelected = _selectedFactoryId == factoryId;
    setState(() {
      _deletingFactoryId = factoryId;
      if (wasSelected) _selectedFactoryId = null;
    });
    if (wasSelected) widget.onOpenSleeperActions?.call(null);
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;

    final deleted = await _controller.deleteFactory(factoryId);
    if (!mounted) return;
    setState(() {
      _deletingFactoryId = null;
      if (!deleted && wasSelected) _selectedFactoryId = factoryId;
    });
    if (!deleted && wasSelected) widget.onOpenSleeperActions?.call(factoryId);
    final message = deleted
        ? _controller.lastErrorMessage ?? 'Factory deleted.'
        : _controller.lastErrorMessage ?? 'Unable to delete factory.';
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _buildHeader(),
        Expanded(
          child: MaxWidth(child: _buildContent()),
        ),
      ],
    );
  }

  Widget _buildHeader() {
    final openFactory = _openFactory;
    final isFactoryMaterials = openFactory != null;
    final isFactoryList = !isFactoryMaterials &&
        _controller.activeSection == InventorySection.sleeper;
    // Search/sort/frequent apply to the Depot material list and to the
    // materials of the currently open factory; not to the factory list page.
    final showSearchAndFilters =
        _controller.activeSection == InventorySection.depot ||
            isFactoryMaterials;

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
              LayoutBuilder(
                builder: (context, constraints) {
                  final title = Text(
                    isFactoryMaterials ? openFactory.name : 'LIVE INVENTORY',
                    maxLines: constraints.maxWidth < 600 ? 2 : 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      letterSpacing: -0.5,
                      color: kInk,
                    ),
                  );
                  final actions = <Widget>[
                    if (isFactoryMaterials && _canManage)
                      BrutalButton(
                        label: 'ADD NEW MATERIALS - SLEEPER',
                        icon: Icons.add,
                        iconSize: 16,
                        filled: true,
                        allowLabelWrap: true,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        onPressed: () =>
                            _openAddFactoryMaterialSheet(openFactory),
                      ),
                    if (isFactoryMaterials &&
                        _canDeleteFactory &&
                        _factoryDeletionSupported)
                      BrutalButton(
                        label: _deletingFactoryId == openFactory.id
                            ? 'DELETING...'
                            : 'DELETE FACTORY',
                        icon: Icons.delete_outline,
                        iconSize: 16,
                        allowLabelWrap: true,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        onPressed: _deletingFactoryId == null
                            ? () => _confirmDeleteFactory(openFactory)
                            : null,
                      ),
                    if (isFactoryMaterials)
                      BrutalButton(
                        label: 'BACK TO SLEEPER',
                        icon: Icons.arrow_back,
                        iconSize: 16,
                        allowLabelWrap: true,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        onPressed: _closeFactory,
                      ),
                    if (!isFactoryMaterials && isFactoryList && _canManage)
                      BrutalButton(
                        label: 'ADD FACTORY',
                        icon: Icons.add_business_outlined,
                        iconSize: 16,
                        filled: true,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        onPressed: _openAddFactorySheet,
                      ),
                    if (!isFactoryMaterials && !isFactoryList && _canManage)
                      BrutalButton(
                        label: 'ADD MATERIAL',
                        icon: Icons.add,
                        iconSize: 16,
                        filled: true,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        onPressed: _openAddSheet,
                      ),
                  ];

                  if (isFactoryMaterials && constraints.maxWidth < 1100) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        title,
                        const SizedBox(height: 10),
                        Wrap(spacing: 8, runSpacing: 8, children: actions),
                      ],
                    );
                  }
                  return Row(
                    children: [
                      Expanded(child: title),
                      if (actions.isNotEmpty) ...[
                        const SizedBox(width: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: actions,
                        ),
                      ],
                    ],
                  );
                },
              ),
              if (widget.showSectionTabs) ...[
                const SizedBox(height: 14),
                _SectionSelector(
                  active: _controller.activeSection,
                  onChanged: _selectSection,
                ),
              ],
              if (isFactoryList) ...[
                const SizedBox(height: 12),
                const MonoLabel('Select a factory to view its materials',
                    color: kGray400),
              ],
              if (isFactoryMaterials && openFactory.location.isNotEmpty) ...[
                const SizedBox(height: 10),
                MonoLabel('Location: ${openFactory.location}', color: kGray400),
              ],
              if (showSearchAndFilters) ...[
                const SizedBox(height: 12),
                BrutalTextInput(
                  controller: _searchController,
                  hint: 'SEARCH ID OR DESCRIPTION',
                  uppercase: true,
                  prefixIcon:
                      const Icon(Icons.search, size: 18, color: kGray400),
                  onChanged: _onSearchChanged,
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    _FrequentFilterChip(
                      active: _frequentOnly,
                      onTap: _toggleFrequentOnly,
                    ),
                    _SortMenu(
                      value: _sort,
                      onChanged: _setSort,
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildContent() {
    if (_controller.lastErrorMessage != null &&
        _controller.inventory.isEmpty &&
        _controller.factories.isEmpty) {
      return Center(
        child: MonoLabel(_controller.lastErrorMessage!, color: kRed),
      );
    }
    if (_showingFactoryList) return _buildFactoryList();
    if (_openFactory != null) return _buildFactoryMaterialsContent();
    if (_frequentOnly && !_hasSearchHistory) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: MonoLabel(
              'No search history yet - showing all materials',
              color: kGray400,
              size: 9,
            ),
          ),
          Expanded(child: _buildList(_displayItems)),
        ],
      );
    }
    return _buildList(_displayItems);
  }

  Widget _buildFactoryList() {
    final factories = _controller.factories;
    if (factories.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.factory_outlined, size: 32, color: kGray400),
              SizedBox(height: 16),
              MonoLabel('No factories yet', color: kGray400),
            ],
          ),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: factories.length,
      itemBuilder: (context, index) {
        final factory = factories[index];
        return _FactoryCard(
          factory: factory,
          onTap: () => _enterFactory(factory.id),
          onDelete: _canDeleteFactory &&
                  _factoryDeletionSupported &&
                  _deletingFactoryId == null
              ? () => _confirmDeleteFactory(factory)
              : null,
          deleting: _deletingFactoryId == factory.id,
        );
      },
    );
  }

  Widget _buildFactoryMaterialsContent() {
    if (_frequentOnly && !_hasFactorySearchHistory) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: MonoLabel(
              'No search history yet - showing all materials',
              color: kGray400,
              size: 9,
            ),
          ),
          Expanded(child: _buildFactoryMaterialList(_factoryDisplayMaterials)),
        ],
      );
    }
    return _buildFactoryMaterialList(_factoryDisplayMaterials);
  }

  Widget _buildFactoryMaterialList(List<FactoryMaterial> items) {
    if (items.isEmpty) {
      if (_searchTerm.trim().isNotEmpty) return const _NoMatches();
      return _NoSectionItems(label: _openFactory!.name);
    }
    final factory = _openFactory!;
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final material = items[index];
        return _FactoryMaterialCard(
          material: material,
          canEdit: _canManage,
          onEdit: () => _openEditFactoryMaterialSheet(factory, material),
        );
      },
    );
  }

  Widget _buildList(List<InventoryItem> items) {
    if (items.isEmpty) {
      if (_searchTerm.trim().isNotEmpty) return const _NoMatches();
      return _NoSectionItems(label: _controller.activeSection.label);
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        return _MaterialCard(
          item: item,
          canEdit: _canManage,
          onEdit: () => _openEditSheet(item),
        );
      },
    );
  }
}

class _DeleteFactoryDialog extends StatefulWidget {
  final String factoryName;

  const _DeleteFactoryDialog({required this.factoryName});

  @override
  State<_DeleteFactoryDialog> createState() => _DeleteFactoryDialogState();
}

class _DeleteFactoryDialogState extends State<_DeleteFactoryDialog> {
  late final TextEditingController _confirmationController;
  bool _matches = false;

  @override
  void initState() {
    super.initState();
    _confirmationController = TextEditingController();
  }

  @override
  void dispose() {
    _confirmationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Delete Factory'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'This removes ${widget.factoryName} from active local factory lists. Existing transaction, request, and audit records are retained.',
              ),
              const SizedBox(height: 12),
              Text('Type ${widget.factoryName} exactly to confirm.'),
              const SizedBox(height: 8),
              TextField(
                key: const ValueKey('factory-delete-confirmation'),
                controller: _confirmationController,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Factory name'),
                onChanged: (value) {
                  final matches = value == widget.factoryName;
                  if (matches != _matches) setState(() => _matches = matches);
                },
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
          key: const ValueKey('confirm-factory-delete'),
          onPressed: _matches ? () => Navigator.of(context).pop(true) : null,
          child: const Text('Delete Factory'),
        ),
      ],
    );
  }
}

class _SectionSelector extends StatelessWidget {
  final InventorySection active;
  final ValueChanged<InventorySection> onChanged;

  const _SectionSelector({required this.active, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _SectionButton(
            label: 'Depot',
            isActive: active == InventorySection.depot,
            onTap: () => onChanged(InventorySection.depot),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _SectionButton(
            label: 'Sleeper',
            isActive: active == InventorySection.sleeper,
            onTap: () => onChanged(InventorySection.sleeper),
          ),
        ),
      ],
    );
  }
}

class _SectionButton extends StatelessWidget {
  final String label;
  final bool isActive;
  final VoidCallback onTap;

  const _SectionButton({
    required this.label,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: isActive ? kInk : kSurface,
          border: Border.all(color: kBorderDark, width: 1),
        ),
        child: MonoLabel(
          label,
          size: 11,
          weight: FontWeight.w600,
          color: isActive ? kSurface : kInk,
        ),
      ),
    );
  }
}

class _FrequentFilterChip extends StatelessWidget {
  final bool active;
  final VoidCallback onTap;

  const _FrequentFilterChip({required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: active ? kInk : kSurface,
          border: Border.all(color: kBorderDark, width: 1),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.trending_up, size: 14, color: active ? kSurface : kInk),
            const SizedBox(width: 6),
            Text(
              'Most Frequently Searched',
              style: monoStyle(
                size: 9,
                weight: FontWeight.w600,
                color: active ? kSurface : kInk,
                letterSpacing: 0.6,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SortMenu extends StatelessWidget {
  final _InventorySort value;
  final ValueChanged<_InventorySort> onChanged;

  const _SortMenu({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<_InventorySort>(
      onSelected: onChanged,
      color: kSurface,
      shape: const RoundedRectangleBorder(
        side: BorderSide(color: kBorderDark, width: 1),
      ),
      itemBuilder: (context) => [
        for (final option in _InventorySort.values)
          PopupMenuItem(
            value: option,
            child: Row(
              children: [
                if (option == value)
                  const Icon(Icons.check, size: 14, color: kInk)
                else
                  const SizedBox(width: 14),
                const SizedBox(width: 8),
                Text(
                  option.label,
                  style: monoStyle(size: 12, color: kInk),
                ),
              ],
            ),
          ),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: kSurface,
          border: Border.all(color: kBorderDark, width: 1),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.sort, size: 14, color: kInk),
            const SizedBox(width: 6),
            Text(
              'Sort: ${value.label}',
              style: monoStyle(
                size: 9,
                weight: FontWeight.w600,
                color: kInk,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(width: 2),
            const Icon(Icons.arrow_drop_down, size: 18, color: kInk),
          ],
        ),
      ),
    );
  }
}

class _MaterialCard extends StatefulWidget {
  final InventoryItem item;
  final bool canEdit;
  final VoidCallback onEdit;

  const _MaterialCard({
    required this.item,
    required this.canEdit,
    required this.onEdit,
  });

  @override
  State<_MaterialCard> createState() => _MaterialCardState();
}

class _MaterialCardState extends State<_MaterialCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final isAvailable = !item.isOutOfStock();

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: _hovered ? kGray50 : kSurface,
          border: Border.all(
            color: _hovered ? kInk : kBorderDark,
            width: 1,
          ),
          boxShadow: _hovered
              ? const [BoxShadow(offset: Offset(3, 3), color: kBorderDark)]
              : null,
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: MonoLabel(
                      item.id,
                      size: 10,
                      weight: FontWeight.w600,
                    ),
                  ),
                  _StatusBadge(available: isAvailable),
                  if (widget.canEdit) ...[
                    const SizedBox(width: 6),
                    _EditIconButton(onTap: widget.onEdit),
                  ],
                ],
              ),
              const SizedBox(height: 6),
              Opacity(
                opacity: isAvailable ? 1.0 : 0.55,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.name.toUpperCase(),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        height: 1.35,
                        letterSpacing: -0.2,
                        color: kInk,
                        decoration:
                            isAvailable ? null : TextDecoration.lineThrough,
                        decorationColor: kInk,
                      ),
                    ),
                    const SizedBox(height: 8),
                    _QuantityLine(
                      total: item.quantity,
                      biIssued: item.biIssued,
                      available: item.available,
                      uom: item.uom,
                    ),
                    _IncomingLine(
                      incomingQuantity: item.incomingQuantity,
                      expectedAvailabilityDate: item.expectedAvailabilityDate,
                      purchaseOrderStatus: item.purchaseOrderStatus,
                      emphasized: !isAvailable,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final bool available;

  const _StatusBadge({required this.available});

  @override
  Widget build(BuildContext context) {
    final color = available ? kGreen : kRed;
    final background =
        available ? const Color(0xFFE8F5E9) : const Color(0xFFFDECEA);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: background,
        border: Border.all(color: color, width: 1),
      ),
      child: MonoLabel(
        available ? 'AVAILABLE' : 'UNAVAILABLE',
        size: 8,
        weight: FontWeight.w600,
        color: color,
      ),
    );
  }
}

class _EditIconButton extends StatelessWidget {
  final VoidCallback onTap;

  const _EditIconButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: kSurface,
          border: Border.all(color: kBorderDark),
        ),
        child: const Icon(Icons.edit_outlined, size: 12, color: kInk),
      ),
    );
  }
}

class _NoSectionItems extends StatelessWidget {
  final String label;

  const _NoSectionItems({required this.label});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.inventory_2_outlined, size: 32, color: kGray400),
            const SizedBox(height: 16),
            MonoLabel('No Materials in $label', color: kGray400),
          ],
        ),
      ),
    );
  }
}

class _NoMatches extends StatelessWidget {
  const _NoMatches();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.inventory_2_outlined, size: 32, color: kGray400),
            SizedBox(height: 16),
            MonoLabel('No Matches', color: kGray400),
          ],
        ),
      ),
    );
  }
}

class _MaterialFormSheet extends StatefulWidget {
  final InventoryItem? item;
  final String? Function(String value) validatePl;
  final String? Function() failureMessage;
  final Future<bool> Function({
    required String id,
    required String name,
    required InventorySection section,
    required int total,
    required int biIssued,
    required int incomingQuantity,
    required DateTime? expectedAvailabilityDate,
    required PurchaseOrderStatus purchaseOrderStatus,
    String? reason,
  }) onSubmit;

  /// Hide the Depot/Sleeper/Both picker (Admin Depot-only flow). The section
  /// then stays at the item's current value, or Depot for a new material.
  final bool showSectionPicker;

  /// Optional header override, e.g. 'ADD MATERIALS - DEPOT'.
  final String? title;

  const _MaterialFormSheet({
    required this.item,
    required this.validatePl,
    required this.failureMessage,
    required this.onSubmit,
    this.showSectionPicker = true,
    this.title,
  });

  @override
  State<_MaterialFormSheet> createState() => _MaterialFormSheetState();
}

class _MaterialFormSheetState extends State<_MaterialFormSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _plController;
  late final TextEditingController _nameController;
  late final TextEditingController _totalController;
  late final TextEditingController _biController;
  late final TextEditingController _incomingController;
  late final TextEditingController _reasonController;
  late InventorySection _section;
  DateTime? _expectedDate;
  late PurchaseOrderStatus _poStatus;
  bool _saving = false;

  bool get _isEdit => widget.item != null;

  @override
  void initState() {
    super.initState();
    final item = widget.item;
    _plController = TextEditingController(text: item?.id ?? '');
    _nameController = TextEditingController(text: item?.name ?? '');
    _totalController =
        TextEditingController(text: item?.quantity.toString() ?? '');
    _biController =
        TextEditingController(text: item?.biIssued.toString() ?? '');
    _incomingController =
        TextEditingController(text: item?.incomingQuantity.toString() ?? '0');
    _reasonController = TextEditingController();
    _expectedDate = item?.expectedAvailabilityDate;
    _poStatus = item?.purchaseOrderStatus ?? PurchaseOrderStatus.none;
    _section = item?.section ?? InventorySection.depot;
  }

  @override
  void dispose() {
    _plController.dispose();
    _nameController.dispose();
    _totalController.dispose();
    _biController.dispose();
    _incomingController.dispose();
    _reasonController.dispose();
    super.dispose();
  }

  Future<void> _pickExpectedDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _expectedDate ?? now,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 5),
    );
    if (picked != null && mounted) {
      setState(() => _expectedDate = picked);
    }
  }

  String? _validatePl(String? value) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return 'PL Number is required';
    return widget.validatePl(v);
  }

  String? _validateQuantity(String? value, String field) {
    final v = (value ?? '').trim();
    if (v.isEmpty) return '$field is required';
    final parsed = int.tryParse(v);
    if (parsed == null) return 'Enter a valid number';
    if (parsed < 0) return 'Must be zero or more';
    if (parsed > 2147483647) return 'Must be 2147483647 or less';
    return null;
  }

  Future<void> _submit() async {
    if (_saving) return;
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final pl = _plController.text.trim();
    final total = int.parse(_totalController.text.trim());
    final biIssued = int.parse(_biController.text.trim());
    if (biIssued > total) {
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('BI Issued cannot exceed total quantity.')));
      return;
    }
    final incoming = int.parse(_incomingController.text.trim());
    final planningError =
        _purchaseOrderError(incoming, _expectedDate, _poStatus);
    if (planningError != null) {
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(planningError)),
      );
      return;
    }
    final ok = await widget.onSubmit(
      id: pl,
      name: _nameController.text.trim(),
      section: _section,
      total: total,
      biIssued: biIssued,
      incomingQuantity: incoming,
      expectedAvailabilityDate: _expectedDate,
      purchaseOrderStatus: _poStatus,
      reason: _reasonController.text.trim().isEmpty
          ? null
          : _reasonController.text.trim(),
    );
    if (!mounted) return;
    if (!ok) {
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            widget.failureMessage() ?? 'Could not save material: $pl',
          ),
        ),
      );
      return;
    }
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                widget.title ?? (_isEdit ? 'EDIT MATERIAL' : 'ADD MATERIAL'),
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  letterSpacing: -0.5,
                  color: kInk,
                ),
              ),
              const SizedBox(height: 4),
              MonoLabel(
                _isEdit ? 'PL: ${widget.item!.id}' : 'New material',
                color: kGray400,
              ),
              const SizedBox(height: 20),
              BrutalTextField(
                label: 'PL Number',
                controller: _plController,
                validator: _validatePl,
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: 12),
              BrutalTextField(
                label: 'Material Name / Description',
                controller: _nameController,
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Name is required' : null,
              ),
              if (widget.showSectionPicker) ...[
                const SizedBox(height: 16),
                const MonoLabel('Section', weight: FontWeight.w600),
                const SizedBox(height: 8),
                _SectionPicker(
                  value: _section,
                  onChanged: (s) => setState(() => _section = s),
                ),
              ],
              const SizedBox(height: 16),
              BrutalTextField(
                label: 'Total Available Quantity',
                controller: _totalController,
                keyboardType: TextInputType.number,
                validator: (v) => _validateQuantity(v, 'Total'),
              ),
              const SizedBox(height: 12),
              BrutalTextField(
                label: 'BI Issued Quantity',
                controller: _biController,
                keyboardType: TextInputType.number,
                validator: (v) => _validateQuantity(v, 'BI Issued'),
              ),
              const SizedBox(height: 16),
              BrutalTextField(
                label: 'Incoming / Purchase Order Quantity',
                controller: _incomingController,
                keyboardType: TextInputType.number,
                validator: (v) => _validateQuantity(v, 'Incoming'),
              ),
              const SizedBox(height: 16),
              const MonoLabel('Expected Availability Date',
                  weight: FontWeight.w600),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: _DatePickerButton(
                      label: _expectedDate == null
                          ? 'SET EXPECTED DATE'
                          : _formatDate(_expectedDate!),
                      onTap: _pickExpectedDate,
                    ),
                  ),
                  if (_expectedDate != null) ...[
                    const SizedBox(width: 8),
                    InkWell(
                      onTap: () => setState(() => _expectedDate = null),
                      child: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: kSurface,
                          border: Border.all(color: kBorderDark),
                        ),
                        child: const Icon(Icons.close, size: 14, color: kInk),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 16),
              _PurchaseOrderStatusPicker(
                value: _poStatus,
                onChanged: (status) => setState(() {
                  _poStatus = status;
                  if (status == PurchaseOrderStatus.none) {
                    _incomingController.text = '0';
                    _expectedDate = null;
                  }
                }),
              ),
              if (_isEdit) ...[
                const SizedBox(height: 16),
                BrutalTextField(
                    label: 'Reason (Optional)', controller: _reasonController),
              ],
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: BrutalButton(
                      label: 'CANCEL',
                      onPressed:
                          _saving ? null : () => Navigator.of(context).pop(),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: BrutalButton(
                      label: 'SAVE',
                      filled: true,
                      onPressed: _saving ? null : _submit,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionPicker extends StatelessWidget {
  final InventorySection value;
  final ValueChanged<InventorySection> onChanged;

  const _SectionPicker({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (final section in InventorySection.values) ...[
          Expanded(
            child: InkWell(
              onTap: () => onChanged(section),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 10),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: value == section ? kInk : kSurface,
                  border: Border.all(color: kBorderDark, width: 1),
                ),
                child: MonoLabel(
                  section.label,
                  size: 9,
                  weight: FontWeight.w600,
                  color: value == section ? kSurface : kInk,
                ),
              ),
            ),
          ),
          if (section != InventorySection.values.last) const SizedBox(width: 8),
        ],
      ],
    );
  }
}

class _FactoryCard extends StatefulWidget {
  final WarehouseFactory factory;
  final VoidCallback onTap;
  final VoidCallback? onDelete;
  final bool deleting;

  const _FactoryCard({
    required this.factory,
    required this.onTap,
    this.onDelete,
    this.deleting = false,
  });

  @override
  State<_FactoryCard> createState() => _FactoryCardState();
}

class _FactoryCardState extends State<_FactoryCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final factory = widget.factory;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: InkWell(
        onTap: widget.onTap,
        child: Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: _hovered ? kGray50 : kSurface,
            border: Border.all(
              color: _hovered ? kInk : kBorderDark,
              width: 1,
            ),
            boxShadow: _hovered
                ? const [BoxShadow(offset: Offset(3, 3), color: kBorderDark)]
                : null,
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                const Icon(Icons.factory_outlined, size: 22, color: kInk),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        factory.name.toUpperCase(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          letterSpacing: -0.2,
                          color: kInk,
                        ),
                      ),
                      const SizedBox(height: 2),
                      MonoLabel(factory.location, size: 9, color: kGray400),
                    ],
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: kSurface,
                    border: Border.all(color: kBorderDark, width: 1),
                  ),
                  child: MonoLabel(
                    '${factory.materials.length} MATERIALS',
                    size: 8,
                    weight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 8),
                if (widget.onDelete != null || widget.deleting) ...[
                  IconButton(
                    tooltip:
                        widget.deleting ? 'Deleting factory' : 'Delete factory',
                    onPressed: widget.deleting ? null : widget.onDelete,
                    icon: widget.deleting
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.delete_outline, size: 18),
                  ),
                  const SizedBox(width: 2),
                ],
                const Icon(Icons.chevron_right, size: 18, color: kInk),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FactoryMaterialCard extends StatefulWidget {
  final FactoryMaterial material;
  final bool canEdit;
  final VoidCallback onEdit;

  const _FactoryMaterialCard({
    required this.material,
    this.canEdit = false,
    this.onEdit = _noop,
  });

  @override
  State<_FactoryMaterialCard> createState() => _FactoryMaterialCardState();
}

class _FactoryMaterialCardState extends State<_FactoryMaterialCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final material = widget.material;
    final isAvailable = !material.isOutOfStock();

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: _hovered ? kGray50 : kSurface,
          border: Border.all(
            color: _hovered ? kInk : kBorderDark,
            width: 1,
          ),
          boxShadow: _hovered
              ? const [BoxShadow(offset: Offset(3, 3), color: kBorderDark)]
              : null,
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: MonoLabel(
                      material.id,
                      size: 10,
                      weight: FontWeight.w600,
                    ),
                  ),
                  _StatusBadge(available: isAvailable),
                  if (widget.canEdit) ...[
                    const SizedBox(width: 6),
                    _EditIconButton(onTap: widget.onEdit),
                  ],
                ],
              ),
              const SizedBox(height: 6),
              Opacity(
                opacity: isAvailable ? 1.0 : 0.55,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      material.name.toUpperCase(),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        height: 1.35,
                        letterSpacing: -0.2,
                        color: kInk,
                        decoration:
                            isAvailable ? null : TextDecoration.lineThrough,
                        decorationColor: kInk,
                      ),
                    ),
                    const SizedBox(height: 8),
                    _QuantityLine(
                      total: material.total,
                      biIssued: material.biIssued,
                      available: material.available,
                      uom: 'UNITS',
                    ),
                    _IncomingLine(
                      incomingQuantity: material.incomingQuantity,
                      expectedAvailabilityDate:
                          material.expectedAvailabilityDate,
                      purchaseOrderStatus: material.purchaseOrderStatus,
                      emphasized: !isAvailable,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

typedef _FactorySubmit = Future<bool> Function({
  required String name,
  required String location,
  required List<FactoryMaterial> materials,
});

class _FactoryMaterialEntry {
  final TextEditingController name;
  final TextEditingController pl;
  final TextEditingController total;
  final TextEditingController biIssued;

  _FactoryMaterialEntry()
      : name = TextEditingController(),
        pl = TextEditingController(),
        total = TextEditingController(),
        biIssued = TextEditingController(text: '0');

  void dispose() {
    name.dispose();
    pl.dispose();
    total.dispose();
    biIssued.dispose();
  }
}

class _FactoryFormSheet extends StatefulWidget {
  final _FactorySubmit onSubmit;
  final String? Function() failureMessage;

  const _FactoryFormSheet({
    required this.onSubmit,
    required this.failureMessage,
  });

  @override
  State<_FactoryFormSheet> createState() => _FactoryFormSheetState();
}

class _FactoryFormSheetState extends State<_FactoryFormSheet> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _locationController = TextEditingController();
  final List<_FactoryMaterialEntry> _entries = [_FactoryMaterialEntry()];
  bool _saving = false;

  @override
  void dispose() {
    _nameController.dispose();
    _locationController.dispose();
    for (final entry in _entries) {
      entry.dispose();
    }
    super.dispose();
  }

  void _addEntry() {
    setState(() => _entries.add(_FactoryMaterialEntry()));
  }

  void _removeEntry(int index) {
    setState(() {
      _entries[index].dispose();
      _entries.removeAt(index);
    });
  }

  String? _validateRequired(String? value, String field) {
    final v = (value ?? '').trim();
    if (v.isEmpty) return '$field is required';
    return null;
  }

  String? _validateNumber(String? value, String field) {
    final v = (value ?? '').trim();
    if (v.isEmpty) return '$field is required';
    final parsed = int.tryParse(v);
    if (parsed == null) return 'Enter a valid number';
    if (parsed < 0) return 'Must be zero or more';
    if (parsed > 2147483647) return 'Must be 2147483647 or less';
    return null;
  }

  Future<void> _submit() async {
    if (_saving) return;
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final materials = _entries
        .map((e) => FactoryMaterial(
              id: e.pl.text.trim(),
              name: e.name.text.trim(),
              total: int.tryParse(e.total.text.trim()) ?? 0,
              biIssued: int.tryParse(e.biIssued.text.trim()) ?? 0,
            ))
        .toList();
    if (materials.any((material) => material.biIssued > material.total)) {
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('BI Issued cannot exceed total quantity.')),
      );
      return;
    }
    final ok = await widget.onSubmit(
      name: _nameController.text.trim(),
      location: _locationController.text.trim(),
      materials: materials,
    );
    if (!mounted) return;
    if (!ok) {
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            widget.failureMessage() ?? 'Could not create the factory.',
          ),
        ),
      );
      return;
    }
    final message = widget.failureMessage();
    if (message != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    }
    Navigator.of(context).pop();
  }

  Widget _buildEntry(_FactoryMaterialEntry entry, int index) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: kGray50,
        border: Border.all(color: kBorderDark, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: MonoLabel(
                  'Material ${index + 1}',
                  weight: FontWeight.w600,
                ),
              ),
              InkWell(
                onTap: _entries.length > 1 ? () => _removeEntry(index) : null,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: kSurface,
                    border: Border.all(color: kBorderDark),
                  ),
                  child: Icon(
                    Icons.remove,
                    size: 12,
                    color: _entries.length > 1 ? kRed : kGray400,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          BrutalTextField(
            label: 'Material Name',
            controller: entry.name,
            validator: (v) => _validateRequired(v, 'Material name'),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: BrutalTextField(
                  label: 'PL Number',
                  controller: entry.pl,
                  validator: (v) => _validateRequired(v, 'PL Number'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: BrutalTextField(
                  label: 'Total',
                  controller: entry.total,
                  keyboardType: TextInputType.number,
                  validator: (v) => _validateNumber(v, 'Total'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: BrutalTextField(
                  label: 'BI Issued',
                  controller: entry.biIssued,
                  keyboardType: TextInputType.number,
                  validator: (v) => _validateNumber(v, 'BI Issued'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'ADD FACTORY',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  letterSpacing: -0.5,
                  color: kInk,
                ),
              ),
              const SizedBox(height: 4),
              const MonoLabel('New factory under Sleeper', color: kGray400),
              const SizedBox(height: 20),
              BrutalTextField(
                label: 'Factory Name',
                controller: _nameController,
                validator: (v) => _validateRequired(v, 'Factory name'),
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: 12),
              BrutalTextField(
                label: 'Location',
                controller: _locationController,
                validator: (v) => _validateRequired(v, 'Location'),
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  const Expanded(
                    child: MonoLabel('Materials', weight: FontWeight.w600),
                  ),
                  BrutalButton(
                    label: 'ADD MATERIAL',
                    icon: Icons.add,
                    iconSize: 14,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    onPressed: _addEntry,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              for (var i = 0; i < _entries.length; i++) ...[
                _buildEntry(_entries[i], i),
                if (i != _entries.length - 1) const SizedBox(height: 12),
              ],
              const SizedBox(height: 24),
              LayoutBuilder(
                builder: (context, constraints) {
                  final cancel = BrutalButton(
                    label: 'CANCEL',
                    onPressed:
                        _saving ? null : () => Navigator.of(context).pop(),
                  );
                  final create = BrutalButton(
                    label: 'CREATE FACTORY',
                    filled: true,
                    allowLabelWrap: true,
                    onPressed: _saving ? null : _submit,
                  );
                  if (constraints.maxWidth < 340) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        cancel,
                        const SizedBox(height: 12),
                        create,
                      ],
                    );
                  }
                  return Row(
                    children: [
                      Expanded(child: cancel),
                      const SizedBox(width: 12),
                      Expanded(child: create),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _QuantityLine extends StatelessWidget {
  final int total;
  final int biIssued;
  final int available;
  final String uom;

  const _QuantityLine({
    required this.total,
    required this.biIssued,
    required this.available,
    required this.uom,
  });

  @override
  Widget build(BuildContext context) {
    final availableColor = available > 0 ? kGreen : kRed;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Expanded(
          child: RichText(
            overflow: TextOverflow.ellipsis,
            text: TextSpan(
              children: [
                TextSpan(
                  text: 'Total: ',
                  style: monoStyle(
                    size: 11,
                    weight: FontWeight.w600,
                    color: kGreen,
                    letterSpacing: 0,
                  ),
                ),
                TextSpan(
                  text: '$total',
                  style: monoStyle(
                    size: 18,
                    weight: FontWeight.w600,
                    color: kGreen,
                    letterSpacing: 0,
                  ),
                ),
                TextSpan(
                  text: '  (BI Issued: ',
                  style: monoStyle(
                    size: 11,
                    color: kGray400,
                    letterSpacing: 0,
                  ),
                ),
                TextSpan(
                  text: '$biIssued',
                  style: monoStyle(
                    size: 11,
                    weight: FontWeight.w600,
                    color: kGray400,
                    letterSpacing: 0,
                  ),
                ),
                TextSpan(
                  text: ', Available: ',
                  style: monoStyle(
                    size: 11,
                    color: kGray400,
                    letterSpacing: 0,
                  ),
                ),
                TextSpan(
                  text: '$available',
                  style: monoStyle(
                    size: 11,
                    weight: FontWeight.w700,
                    color: availableColor,
                    letterSpacing: 0,
                  ),
                ),
                TextSpan(
                  text: ')',
                  style: monoStyle(
                    size: 11,
                    color: kGray400,
                    letterSpacing: 0,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 8),
        MonoLabel(uom, size: 9, color: kGray400),
      ],
    );
  }
}

class _IncomingLine extends StatelessWidget {
  final int incomingQuantity;
  final DateTime? expectedAvailabilityDate;
  final PurchaseOrderStatus purchaseOrderStatus;
  final bool emphasized;

  const _IncomingLine({
    required this.incomingQuantity,
    required this.expectedAvailabilityDate,
    required this.purchaseOrderStatus,
    this.emphasized = false,
  });

  bool get _visible => incomingQuantity > 0 || purchaseOrderStatus.hasIncoming;

  @override
  Widget build(BuildContext context) {
    if (!_visible) return const SizedBox.shrink();
    final segments = <Widget>[
      if (incomingQuantity > 0)
        _segment('INCOMING: $incomingQuantity', strong: true),
      if (expectedAvailabilityDate != null)
        _segment('EXPECTED: ${_formatDate(expectedAvailabilityDate!)}'),
      if (purchaseOrderStatus.hasIncoming)
        _segment(purchaseOrderStatus.label.toUpperCase(), strong: true),
    ];
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: emphasized ? const Color(0xFFFDECEA) : kGray50,
        border: Border.all(
          color: emphasized ? kRed : kBorder,
          width: 1,
        ),
      ),
      child: Wrap(
        spacing: 12,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: segments,
      ),
    );
  }

  Widget _segment(String text, {bool strong = false}) {
    final color = strong ? (emphasized ? kRed : kInk) : kGray400;
    return Text(
      text.toUpperCase(),
      style: monoStyle(
        size: 9,
        weight: strong ? FontWeight.w700 : FontWeight.w600,
        color: color,
        letterSpacing: 0.4,
      ),
    );
  }
}

class _PurchaseOrderStatusPicker extends StatelessWidget {
  final PurchaseOrderStatus value;
  final ValueChanged<PurchaseOrderStatus> onChanged;

  const _PurchaseOrderStatusPicker({
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const MonoLabel('Purchase Order / Incoming Status',
            weight: FontWeight.w600),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final status in PurchaseOrderStatus.values)
              InkWell(
                onTap: () => onChanged(status),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: value == status ? kInk : kSurface,
                    border: Border.all(color: kBorderDark, width: 1),
                  ),
                  child: MonoLabel(
                    status.label,
                    size: 8,
                    weight: FontWeight.w600,
                    color: value == status ? kSurface : kInk,
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _DatePickerButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _DatePickerButton({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: kSurface,
          border: Border.all(color: kBorderDark, width: 1),
        ),
        child: Row(
          children: [
            const Icon(Icons.event, size: 16, color: kInk),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: monoStyle(size: 12, color: kInk),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FactoryMaterialFormSheet extends StatefulWidget {
  final String factoryName;
  final FactoryMaterial? material;
  final String? Function(String value) validatePl;
  final String? Function() failureMessage;
  final Future<bool> Function({
    required String id,
    required String name,
    required int total,
    required int biIssued,
    required int incomingQuantity,
    required DateTime? expectedAvailabilityDate,
    required PurchaseOrderStatus purchaseOrderStatus,
    String? reason,
  }) onSubmit;

  const _FactoryMaterialFormSheet({
    required this.factoryName,
    required this.material,
    required this.validatePl,
    required this.failureMessage,
    required this.onSubmit,
  });

  @override
  State<_FactoryMaterialFormSheet> createState() =>
      _FactoryMaterialFormSheetState();
}

class _FactoryMaterialFormSheetState extends State<_FactoryMaterialFormSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _plController;
  late final TextEditingController _nameController;
  late final TextEditingController _totalController;
  late final TextEditingController _biController;
  late final TextEditingController _incomingController;
  late final TextEditingController _reasonController;
  DateTime? _expectedDate;
  late PurchaseOrderStatus _poStatus;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final material = widget.material;
    _plController = TextEditingController(text: material?.id ?? '');
    _nameController = TextEditingController(text: material?.name ?? '');
    _totalController =
        TextEditingController(text: material?.total.toString() ?? '');
    _biController =
        TextEditingController(text: material?.biIssued.toString() ?? '0');
    _incomingController = TextEditingController(
        text: material?.incomingQuantity.toString() ?? '0');
    _reasonController = TextEditingController();
    _expectedDate = material?.expectedAvailabilityDate;
    _poStatus = material?.purchaseOrderStatus ?? PurchaseOrderStatus.none;
  }

  @override
  void dispose() {
    _plController.dispose();
    _nameController.dispose();
    _totalController.dispose();
    _biController.dispose();
    _incomingController.dispose();
    _reasonController.dispose();
    super.dispose();
  }

  String? _validatePl(String? value) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return 'PL Number is required';
    return widget.validatePl(v);
  }

  String? _validateQuantity(String? value, String field) {
    final v = (value ?? '').trim();
    if (v.isEmpty) return '$field is required';
    final parsed = int.tryParse(v);
    if (parsed == null) return 'Enter a valid number';
    if (parsed < 0) return 'Must be zero or more';
    return null;
  }

  Future<void> _pickExpectedDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _expectedDate ?? now,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 5),
    );
    if (picked != null && mounted) {
      setState(() => _expectedDate = picked);
    }
  }

  Future<void> _submit() async {
    if (_saving) return;
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final total = int.parse(_totalController.text.trim());
    final biIssued = int.parse(_biController.text.trim());
    if (biIssued > total) {
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('BI Issued cannot exceed total quantity.')));
      return;
    }
    final incoming = int.parse(_incomingController.text.trim());
    final planningError =
        _purchaseOrderError(incoming, _expectedDate, _poStatus);
    if (planningError != null) {
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(planningError)),
      );
      return;
    }
    final ok = await widget.onSubmit(
      id: _plController.text.trim(),
      name: _nameController.text.trim(),
      total: total,
      biIssued: biIssued,
      incomingQuantity: incoming,
      expectedAvailabilityDate: _expectedDate,
      purchaseOrderStatus: _poStatus,
      reason: _reasonController.text.trim().isEmpty
          ? null
          : _reasonController.text.trim(),
    );
    if (!mounted) return;
    if (!ok) {
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            widget.failureMessage() ??
                'Could not save material: ${_plController.text.trim()}',
          ),
        ),
      );
      return;
    }
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                widget.material == null
                    ? 'ADD NEW MATERIALS - SLEEPER'
                    : 'EDIT FACTORY MATERIAL',
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  letterSpacing: -0.5,
                  color: kInk,
                ),
              ),
              const SizedBox(height: 4),
              MonoLabel(
                '${widget.factoryName}${widget.material != null ? ' · ${widget.material!.id}' : ''}',
                color: kGray400,
              ),
              const SizedBox(height: 20),
              BrutalTextField(
                label: 'PL Number',
                controller: _plController,
                validator: _validatePl,
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: 12),
              BrutalTextField(
                label: 'Material Name / Description',
                controller: _nameController,
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Name is required' : null,
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: BrutalTextField(
                      label: 'Total Quantity',
                      controller: _totalController,
                      keyboardType: TextInputType.number,
                      validator: (v) => _validateQuantity(v, 'Total'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: BrutalTextField(
                      label: 'BI Issued Quantity',
                      controller: _biController,
                      keyboardType: TextInputType.number,
                      validator: (v) => _validateQuantity(v, 'BI Issued'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              BrutalTextField(
                label: 'Incoming / Purchase Order Quantity',
                controller: _incomingController,
                keyboardType: TextInputType.number,
                validator: (v) => _validateQuantity(v, 'Incoming'),
              ),
              const SizedBox(height: 16),
              const MonoLabel('Expected Availability Date',
                  weight: FontWeight.w600),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: _DatePickerButton(
                      label: _expectedDate == null
                          ? 'SET EXPECTED DATE'
                          : _formatDate(_expectedDate!),
                      onTap: _pickExpectedDate,
                    ),
                  ),
                  if (_expectedDate != null) ...[
                    const SizedBox(width: 8),
                    InkWell(
                      onTap: () => setState(() => _expectedDate = null),
                      child: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: kSurface,
                          border: Border.all(color: kBorderDark),
                        ),
                        child: const Icon(Icons.close, size: 14, color: kInk),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 16),
              _PurchaseOrderStatusPicker(
                value: _poStatus,
                onChanged: (status) => setState(() {
                  _poStatus = status;
                  if (status == PurchaseOrderStatus.none) {
                    _incomingController.text = '0';
                    _expectedDate = null;
                  }
                }),
              ),
              if (widget.material != null) ...[
                const SizedBox(height: 16),
                BrutalTextField(
                    label: 'Reason (Optional)', controller: _reasonController),
              ],
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: BrutalButton(
                      label: 'CANCEL',
                      onPressed:
                          _saving ? null : () => Navigator.of(context).pop(),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: BrutalButton(
                      label: 'SAVE',
                      filled: true,
                      onPressed: _saving ? null : _submit,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
