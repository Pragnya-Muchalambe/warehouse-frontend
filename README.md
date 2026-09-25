# Railway Warehouse Management System

Flutter frontend for railway warehouse inventory across Depot and Sleeper/factory scopes. It connects to the HTTP API defined in [`api.md`](api.md); production startup does not use the test-only local warehouse services.

## Features

- Viewer, Admin, and Superadmin role-specific navigation and controls.
- Separate Depot and Sleeper/factory inventory workflows.
- Incoming and Dispatch transactions with a required Bill and up to 10 optional Proof files.
- Image and PDF attachment previews.
- Viewer request cart, history, and pending-request badge.
- Admin request decisions and Superadmin undo confirmation.
- Factory and account deletion controls.
- Transaction correction and scoped audit views.
- Login, registration, cookie-based session refresh, and in-memory access tokens.

Server-side authorization remains authoritative. The Flutter role restrictions are a presentation and workflow boundary, not a replacement for API authorization.

## API Configuration

The client appends `/api/v1` to the configured origin unless it is already present. Development defaults to `http://localhost:8000`. Configure every deployed build with an HTTPS API origin:

```bash
flutter run --dart-define=WAREHOUSE_API_BASE_URL=https://warehouse.example.com
flutter build web --dart-define=WAREHOUSE_API_BASE_URL=https://warehouse.example.com
```

Authentication follows the cookie-only refresh contract in `api.md`:

- Dart stores the access token in memory only.
- Refresh and logout do not read or send a refresh token in JSON.
- Browser requests enable credentials.
- Android requests use the native persistent cookie store.
- Concurrent expired-token requests share one in-flight refresh operation.

The API must allow credentialed CORS requests from the deployed web origin. Android networking requires the Internet permission already declared in the application manifest.

## Setup

Requirements:

- Flutter stable with Dart 3.5 or newer.
- Chrome for web development, or an Android SDK/device for Android development.
- A backend implementing [`api.md`](api.md).

```bash
git clone https://github.com/Pragnya-Muchalambe/warehouse-frontend.git
cd warehouse-frontend
flutter pub get
flutter doctor
flutter run --dart-define=WAREHOUSE_API_BASE_URL=http://localhost:8000
```

For an Android emulator, use the backend address reachable from that emulator rather than the host-only loopback address when necessary.

## Architecture

Production dependencies are created by `AppDependencies.production()` and use API-backed authentication, inventory, request, account-request, and user-account services. `AppDependencies.forTesting()` permits explicit injection of test doubles. The deterministic local warehouse implementation is under `test/support/` and is never selected by production startup.

Attachments are uploaded before transaction submission. Bills and Proofs remain separate throughout the workflow:

- `billFileId` is required.
- `proofFileIds` is ordered, plural, optional, and limited to 10 unique files.
- An omitted `proofFileIds` correction preserves existing Proofs.
- `proofFileIds: []` explicitly removes all Proofs.

## Validation

Run the complete project checks from the repository root:

```bash
dart format lib test
flutter pub get
flutter analyze
flutter test
flutter build web
git diff --check
```

The tests include API contract compatibility, cookie-only refresh behavior, concurrent refresh, role restrictions, Depot/Sleeper separation, request history and decisions, deletion controls, attachment previews, multiple-Proof payloads, and test-only local service behavior. The real PDF renderer initialization test is web-only because its platform view requires a browser test environment; non-web tests still cover attachment selection and file-type behavior.

## Repository Structure

```text
android/   Android host integration and persistent cookie transport
assets/    Bundled frontend assets
lib/       Production Flutter source
test/      Unit/widget tests and explicit test-only local services
api.md     Final frontend/backend API contract
```

Generated output, local SDK configuration, IDE files, logs, environment files, and the standalone development mock backend are not part of the frontend source commit.

## Deployment Notes

- Replace the placeholder Android application ID and configure release signing before distribution.
- Use HTTPS for every deployed API origin.
- Keep refresh cookies `HttpOnly`, `Secure`, and configured with the contract's `SameSite` policy.
- Do not place secrets in `--dart-define`; Flutter compile-time values are visible to clients.
- Run security, accessibility, performance, and end-to-end checks against the deployed backend before operational use.

## License

No open-source license has been added to this repository.
