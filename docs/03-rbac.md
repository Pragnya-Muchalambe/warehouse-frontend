# Role-Based Access Control

## Wire Roles

The API uses exactly three roles (lowercase in Dart, uppercase on wire):

| Dart Role | Wire Role | Description |
|-----------|-----------|-------------|
| `viewer` | `VIEWER` | Read-only access to own requests, Depot/Sleeper inventory |
| `admin` | `ADMIN` | Write access within assigned module/factory scope |
| `superadmin` | `SUPERADMIN` | Full write access + request undo, factory archive, user admin |

## Module & Factory Scoping

| Concept | Wire Value | Notes |
|---------|------------|-------|
| Module | `DEPOT` / `SLEEPER` | UI module; `SLEEPER` maps to `FACTORY` scope in transactions |
| Transaction Scope | `DEPOT` / `FACTORY` | Determines which ledger is affected |
| Factory | UUID | Required for `SLEEPER` module operations |

**Frontend enforcement** (in `InventoryController` and shells):
- Viewer sees only own requests (`RequestService.loadRequests()` filtered by backend)
- Admin sees requests/transactions only for authorized module/factory
- Superadmin sees all authorized scopes + `PERMISSION` section (account requests, user admin)

## Frontend vs Backend Authorization

> **Critical:** The backend is the source of truth. Frontend role checks (`_isAdmin`, `_role == 'superadmin'`) only control *which UI affordances are shown*. Every mutating API call re-validates permissions server-side and returns `403 FORBIDDEN` if unauthorized.

## Permission Summary (from API Contract)

| Endpoint | VIEWER | ADMIN | SUPERADMIN |
|----------|--------|-------|------------|
| Authentication | Public/current session | Public/current session | Public/current session |
| Account request creation/decisions | Public creation | Deny | Superadmin decisions |
| `GET /users` | Deny | Deny | Allow |
| User administration | Deny | Deny | Allow |
| `DELETE /users/{userId}` | Deny | Deny | Allow |
| Inventory/factory reads | Allow | Allow | Allow |
| Inventory/factory/material writes | Deny | Allow | Allow |
| Factory archive/delete | Deny | Deny | Allow |
| Request create/list | Create and own-only list | Scoped list | Scoped list |
| Request accept/reject | Deny | Allow in scope | Allow in scope |
| Request undo | Deny | Deny | Allow in scope |
| Transaction create/list/correct/reverse | Deny | Create/list in scope | Full in scope |
| File upload | Deny | Allow | Allow |
| File content | Own related Bill only | Authorized Bill/Proof | Authorized Bill/Proof |
| Audit list | Deny | Operational scope | All authorized |

## Source References

- `lib/main.dart:160-190` — Role-based shell routing
- `lib/controllers/inventory_controller.dart:682` — `_isAdmin` getter
- `lib/controllers/inventory_controller.dart:497-523` — Superadmin-only factory archival
- `lib/views/viewer_shell.dart` — Viewer read-only UI
- `lib/views/admin_shell.dart` — Admin scoped write UI
- `lib/views/superadmin_shell.dart` — Superadmin full control UI