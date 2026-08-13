import 'package:flutter/material.dart';

import '../services/account_request_service.dart';
import '../services/auth_service.dart';
import '../theme.dart';
import '../widgets/brutal.dart';

/// Registration flow for new accounts. Submits an account-creation request
/// that Superadmin reviews from the PERMISSION section. The login username is
/// the lowercased requested ID once the request is accepted.
class NewUserRequestView extends StatefulWidget {
  const NewUserRequestView({super.key});

  @override
  State<NewUserRequestView> createState() => _NewUserRequestViewState();
}

class _NewUserRequestViewState extends State<NewUserRequestView> {
  final _formKey = GlobalKey<FormState>();
  final AccountRequestService _service = AccountRequestService();
  final AuthService _authService = AuthService();
  final _nameController = TextEditingController();
  final _idController = TextEditingController();
  final _passwordController = TextEditingController();

  String? _role;
  String? _roleError;
  String? _idError;
  bool _submitting = false;

  static final _idPattern = RegExp(r'^[A-Za-z0-9-]+$');

  @override
  void dispose() {
    _nameController.dispose();
    _idController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_role == null) {
      setState(() => _roleError = 'Select a role.');
      return;
    }
    setState(() => _submitting = true);

    final taken = await _authService.isAccountIdTaken(_idController.text);
    if (!mounted) return;
    if (taken) {
      setState(() {
        _submitting = false;
        _idError = 'This ID already belongs to an active account.';
      });
      return;
    }

    await _service.addRequest(
      name: _nameController.text.trim(),
      id: _idController.text.trim().toUpperCase(),
      password: _passwordController.text,
      role: _role!,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Account request has been sent')),
    );
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kPaper,
      body: SafeArea(
        child: Column(
          children: [
            Container(
              color: kInk,
              child: Row(
                children: [
                  InkWell(
                    onTap: () => Navigator.of(context).pop(),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 12),
                      decoration: const BoxDecoration(
                        border: Border(
                          right: BorderSide(color: kSurface, width: 1),
                        ),
                      ),
                      child: const Icon(Icons.arrow_back,
                          size: 22, color: kSurface),
                    ),
                  ),
                  const Expanded(
                    child: Padding(
                      padding: EdgeInsets.symmetric(horizontal: 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
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
                          MonoLabel(
                            'NEW USER REQUEST',
                            size: 8,
                            color: kGray400,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 520),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text(
                          'NEW USER REQUEST',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            letterSpacing: -0.5,
                            color: kInk,
                          ),
                        ),
                        const SizedBox(height: 4),
                        const MonoLabel(
                          'Request an account. Superadmin approval is required.',
                          size: 9,
                        ),
                        const SizedBox(height: 20),
                        BrutalCard(
                          child: Form(
                            key: _formKey,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                BrutalTextField(
                                  controller: _nameController,
                                  label: 'Name',
                                  hint: 'Rahul Kumar',
                                  textInputAction: TextInputAction.next,
                                  validator: (v) => (v == null ||
                                          v.trim().isEmpty)
                                      ? 'Name required'
                                      : null,
                                ),
                                const SizedBox(height: 16),
                                BrutalTextField(
                                  controller: _idController,
                                  label: 'ID',
                                  hint: 'A1024',
                                  textInputAction: TextInputAction.next,
                                  onChanged: (_) {
                                    if (_idError != null) {
                                      setState(() => _idError = null);
                                    }
                                  },
                                  validator: (v) {
                                    final value = (v ?? '').trim();
                                    if (value.isEmpty) return 'ID required';
                                    if (value.length < 3) {
                                      return 'ID must be at least 3 characters';
                                    }
                                    if (!_idPattern.hasMatch(value)) {
                                      return 'Use letters, numbers or hyphens only';
                                    }
                                    return null;
                                  },
                                ),
                                if (_idError != null) ...[
                                  const SizedBox(height: 8),
                                  MonoLabel(
                                    _idError!,
                                    size: 9,
                                    weight: FontWeight.w600,
                                    color: kRed,
                                  ),
                                ],
                                const SizedBox(height: 16),
                                BrutalTextField(
                                  controller: _passwordController,
                                  label: 'Password',
                                  hint: 'Minimum 4 characters',
                                  obscureText: true,
                                  textInputAction: TextInputAction.next,
                                  validator: (v) {
                                    if (v == null || v.isEmpty) {
                                      return 'Password required';
                                    }
                                    if (v.length < 4) {
                                      return 'Password must be at least 4 characters';
                                    }
                                    return null;
                                  },
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  'Role',
                                  style: monoStyle(
                                      weight: FontWeight.w600),
                                ),
                                const SizedBox(height: 8),
                                Container(
                                  decoration: BoxDecoration(
                                    color: kSurface,
                                    border: Border.all(
                                        color: kBorderDark, width: 1),
                                  ),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 12),
                                    child: DropdownButtonHideUnderline(
                                      child: DropdownButton<String>(
                                        value: _role,
                                        isExpanded: true,
                                        hint: const MonoLabel(
                                          'Select role',
                                          size: 11,
                                          color: kGray400,
                                        ),
                                        items: const [
                                          DropdownMenuItem(
                                            value: 'admin',
                                            child: MonoLabel(
                                              'Admin',
                                              size: 11,
                                              color: kInk,
                                            ),
                                          ),
                                          DropdownMenuItem(
                                            value: 'viewer',
                                            child: MonoLabel(
                                              'Viewer',
                                              size: 11,
                                              color: kInk,
                                            ),
                                          ),
                                        ],
                                        onChanged: (value) => setState(() {
                                          _role = value;
                                          _roleError = null;
                                        }),
                                        dropdownColor: kSurface,
                                        style: monoStyle(
                                            size: 11, color: kInk),
                                        icon: const Icon(
                                          Icons.arrow_drop_down,
                                          color: kInk,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                if (_roleError != null) ...[
                                  const SizedBox(height: 8),
                                  MonoLabel(
                                    _roleError!,
                                    size: 9,
                                    weight: FontWeight.w600,
                                    color: kRed,
                                  ),
                                ],
                                const SizedBox(height: 20),
                                BrutalButton(
                                  label: _submitting
                                      ? 'Sending...'
                                      : 'SEND REQUEST',
                                  filled: true,
                                  onPressed: _submitting ? null : _submit,
                                ),
                                const SizedBox(height: 8),
                                const MonoLabel(
                                  'Your login username will be your ID (lowercase) once approved',
                                  size: 8,
                                  color: kGray400,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
