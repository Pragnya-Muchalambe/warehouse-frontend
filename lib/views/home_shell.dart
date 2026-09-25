import 'package:flutter/material.dart';

import '../controllers/inventory_controller.dart';
import '../services/auth_service.dart';
import '../theme.dart';
import '../widgets/brutal.dart';
import 'inventory_view.dart';
import 'logs_view.dart';
import 'transactions_view.dart';

enum _Tab { inventory, transactions, logs }

class HomeShell extends StatefulWidget {
  final AuthSession session;
  final InventoryController inventoryController;
  final VoidCallback onLogout;

  const HomeShell({
    super.key,
    required this.session,
    required this.inventoryController,
    required this.onLogout,
  });

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  _Tab _activeTab = _Tab.inventory;

  bool get _canOperate =>
      widget.session.role == 'superadmin' || widget.session.role == 'admin';

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.inventoryController,
      builder: (context, _) {
        final controller = widget.inventoryController;
        return Scaffold(
          body: SafeArea(
            bottom: false,
            child: _buildBody(controller),
          ),
          bottomNavigationBar: _buildNavBar(),
        );
      },
    );
  }

  Widget _buildBody(InventoryController controller) {
    switch (_activeTab) {
      case _Tab.inventory:
        return InventoryView(controller: controller, session: widget.session);
      case _Tab.transactions:
        return TransactionsView(
          controller: controller,
          addTransaction: controller.addTransaction,
          session: widget.session,
        );
      case _Tab.logs:
        return LogsView(
          logs: controller.auditLogs,
          transactions: controller.logs,
          factories: controller.factories,
          session: widget.session,
          editTransaction: controller.editTransaction,
          downloadFile: controller.downloadFile,
        );
    }
  }

  Widget _buildNavBar() {
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
                label: 'Inventory',
                icon: Icons.inventory_2_outlined,
                activeIcon: Icons.inventory_2,
                isActive: _activeTab == _Tab.inventory,
                onTap: () => setState(() => _activeTab = _Tab.inventory),
              ),
              _NavItem(
                label: 'Actions',
                icon: Icons.add_box_outlined,
                activeIcon: Icons.add_box,
                isActive: _activeTab == _Tab.transactions,
                onTap: () => setState(() => _activeTab = _Tab.transactions),
              ),
              _NavItem(
                label: 'Audit',
                icon: Icons.receipt_long_outlined,
                activeIcon: Icons.receipt_long,
                isActive: _activeTab == _Tab.logs,
                onTap: () => setState(() => _activeTab = _Tab.logs),
              ),
              _NavItem(
                label: 'Logout',
                icon: Icons.logout,
                isActive: false,
                onTap: widget.onLogout,
                showBorder: _canOperate,
              ),
            ],
          ),
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
  final bool showBorder;

  const _NavItem({
    required this.label,
    required this.icon,
    this.activeIcon,
    required this.isActive,
    required this.onTap,
    this.showBorder = true,
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
            border: showBorder
                ? const Border(
                    right: BorderSide(color: kBorderDark, width: 2),
                  )
                : null,
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
