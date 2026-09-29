import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:warehouse_poc/models/account_request.dart';
import 'package:warehouse_poc/services/account_request_service.dart';
import 'package:warehouse_poc/services/auth_service.dart';
import 'package:warehouse_poc/theme.dart';
import 'package:warehouse_poc/views/login_view.dart';
import 'package:warehouse_poc/views/new_user_request_view.dart';

void main() {
  testWidgets('login uses User ID and exposes an accessible password toggle',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(),
      home: LoginView(
        authService: _NoSessionAuthService(),
        onLogin: (_) async {},
      ),
    ));

    expect(find.text('User ID'), findsOneWidget);
    expect(find.text('Username'), findsNothing);
    expect(find.byTooltip('Show password'), findsOneWidget);
    expect(tester.widget<TextField>(find.byType(TextField).last).obscureText,
        isTrue);

    await tester.tap(find.byTooltip('Show password'));
    await tester.pump();

    expect(find.byTooltip('Hide password'), findsOneWidget);
    expect(tester.widget<TextField>(find.byType(TextField).last).obscureText,
        isFalse);
  });

  testWidgets('registration validates confirmation and sends only password',
      (tester) async {
    tester.view.physicalSize = const Size(800, 1200);
    addTearDown(tester.view.resetPhysicalSize);
    final service = _CapturingAccountRequestService();
    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(),
      home: NewUserRequestView(service: service),
    ));

    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), 'Ravi Kumar');
    await tester.enterText(fields.at(1), 'vw-2042');
    await tester.enterText(fields.at(2), 'securepass12');
    await tester.enterText(fields.at(3), 'differentpass');
    final rolePicker = find.byType(DropdownButton<String>);
    await tester.ensureVisible(rolePicker);
    await tester.tap(rolePicker);
    await tester.pumpAndSettle();
    final viewerRole = find
        .byWidgetPredicate(
          (widget) =>
              widget is DropdownMenuItem<String> && widget.value == 'viewer',
        )
        .last;
    await tester.ensureVisible(viewerRole);
    await tester.tap(viewerRole);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('SEND REQUEST'));
    await tester.tap(find.text('SEND REQUEST'));
    await tester.pump();

    expect(find.text('Passwords do not match'), findsOneWidget);
    expect(service.calls, 0);

    await tester.enterText(fields.at(3), 'securepass12');
    await tester.tap(find.text('SEND REQUEST'));
    await tester.pumpAndSettle();

    expect(service.calls, 1);
    expect(service.id, 'VW-2042');
    expect(service.password, 'securepass12');
    expect(service.role, 'viewer');
  });
}

class _NoSessionAuthService extends AuthService {
  @override
  Future<AuthSession?> login(String username, String password) async => null;
}

class _CapturingAccountRequestService extends AccountRequestService {
  int calls = 0;
  String? id;
  String? password;
  String? role;

  @override
  Future<AccountRequest> addRequest({
    required String name,
    required String id,
    required String password,
    required String role,
  }) async {
    calls++;
    this.id = id;
    this.password = password;
    this.role = role;
    return AccountRequest(
      id: 'request-id',
      name: name,
      requestedId: id,
      role: role,
      submittedAt: DateTime.utc(2026, 9, 29),
    );
  }
}
