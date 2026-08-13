import 'package:flutter/material.dart';

import 'controllers/inventory_controller.dart';
import 'services/auth_service.dart';
import 'theme.dart';
import 'views/admin_shell.dart';
import 'views/login_view.dart';
import 'views/superadmin_shell.dart';
import 'views/viewer_shell.dart';
import 'widgets/brutal.dart';

void main() {
  runApp(const WarehouseApp());
}

class WarehouseApp extends StatefulWidget {
  const WarehouseApp({super.key});

  @override
  State<WarehouseApp> createState() => _WarehouseAppState();
}

class _WarehouseAppState extends State<WarehouseApp> {
  final InventoryController _inventoryController = InventoryController();
  final AuthService _authService = AuthService();
  AuthSession? _session;
  bool _booting = true;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    await _inventoryController.init();
    final session = await _authService.getSession();
    if (mounted) {
      setState(() {
        _session = session;
        _booting = false;
      });
    }
  }

  void _handleLogin(AuthSession session) {
    setState(() => _session = session);
  }

  Future<void> _handleLogout() async {
    await _authService.logout();
    if (mounted) {
      setState(() => _session = null);
    }
  }

  @override
  void dispose() {
    _inventoryController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Warehouse POC',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      home: _buildHome(),
    );
  }

  Widget _buildHome() {
    if (_booting || _inventoryController.loading) {
      return const Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 32,
                height: 32,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              SizedBox(height: 16),
              MonoLabel('Loading System'),
            ],
          ),
        ),
      );
    }

    final session = _session;
    if (session == null) {
      return LoginView(onLogin: _handleLogin);
    }

    // Viewer uses its own read-only shell; Admin gets the Admin workflow
    // shell (Requests, Depot-only adds). Superadmin gets the Admin workflow
    // plus Requests override (Undo) and the PERMISSION account-approval
    // section.
    if (session.role == 'viewer') {
      return ViewerShell(
        session: session,
        inventoryController: _inventoryController,
        onLogout: _handleLogout,
      );
    }

    if (session.role == 'admin') {
      return AdminShell(
        session: session,
        inventoryController: _inventoryController,
        onLogout: _handleLogout,
      );
    }

    return SuperadminShell(
      session: session,
      inventoryController: _inventoryController,
      onLogout: _handleLogout,
    );
  }
}
