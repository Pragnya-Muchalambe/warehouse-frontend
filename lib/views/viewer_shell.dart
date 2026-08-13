import 'package:flutter/material.dart';

import '../controllers/inventory_controller.dart';
import '../models/inventory_item.dart';
import '../services/auth_service.dart';
import '../theme.dart';
import '../widgets/brutal.dart';
import 'inventory_view.dart';
import 'viewer_history_view.dart';
import 'viewer_requests_view.dart';

enum _ViewerPage { depot, sleeper, requests, history }

/// Viewer-only application shell. Branched in `main.dart` when the logged-in
/// role is `viewer`. Admin/Superadmin keep using [HomeShell] untouched.
class ViewerShell extends StatefulWidget {
  final AuthSession session;
  final InventoryController inventoryController;
  final VoidCallback onLogout;

  const ViewerShell({
    super.key,
    required this.session,
    required this.inventoryController,
    required this.onLogout,
  });

  @override
  State<ViewerShell> createState() => _ViewerShellState();
}

class _ViewerShellState extends State<ViewerShell> {
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  _ViewerPage _page = _ViewerPage.depot;

  String get _pageLabel {
    switch (_page) {
      case _ViewerPage.depot:
        return 'DEPOT INVENTORY';
      case _ViewerPage.sleeper:
        return 'SLEEPER';
      case _ViewerPage.requests:
        return 'REQUESTS';
      case _ViewerPage.history:
        return 'HISTORY';
    }
  }

  void _go(_ViewerPage page) {
    if (_page != page) {
      setState(() => _page = page);
    }
    // Close the slide-out navigation drawer.
    Navigator.of(context).pop();
  }

  Widget _buildBody(InventoryController controller) {
    switch (_page) {
      case _ViewerPage.depot:
        return InventoryView(
          key: const ValueKey('viewer-depot'),
          controller: controller,
          session: widget.session,
          initialSection: InventorySection.depot,
          showSectionTabs: false,
        );
      case _ViewerPage.sleeper:
        return InventoryView(
          key: const ValueKey('viewer-sleeper'),
          controller: controller,
          session: widget.session,
          initialSection: InventorySection.sleeper,
          showSectionTabs: false,
        );
      case _ViewerPage.requests:
        return ViewerRequestsView(
          controller: controller,
          session: widget.session,
        );
      case _ViewerPage.history:
        return ViewerHistoryView(session: widget.session);
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
          bottomNavigationBar:
              _page == _ViewerPage.sleeper ? null : _buildFooter(),
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
          // Profile area.
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
                        'Role: Viewer',
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
                  active: _page == _ViewerPage.depot,
                  onTap: () => _go(_ViewerPage.depot),
                ),
                _DrawerItem(
                  icon: Icons.factory_outlined,
                  label: 'SLEEPER',
                  active: _page == _ViewerPage.sleeper,
                  onTap: () => _go(_ViewerPage.sleeper),
                ),
              ],
            ),
          ),
          // Logout anchored at the bottom.
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
              _ViewerNavItem(
                label: 'INVENTORY',
                icon: Icons.inventory_2_outlined,
                activeIcon: Icons.inventory_2,
                isActive: _page == _ViewerPage.depot,
                onTap: () => setState(() => _page = _ViewerPage.depot),
              ),
              _ViewerNavItem(
                label: 'REQUESTS',
                icon: Icons.outbox_outlined,
                activeIcon: Icons.outbox,
                isActive: _page == _ViewerPage.requests,
                onTap: () => setState(() => _page = _ViewerPage.requests),
              ),
              _ViewerNavItem(
                label: 'HISTORY',
                icon: Icons.history,
                isActive: _page == _ViewerPage.history,
                onTap: () => setState(() => _page = _ViewerPage.history),
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

class _ViewerNavItem extends StatelessWidget {
  final String label;
  final IconData icon;
  final IconData? activeIcon;
  final bool isActive;
  final VoidCallback onTap;

  const _ViewerNavItem({
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
              right: BorderSide(color: kBorderDark, width: 1),
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
