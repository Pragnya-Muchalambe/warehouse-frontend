import 'package:flutter/material.dart';

import '../controllers/inventory_controller.dart';
import '../models/inventory_item.dart';
import '../models/account_request.dart';
import '../models/viewer_request.dart';
import '../presentation.dart';
import '../services/auth_service.dart';
import '../services/account_request_service.dart';
import '../services/request_service.dart';
import '../services/user_account_service.dart';
import '../services/transaction_file_picker.dart';
import '../theme.dart';
import '../widgets/brutal.dart';
import 'inventory_view.dart';
import 'logs_view.dart';
import 'superadmin_permission_view.dart';
import 'superadmin_requests_view.dart';
import 'transactions_view.dart';

enum _SuperadminPage {
  inventory,
  sleeperFactories,
  actions,
  audit,
  requests,
  permission,
  sleeperActions,
  sleeperAudit,
  sleeperRequests,
  sleeperPermission,
}

/// Superadmin application shell, branched in `main.dart` for
/// `role == 'superadmin'`. Hamburger drawer with profile (Role: Superadmin) +
/// DEPOT/SLEEPER/LOGOUT; the bottom footer shows the five sections
/// INVENTORY | ACTIONS | AUDIT | REQUESTS | PERMISSION, scoped by area.
class SuperadminShell extends StatefulWidget {
  final AuthSession session;
  final InventoryController inventoryController;
  final VoidCallback onLogout;
  final RequestService? requestService;
  final AccountRequestService? accountRequestService;
  final UserAccountService? userAccountService;
  final TransactionFilePicker transactionFilePicker;

  const SuperadminShell({
    super.key,
    required this.session,
    required this.inventoryController,
    required this.onLogout,
    this.requestService,
    this.accountRequestService,
    this.userAccountService,
    this.transactionFilePicker = const PlatformTransactionFilePicker(),
  });

  @override
  State<SuperadminShell> createState() => _SuperadminShellState();
}

class _SuperadminShellState extends State<SuperadminShell> {
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  _SuperadminPage _page = _SuperadminPage.inventory;
  String? _sleeperFactoryId;
  late final RequestService _requestService;
  late final AccountRequestService _accountRequestService;
  int _depotPendingCount = 0;
  int _sleeperPendingCount = 0;
  int _permissionPendingCount = 0;
  int _countEpoch = 0;

  bool get _hasPendingNotifications =>
      _depotPendingCount > 0 ||
      _sleeperPendingCount > 0 ||
      _permissionPendingCount > 0;

  /// Incremented on each drawer navigation to Depot so the inventory page
  /// remounts cleanly (resets section + any open factory) instead of staying
  /// stuck inside the Sleeper experience.
  int _inventoryEpoch = 0;

  @override
  void initState() {
    super.initState();
    _requestService = widget.requestService ?? RequestService();
    _accountRequestService =
        widget.accountRequestService ?? AccountRequestService();
    _refreshPendingCounts();
  }

  Future<void> _refreshPendingCounts() async {
    final epoch = ++_countEpoch;
    try {
      final results = await Future.wait([
        _requestService.loadRequests(),
        _accountRequestService.loadRequests(),
      ]);
      if (!mounted || epoch != _countEpoch) return;
      final requests = results[0] as List<ViewerRequest>;
      final permissions = results[1] as List<AccountRequest>;
      setState(() {
        _depotPendingCount = requests
            .where((request) => request.section == 'Depot' && request.isPending)
            .length;
        _sleeperPendingCount = requests
            .where(
                (request) => request.section == 'Sleeper' && request.isPending)
            .length;
        _permissionPendingCount =
            permissions.where((request) => request.isPending).length;
      });
    } catch (_) {
      // Keep the last authoritative counts when refresh fails.
    }
  }

  String get _pageLabel {
    switch (_page) {
      case _SuperadminPage.inventory:
        return 'DEPOT INVENTORY';
      case _SuperadminPage.sleeperFactories:
        return 'SLEEPER FACTORIES';
      case _SuperadminPage.actions:
        return 'ACTIONS';
      case _SuperadminPage.audit:
        return 'AUDIT LOGS';
      case _SuperadminPage.requests:
        return 'REQUESTS';
      case _SuperadminPage.permission:
        return 'PERMISSION';
      case _SuperadminPage.sleeperActions:
        return 'SLEEPER ACTIONS';
      case _SuperadminPage.sleeperAudit:
        return 'SLEEPER AUDIT';
      case _SuperadminPage.sleeperRequests:
        return 'SLEEPER REQUESTS';
      case _SuperadminPage.sleeperPermission:
        return 'SLEEPER PERMISSION';
    }
  }

  bool get _inSleeperArea => switch (_page) {
        _SuperadminPage.sleeperFactories ||
        _SuperadminPage.sleeperActions ||
        _SuperadminPage.sleeperAudit ||
        _SuperadminPage.sleeperRequests ||
        _SuperadminPage.sleeperPermission =>
          true,
        _ => false,
      };

  void _go(_SuperadminPage page) {
    _refreshPendingCounts();
    setState(() {
      _page = page;
      if (page == _SuperadminPage.inventory) {
        _inventoryEpoch++;
        // Reset the active section with the page so the footer for the Depot
        // page is computed from Depot state immediately (no stale Sleeper
        // section left over from a previous visit).
        widget.inventoryController.setSection(
          InventorySection.depot,
          notify: false,
        );
      } else if (page == _SuperadminPage.sleeperFactories) {
        _sleeperFactoryId = null;
        widget.inventoryController.setSection(
          InventorySection.sleeper,
          notify: false,
        );
      }
    });
    Navigator.of(context).pop();
  }

  Widget _buildBody(InventoryController controller) {
    switch (_page) {
      case _SuperadminPage.inventory:
        return InventoryView(
          key: ValueKey('superadmin-inventory-$_inventoryEpoch'),
          controller: controller,
          session: widget.session,
          initialSection: InventorySection.depot,
          showSectionTabs: false,
        );
      case _SuperadminPage.sleeperFactories:
        return InventoryView(
          key: const ValueKey('superadmin-sleeper'),
          controller: controller,
          session: widget.session,
          initialSection: InventorySection.sleeper,
          showSectionTabs: false,
          onOpenSleeperActions: (factoryId) =>
              setState(() => _sleeperFactoryId = factoryId),
        );
      case _SuperadminPage.actions:
        return TransactionsView(
          key: const ValueKey('superadmin-depot-actions'),
          controller: controller,
          addTransaction: controller.addTransaction,
          session: widget.session,
          fixedSection: InventorySection.depot,
          filePicker: widget.transactionFilePicker,
          requestService: _requestService,
        );
      case _SuperadminPage.audit:
        return LogsView(
          logs: controller.auditLogs,
          transactions: controller.logs,
          factories: controller.factories,
          session: widget.session,
          editTransaction: controller.editTransaction,
          fixedSection: InventorySection.depot,
          downloadFile: controller.downloadFile,
        );
      case _SuperadminPage.requests:
        return SuperadminRequestsView(
          controller: controller,
          session: widget.session,
          section: 'Depot',
          requestService: _requestService,
          onRequestsChanged: _refreshPendingCounts,
        );
      case _SuperadminPage.permission:
        return SuperadminPermissionView(
          session: widget.session,
          accountRequestService: _accountRequestService,
          userService: widget.userAccountService,
          onRequestsChanged: _refreshPendingCounts,
        );
      case _SuperadminPage.sleeperActions:
        return TransactionsView(
          key: const ValueKey('superadmin-sleeper-actions'),
          controller: controller,
          addTransaction: controller.addTransaction,
          session: widget.session,
          fixedSection: InventorySection.sleeper,
          initialFactoryId: _sleeperFactoryId,
          filePicker: widget.transactionFilePicker,
          requestService: _requestService,
        );
      case _SuperadminPage.sleeperAudit:
        return LogsView(
          logs: controller.auditLogs,
          transactions: controller.logs,
          factories: controller.factories,
          session: widget.session,
          editTransaction: controller.editTransaction,
          fixedSection: InventorySection.sleeper,
          downloadFile: controller.downloadFile,
        );
      case _SuperadminPage.sleeperRequests:
        return SuperadminRequestsView(
          controller: controller,
          session: widget.session,
          section: 'Sleeper',
          factoryId: _sleeperFactoryId,
          requestService: _requestService,
          onRequestsChanged: _refreshPendingCounts,
        );
      case _SuperadminPage.sleeperPermission:
        return SuperadminPermissionView(
          session: widget.session,
          accountRequestService: _accountRequestService,
          userService: widget.userAccountService,
          onRequestsChanged: _refreshPendingCounts,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.inventoryController,
      builder: (context, _) {
        final controller = widget.inventoryController;
        return Scaffold(
          key: _scaffoldKey,
          backgroundColor: kPaper,
          drawer: _buildDrawer(),
          body: SafeArea(
            bottom: false,
            child: Column(
              children: [
                _buildTopBar(),
                Expanded(child: _buildBody(controller)),
              ],
            ),
          ),
          bottomNavigationBar: _buildFooter(),
        );
      },
    );
  }

  Widget _buildTopBar() {
    return Container(
      color: kInk,
      child: Row(
        children: [
          InkWell(
            onTap: () {
              _refreshPendingCounts();
              _scaffoldKey.currentState?.openDrawer();
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: const BoxDecoration(
                border: Border(
                  right: BorderSide(color: kSurface, width: 1),
                ),
              ),
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  const Icon(Icons.menu, size: 22, color: kSurface),
                  if (_hasPendingNotifications)
                    Positioned(
                      right: -3,
                      top: -3,
                      child: IgnorePointer(
                        child: Semantics(
                          key: const ValueKey('hamburger-notification-dot'),
                          label: 'Pending notifications',
                          child: Container(
                            width: 8,
                            height: 8,
                            decoration: const BoxDecoration(
                              color: kRed,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'WAREHOUSE',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      letterSpacing: -0.5,
                      color: kSurface,
                    ),
                  ),
                  MonoLabel(_pageLabel, size: 8, color: kGray400),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDrawer() {
    final session = widget.session;
    return Drawer(
      backgroundColor: kSurface,
      width: 280,
      shape: const RoundedRectangleBorder(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: kBorderDark, width: 1)),
            ),
            child: Row(
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: kInk,
                    border: Border.all(color: kBorderDark, width: 1),
                  ),
                  child: const Icon(Icons.person, size: 30, color: kSurface),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        session.name.isNotEmpty
                            ? displayName(session.name)
                            : session.username.toUpperCase(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: kInk,
                        ),
                      ),
                      const SizedBox(height: 2),
                      MonoLabel(
                        'ID: ${session.id.isNotEmpty ? session.id : session.username.toUpperCase()}',
                        size: 9,
                      ),
                      const SizedBox(height: 2),
                      const MonoLabel(
                        'Role: Superadmin',
                        size: 9,
                        weight: FontWeight.w700,
                        color: kGreen,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: [
                _DrawerItem(
                  icon: Icons.inventory_2_outlined,
                  label: 'DEPOT',
                  badgeCount: _depotPendingCount + _permissionPendingCount,
                  badgeKey: const ValueKey('depot-drawer-badge'),
                  active: _page == _SuperadminPage.inventory,
                  onTap: () => _go(_SuperadminPage.inventory),
                ),
                _DrawerItem(
                  icon: Icons.factory_outlined,
                  label: 'SLEEPER',
                  badgeCount: _sleeperPendingCount,
                  badgeKey: const ValueKey('sleeper-drawer-badge'),
                  active: _inSleeperArea,
                  onTap: () => _go(_SuperadminPage.sleeperFactories),
                ),
              ],
            ),
          ),
          InkWell(
            onTap: widget.onLogout,
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: kBorderDark, width: 1)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.logout, size: 18, color: kRed),
                  SizedBox(width: 10),
                  MonoLabel(
                    'LOGOUT',
                    size: 11,
                    weight: FontWeight.w700,
                    color: kRed,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFooter() {
    final sleeper = _inSleeperArea;
    return Material(
      color: kSurface,
      child: Container(
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: kBorderDark, width: 2)),
        ),
        child: SafeArea(
          top: false,
          child: Row(
            children: [
              _NavItem(
                label: sleeper ? 'FACTORIES' : 'INVENTORY',
                icon: sleeper
                    ? Icons.factory_outlined
                    : Icons.inventory_2_outlined,
                activeIcon: sleeper ? Icons.factory : Icons.inventory_2,
                isActive: sleeper
                    ? _page == _SuperadminPage.sleeperFactories
                    : _page == _SuperadminPage.inventory,
                onTap: () => setState(() {
                  if (sleeper) _sleeperFactoryId = null;
                  _page = sleeper
                      ? _SuperadminPage.sleeperFactories
                      : _SuperadminPage.inventory;
                }),
              ),
              _NavItem(
                label: 'ACTIONS',
                icon: Icons.add_box_outlined,
                activeIcon: Icons.add_box,
                isActive: sleeper
                    ? _page == _SuperadminPage.sleeperActions
                    : _page == _SuperadminPage.actions,
                onTap: () => setState(() => _page = sleeper
                    ? _SuperadminPage.sleeperActions
                    : _SuperadminPage.actions),
              ),
              _NavItem(
                label: 'AUDIT',
                icon: Icons.receipt_long_outlined,
                activeIcon: Icons.receipt_long,
                isActive: sleeper
                    ? _page == _SuperadminPage.sleeperAudit
                    : _page == _SuperadminPage.audit,
                onTap: () => setState(() => _page = sleeper
                    ? _SuperadminPage.sleeperAudit
                    : _SuperadminPage.audit),
              ),
              _NavItem(
                label: 'REQUESTS',
                icon: Icons.outbox_outlined,
                activeIcon: Icons.outbox,
                badgeCount: sleeper ? _sleeperPendingCount : _depotPendingCount,
                isActive: sleeper
                    ? _page == _SuperadminPage.sleeperRequests
                    : _page == _SuperadminPage.requests,
                onTap: () => setState(() => _page = sleeper
                    ? _SuperadminPage.sleeperRequests
                    : _SuperadminPage.requests),
              ),
              _NavItem(
                label: 'PERMISSION',
                icon: Icons.admin_panel_settings_outlined,
                activeIcon: Icons.admin_panel_settings,
                badgeCount: _permissionPendingCount,
                isActive: sleeper
                    ? _page == _SuperadminPage.sleeperPermission
                    : _page == _SuperadminPage.permission,
                onTap: () => setState(() => _page = sleeper
                    ? _SuperadminPage.sleeperPermission
                    : _SuperadminPage.permission),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DrawerItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;
  final int badgeCount;
  final Key? badgeKey;

  const _DrawerItem({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
    this.badgeCount = 0,
    this.badgeKey,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        color: active ? kInk : kSurface,
        child: Row(
          children: [
            Icon(icon, size: 18, color: active ? kSurface : kInk),
            const SizedBox(width: 10),
            MonoLabel(
              label,
              size: 11,
              weight: FontWeight.w600,
              color: active ? kSurface : kInk,
            ),
            const Spacer(),
            if (badgeCount > 0) _Badge(key: badgeKey, count: badgeCount),
          ],
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final String label;
  final IconData icon;
  final IconData? activeIcon;
  final bool isActive;
  final int badgeCount;
  final VoidCallback onTap;

  const _NavItem({
    required this.label,
    required this.icon,
    this.activeIcon,
    required this.isActive,
    required this.onTap,
    this.badgeCount = 0,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        child: Container(
          height: 64,
          decoration: BoxDecoration(
            color: isActive ? kInk : kSurface,
            border: const Border(
              right: BorderSide(color: kBorderDark, width: 2),
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Icon(
                    isActive ? (activeIcon ?? icon) : icon,
                    size: 18,
                    color: isActive ? kSurface : kInk,
                  ),
                  if (badgeCount > 0)
                    Positioned(
                        right: -9, top: -8, child: _Badge(count: badgeCount)),
                ],
              ),
              const SizedBox(height: 4),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: MonoLabel(
                    label,
                    size: 9,
                    weight: FontWeight.w600,
                    color: isActive ? kSurface : kInk,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  final int count;
  const _Badge({super.key, required this.count});
  @override
  Widget build(BuildContext context) => Container(
        constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 3),
        decoration: BoxDecoration(
          color: kRed,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(count > 99 ? '99+' : '$count',
            style: monoStyle(size: 8, color: kSurface)),
      );
}
