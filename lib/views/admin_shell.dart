import 'package:flutter/material.dart';

import '../controllers/inventory_controller.dart';
import '../models/inventory_item.dart';
import '../services/auth_service.dart';
import '../theme.dart';
import '../widgets/brutal.dart';
import 'admin_requests_view.dart';
import 'inventory_view.dart';
import 'logs_view.dart';
import 'transactions_view.dart';

enum _AdminPage { inventory, sleeper, actions, audit, requests }

/// Admin application shell, branched in `main.dart` for `role == 'admin'`.
/// Hamburger drawer with profile (Role: Admin) + DEPOT/SLEEPER/LOGOUT; the
/// bottom footer shows INVENTORY | ACTIONS | AUDIT | REQUESTS and is hidden
/// while inside the Sleeper inventory experience.
class AdminShell extends StatefulWidget {
  final AuthSession session;
  final InventoryController inventoryController;
  final VoidCallback onLogout;

  const AdminShell({
    super.key,
    required this.session,
    required this.inventoryController,
    required this.onLogout,
  });

  @override
  State<AdminShell> createState() => _AdminShellState();
}

class _AdminShellState extends State<AdminShell> {
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  _AdminPage _page = _AdminPage.inventory;

  /// Incremented on each drawer navigation to Depot so the inventory page
  /// remounts cleanly (resets section + any open factory) instead of staying
  /// stuck inside the Sleeper experience.
  int _inventoryEpoch = 0;

  String get _pageLabel {
    switch (_page) {
      case _AdminPage.inventory:
        return 'DEPOT INVENTORY';
      case _AdminPage.sleeper:
        return 'SLEEPER';
      case _AdminPage.actions:
        return 'ACTIONS';
      case _AdminPage.audit:
        return 'AUDIT LOGS';
      case _AdminPage.requests:
        return 'REQUESTS';
    }
  }

  /// No bottom footer while browsing the Sleeper inventory experience. The
  /// Sleeper experience is its own page here (SLEEPER drawer entry), so the
  /// footer is derived purely from the current navigation state and can never
  /// be left stale by switching sections.
  bool get _inSleeperExperience => _page == _AdminPage.sleeper;

  void _go(_AdminPage page) {
    setState(() {
      _page = page;
      if (page == _AdminPage.inventory) {
        _inventoryEpoch++;
        // Reset the active section with the page so the footer for the Depot
        // page is computed from Depot state immediately (no stale Sleeper
        // section left over from a previous visit).
        widget.inventoryController.setSection(
          InventorySection.depot,
          notify: false,
        );
      } else if (page == _AdminPage.sleeper) {
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
      case _AdminPage.inventory:
        return InventoryView(
          key: ValueKey('admin-inventory-$_inventoryEpoch'),
          controller: controller,
          session: widget.session,
          initialSection: InventorySection.depot,
          showSectionTabs: false,
        );
      case _AdminPage.sleeper:
        return InventoryView(
          key: const ValueKey('admin-sleeper'),
          controller: controller,
          session: widget.session,
          initialSection: InventorySection.sleeper,
          showSectionTabs: false,
        );
      case _AdminPage.actions:
        return TransactionsView(
          controller: controller,
          addTransaction: controller.addTransaction,
          session: widget.session,
        );
      case _AdminPage.audit:
        return LogsView(
          logs: controller.logs,
          factories: controller.factories,
          session: widget.session,
          editTransaction: controller.editTransaction,
        );
      case _AdminPage.requests:
        return AdminRequestsView(controller: controller, session: widget.session);
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
          bottomNavigationBar: _inSleeperExperience ? null : _buildFooter(),
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
            onTap: () => _scaffoldKey.currentState?.openDrawer(),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: const BoxDecoration(
                border: Border(
                  right: BorderSide(color: kSurface, width: 1),
                ),
              ),
              child: const Icon(Icons.menu, size: 22, color: kSurface),
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
                            ? session.name
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
                        'Role: Admin',
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
                  active: _page == _AdminPage.inventory,
                  onTap: () => _go(_AdminPage.inventory),
                ),
                _DrawerItem(
                  icon: Icons.factory_outlined,
                  label: 'SLEEPER',
                  active: _page == _AdminPage.sleeper,
                  onTap: () => _go(_AdminPage.sleeper),
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
                label: 'INVENTORY',
                icon: Icons.inventory_2_outlined,
                activeIcon: Icons.inventory_2,
                isActive: _page == _AdminPage.inventory,
                onTap: () => setState(() => _page = _AdminPage.inventory),
              ),
              _NavItem(
                label: 'ACTIONS',
                icon: Icons.add_box_outlined,
                activeIcon: Icons.add_box,
                isActive: _page == _AdminPage.actions,
                onTap: () => setState(() => _page = _AdminPage.actions),
              ),
              _NavItem(
                label: 'AUDIT',
                icon: Icons.receipt_long_outlined,
                activeIcon: Icons.receipt_long,
                isActive: _page == _AdminPage.audit,
                onTap: () => setState(() => _page = _AdminPage.audit),
              ),
              _NavItem(
                label: 'REQUESTS',
                icon: Icons.outbox_outlined,
                activeIcon: Icons.outbox,
                isActive: _page == _AdminPage.requests,
                onTap: () => setState(() => _page = _AdminPage.requests),
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

  const _DrawerItem({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
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
  final VoidCallback onTap;

  const _NavItem({
    required this.label,
    required this.icon,
    this.activeIcon,
    required this.isActive,
    required this.onTap,
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
              Icon(
                isActive ? (activeIcon ?? icon) : icon,
                size: 20,
                color: isActive ? kSurface : kInk,
              ),
              const SizedBox(height: 4),
              MonoLabel(
                label,
                size: 9,
                weight: FontWeight.w600,
                color: isActive ? kSurface : kInk,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
