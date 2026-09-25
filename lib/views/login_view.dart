import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../services/account_request_service.dart';
import '../theme.dart';
import '../widgets/brutal.dart';
import 'new_user_request_view.dart';

class LoginView extends StatefulWidget {
  final Future<void> Function(AuthSession) onLogin;
  final AuthService? authService;
  final AccountRequestService? accountRequestService;

  const LoginView({
    super.key,
    required this.onLogin,
    this.authService,
    this.accountRequestService,
  });

  @override
  State<LoginView> createState() => _LoginViewState();
}

class _LoginViewState extends State<LoginView> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  late final AuthService _authService;
  String? _error;
  bool _submitting = false;
  bool _obscurePassword = true;

  @override
  void initState() {
    super.initState();
    _authService = widget.authService ?? AuthService();
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _error = null;
      _submitting = true;
    });

    final session = await _authService.login(
      _usernameController.text,
      _passwordController.text,
    );

    if (!mounted) return;
    if (session == null) {
      setState(() {
        _error = _authService.lastErrorMessage ?? 'Unable to sign in.';
        _submitting = false;
      });
    } else {
      await widget.onLogin(session);
    }
  }

  void _openNewUser() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => NewUserRequestView(
          service: widget.accountRequestService,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 384),
            child: BrutalCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'SYSTEM LOGIN',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      letterSpacing: -0.5,
                      color: kInk,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const MonoLabel('Authentication Required'),
                  const SizedBox(height: 24),
                  if (_error != null) ...[
                    Container(
                      width: double.infinity,
                      color: kInk,
                      padding: const EdgeInsets.all(12),
                      child: MonoLabel(
                        _error!,
                        color: kSurface,
                        weight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                  Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        BrutalTextField(
                          controller: _usernameController,
                          label: 'User ID',
                          hint: 'admin',
                          keyboardType: TextInputType.text,
                          textInputAction: TextInputAction.next,
                          validator: (v) => (v == null || v.isEmpty)
                              ? 'User ID required'
                              : null,
                        ),
                        const SizedBox(height: 16),
                        BrutalTextField(
                          controller: _passwordController,
                          label: 'Password',
                          hint: 'password',
                          obscureText: _obscurePassword,
                          suffixIcon: IconButton(
                            tooltip: _obscurePassword
                                ? 'Show password'
                                : 'Hide password',
                            icon: Icon(_obscurePassword
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined),
                            onPressed: () => setState(
                                () => _obscurePassword = !_obscurePassword),
                          ),
                          textInputAction: TextInputAction.done,
                          validator: (v) => (v == null || v.isEmpty)
                              ? 'Password required'
                              : null,
                          onChanged: (_) {
                            if (_submitting) {
                              setState(() => _submitting = false);
                            }
                          },
                          onSubmitted: (_) {
                            if (!_submitting) _submit();
                          },
                        ),
                        const SizedBox(height: 24),
                        BrutalButton(
                          label: _submitting ? 'Signing In...' : 'Login',
                          labelStyle: monoStyle(
                            size: 12,
                            weight: FontWeight.w700,
                            color: kInk,
                            letterSpacing: 0.8,
                          ),
                          onPressed: _submitting ? null : _submit,
                        ),
                        const SizedBox(height: 12),
                        InkWell(
                          onTap: _openNewUser,
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            decoration: BoxDecoration(
                              border: Border.all(color: kBorderDark, width: 1),
                            ),
                            child: const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.person_add_alt_outlined,
                                    size: 16, color: kInk),
                                SizedBox(width: 8),
                                MonoLabel(
                                  'NEW USER',
                                  size: 11,
                                  weight: FontWeight.w700,
                                  color: kInk,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  const Divider(color: kBorder),
                  const SizedBox(height: 12),
                  const MonoLabel(
                    'Use your approved warehouse account',
                    size: 9,
                    color: kGray400,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
