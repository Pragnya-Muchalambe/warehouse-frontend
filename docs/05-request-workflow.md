# Request Workflow

## Viewer Request Creation

- **Endpoint:** `POST /requests` (one per material line)
- **Role:** `VIEWER` only
- **Idempotency:** Each line gets a distinct `Idempotency-Key`
- **Non-atomic:** Successful lines remain if another fails; frontend reports per-item results
- **Initial status:** `PENDING` — no stock reservation

```json
// Depot
{"module": "DEPOT", "factoryId": null, "itemId": "T-6902", "quantity": 10}

// Sleeper
{"module": "SLEEPER", "factoryId": "uuid", "itemId": "T-5836", "quantity": 10}
```

## Admin Decision (Accept/Reject)

- **Endpoint:** `POST /requests/{id}/accept` or `/reject`
- **Role:** `ADMIN` / `SUPERADMIN` within authorized scope
- **Headers:** `Idempotency-Key` + `If-Match: "<version>"`
- **Atomic backend transaction:** Verifies `PENDING`, locks ledger, validates stock, updates request + stock + history/audit
- **Stock change on Accept only:** `BI Issued += requested quantity`

## Superadmin Undo

- **Endpoint:** `POST /requests/{id}/undo`
- **Role:** `SUPERADMIN` only
- **Precondition:** Request must be `ACCEPTED` or `REJECTED` (not `PENDING`)
- **Atomic reversal:** Locks request + ledger, restores stock if was `ACCEPTED`, clears decision, returns to `PENDING`
- **History preserved:** Undo appends audit entries; original decision remains in history

## Pending Counts Badge

`GET /requests/pending-counts` returns scoped counts for the current user's visibility:
- Viewer: own pending requests only
- Admin/Superadmin: authorized module/factory
- Used for badge in `ViewerShell` and `AdminShell`

## Request Decision Enum (Frontend)

```dart
enum RequestDecision {
  accepted,
  rejected,
  insufficientStock,
  alreadyProcessed,
  undone,
  notAuthorized,
  failed,
}
```

Returned by `InventoryController.acceptRequest()`, `rejectRequest()`, `undoRequest()`.

## Source References

- `lib/controllers/inventory_controller.dart:582-654` — Accept, reject, undo implementations
- `lib/controllers/inventory_controller.dart:656-665` — `_findRequest()` helper
- `lib/controllers/inventory_controller.dart:667-680` — `_refreshInventoryAfterRequestDecision()`
- `lib/services/request_service.dart` — API calls for decisions
- `lib/views/viewer_requests_view.dart` — Viewer request creation UI
- `lib/views/admin_requests_view.dart` — Admin decision UI
- `lib/widgets/accept_request_dialog.dart` — Accept dialog (if exists)
- `lib/widgets/reject_request_dialog.dart` — Reject dialog
- `lib/widgets/undo_request_dialog.dart` — Undo dialog
- `api.md` section 4 — Material Requests contract