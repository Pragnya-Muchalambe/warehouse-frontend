# Testing & Test Architecture

## `AppDependencies` — Production vs Testing

```dart
// Production — real services
factory AppDependencies.production() => AppDependencies(
  auth: AuthService(),
  inventory: InventoryService(),
  requests: RequestService(),
  accountRequests: AccountRequestService(),
  users: UserAccountService(),
  transactionFilePicker: kIsWeb
      ? PlatformTransactionFilePicker.initialized()
      : const PlatformTransactionFilePicker(),
);

// Testing — explicit doubles
@visibleForTesting
factory AppDependencies.forTesting({
  required AuthService auth,
  required InventoryService inventory,
  required RequestService requests,
  required AccountRequestService accountRequests,
  required UserAccountService users,
  required TransactionFilePicker transactionFilePicker,
}) => AppDependencies(...);
```

**Production services are created once at startup** via `AppDependencies.loadFromEnvironment()` (currently aliases `production()`). The deterministic local warehouse implementation lives in `test/support/` and is **never selected by production code**.

## `InventoryController` as Test Seam

The controller accepts optional `InventoryService` and `RequestService` in its constructor. Tests inject fakes to:
- Control loading sequences
- Simulate API errors (including `412 VERSION_CONFLICT`)
- Verify stock refresh behavior after decisions
- Test validation logic without network

## Test Coverage Areas

The test suite covers:
- API contract compatibility
- Cookie-only refresh behavior (concurrent refresh, rotation)
- Role restrictions (Viewer/Admin/Superadmin UI boundaries)
- Depot/Sleeper separation
- Request history, decisions, and undo
- Factory archival and account deactivation
- Attachment previews and multi-Proof payloads
- Test-only local service behavior

**Web-only test:** PDF renderer initialization (platform view requires browser). Non-web tests cover attachment selection and file-type logic.

## Validation Commands

Run complete project checks from repository root:

```bash
dart format lib test
flutter pub get
flutter analyze
flutter test
flutter build web
git diff --check
```

## Source References

- `lib/app_dependencies.dart` — Dependency graph and test seam
- `test/` — Unit/widget tests and deterministic local service implementations
- `README.md` — Validation commands