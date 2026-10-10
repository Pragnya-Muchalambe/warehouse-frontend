# Platform-Specific Concerns

## Build Configuration

| Variable | Purpose | Required |
|----------|---------|----------|
| `WAREHOUSE_API_BASE_URL` | API origin (appends `/api/v1` if missing) | **Yes** — production must use HTTPS |

```bash
# Development
flutter run --dart-define=WAREHOUSE_API_BASE_URL=http://localhost:8000

# Production
flutter build web --dart-define=WAREHOUSE_API_BASE_URL=https://warehouse.example.com
```

**Secrets never in `--dart-define`** — compile-time values are visible to clients.

## Android Release Blockers

- Unique application ID not finalized
- Production signing credentials not configured
- Release builds are **intentionally unsigned** — do not publish

## CORS & Network

- API must allow credentialed CORS from deployed web origin
- Android `INTERNET` permission already declared in manifest
- iOS/Desktop release builds fail clearly with "unsupported" message

## Platform Support Matrix

| Platform | Auth Support | Notes |
|----------|--------------|-------|
| **Web** | ✅ Full | Browser handles `HttpOnly` cookies automatically |
| **Android** | ✅ Full | Native `CookieManager` persistent store |
| **iOS** | ❌ Release | No equivalent native `HttpOnly` cookie transport |
| **Desktop (macOS/Windows/Linux)** | ❌ Release | No equivalent native `HttpOnly` cookie transport |

## Cookie Transport Implementation

The `ApiClient` uses a platform-specific `CredentialedHttpClient`:

- `credentialed_http_client_web.dart` — Web implementation using `http` package with `withCredentials: true`
- `credentialed_http_client_io.dart` — Android/iOS implementation using platform channels for cookie persistence
- `credentialed_http_client_stub.dart` — Fallback/stub for unsupported platforms

Selected at runtime in `AppDependencies.production()`:

```dart
transactionFilePicker: kIsWeb
    ? PlatformTransactionFilePicker.initialized()
    : const PlatformTransactionFilePicker(),
```

## Source References

- `lib/main.dart:27-29` — `WAREHOUSE_API_BASE_URL` usage
- `lib/services/api_client.dart` — Platform client selection
- `lib/services/credentialed_http_client_web.dart` — Web cookie handling
- `lib/services/credentialed_http_client_io.dart` — Native cookie handling
- `android/` — Android host integration
- `README.md` — Deployment notes, API configuration