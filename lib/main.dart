import 'package:flutter/material.dart';

import 'app_dependencies.dart';
import 'controllers/inventory_controller.dart';
import 'services/auth_service.dart';
import 'theme.dart';
import 'views/admin_shell.dart';
import 'views/login_view.dart';
import 'views/superadmin_shell.dart';
import 'views/viewer_shell.dart';
import 'widgets/brutal.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
      WarehouseApp(dependencies: await AppDependencies.loadFromEnvironment()));
}

class WarehouseApp extends StatefulWidget {
  final AppDependencies? dependencies;

  const WarehouseApp({super.key, this.dependencies});

  @override
  State<WarehouseApp> createState() => _WarehouseAppState();
}

class _WarehouseAppState extends State<WarehouseApp> {
  late final AppDependencies _dependencies;
  late final InventoryController _inventoryController;
  late final AuthService _authService;
  AuthSession? _session;
  bool _booting = true;

  @override
  void initState() {
    super.initState();
    _dependencies = widget.dependencies ??
        (throw StateError('WarehouseApp requires initialized dependencies.'));
    _inventoryController = _dependencies.controller;
    _authService = _dependencies.auth;
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    final session = await _authService.getSession();
    if (session != null) {
      try {
        await _inventoryController.init(role: session.role);
      } catch (_) {
        // Individual screens remain usable and will surface API errors.
      }
    }
    if (mounted) {
      setState(() {
        _session = session;
        _booting = false;
      });
    }
  }

  Future<void> _handleLogin(AuthSession session) async {
    try {
      await _inventoryController.init(role: session.role);
    } catch (_) {
      // The authenticated shell can still render with empty collections.
    }
    if (mounted) setState(() => _session = session);
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
      return LoginView(
        onLogin: _handleLogin,
        authService: _authService,
        accountRequestService: _dependencies.accountRequests,
      );
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
        requestService: _dependencies.requests,
      );
    }

    if (session.role == 'admin') {
      return AdminShell(
        session: session,
        inventoryController: _inventoryController,
        onLogout: _handleLogout,
        requestService: _dependencies.requests,
        transactionFilePicker: _dependencies.transactionFilePicker,
      );
    }

    if (session.role == 'superadmin') {
      return SuperadminShell(
        session: session,
        inventoryController: _inventoryController,
        onLogout: _handleLogout,
        requestService: _dependencies.requests,
        accountRequestService: _dependencies.accountRequests,
        userAccountService: _dependencies.users,
        transactionFilePicker: _dependencies.transactionFilePicker,
      );
    }

    return LoginView(
      onLogin: _handleLogin,
      authService: _authService,
      accountRequestService: _dependencies.accountRequests,
    );
  }
}
