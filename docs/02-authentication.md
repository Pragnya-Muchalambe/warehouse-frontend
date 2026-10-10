# Authentication & Session Management

## Cookie-Only Refresh Contract

The backend implements a **secure cookie-based refresh token flow**:

| Property | Implementation |
|----------|----------------|
| Access token | Stored in memory only (`ApiClient.accessToken`) |
| Refresh token | **Never** exposed to Dart — transported exclusively via `HttpOnly`, `Secure`, `SameSite` cookies |
| Login/Refresh response | Returns `accessToken`, `accessTokenExpiresAt`, `tokenType: "Bearer"`, and `user` object |
| Logout | `POST /auth/logout` with cookie; client clears local state regardless of server response |

This design prevents token leakage through logs, local storage, or application code.

## Platform-Specific Cookie Transport

| Platform | Cookie Handling |
|----------|-----------------|
| **Web** | Browser automatically sends cookies with `credentials: 'include'` (`credentialed_http_client_web.dart`) |
| **Android** | Uses platform `CookieManager` for persistent cookie store (`credentialed_http_client_io.dart` + Android native integration) |
| **iOS / Desktop** | **Unsupported in release builds** — no equivalent native `HttpOnly` cookie transport; refresh tokens never exposed to Dart |

The `ApiClient` abstracts this via a platform-specific `CredentialedHttpClient` interface. The production factory (`AppDependencies.production()`) selects the correct implementation at runtime.

## Concurrent Refresh Deduplication

Multiple simultaneous `401` responses must not trigger parallel refresh attempts. `AuthService._refreshAccessToken()` uses a **single in-flight future** pattern:

```dart
Future<bool>? _refreshInProgress;

Future<bool> _refreshAccessToken() {
  return _refreshInProgress ??= _performRefresh().whenComplete(
    () => _refreshInProgress = null,
  );
}
```

All callers await the same refresh operation. This is critical for Flutter's async widget tree where multiple services may detect expiry simultaneously.

## Session Bootstrap

`WarehouseApp._bootstrap()` (in `main.dart`):

1. Checks `ApiClient.configurationError` (missing `WAREHOUSE_API_BASE_URL`)
2. Calls `AuthService.getSession()` → attempts refresh → calls `/auth/me`
3. On success, initializes `InventoryController` with the user's role
4. Renders the appropriate shell (`ViewerShell`, `AdminShell`, `SuperadminShell`)

If bootstrap fails, the app still renders — individual screens surface API errors inline.

## Source References

- `lib/main.dart` — App bootstrap and role-based shell routing
- `lib/services/auth_service.dart` — Session lifecycle and refresh deduplication
- `lib/services/api_client.dart` — HTTP client, token storage, refresh orchestration
- `lib/services/credentialed_http_client_web.dart` — Web cookie handling
- `lib/services/credentialed_http_client_io.dart` — Android/iOS cookie handling