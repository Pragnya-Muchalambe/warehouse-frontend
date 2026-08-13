# Warehouse POC — Backend API Specification

Status: Draft for review.
Scope: Web/REST API + WebSocket that the Flutter frontend (`warehouse_poc`) needs in order to
replace its current SharedPreferences-based local persistence.
Author: derived from a deep read of the Flutter source (`lib/controllers`, `lib/services`,
`lib/models`, `lib/views`) — no Flutter source code was modified to produce this document.

---

## 1. Conventions

- **Base URL**: `http://<server-host>:<port>/api/v1` — the Flutter app currently hardcodes
  no base URL (see `TBD` items). Everything below is relative to this prefix.
- **Authentication**: `Authorization: Bearer <jwt>` header. The token is issued by
  `POST /auth/login` and must be sent on every protected endpoint.
- **Roles** (exactly three, hierarchical):
  - `viewer` — read-only inventory; creates and tracks their own material requests.
  - `admin` — plus: create/edit inventory (depot + sleeper), record incoming/dispatch
    transactions, view audit, accept/reject viewer requests.
  - `superadmin` — plus: undo/override request decisions, correct transactions, approve
    new-user account requests.
- **Error envelope**: every non-2xx response body is

  ```json
  { "detail": "Human readable reason" }
  ```

  Additional machine-readable error info may be added under `"error": { "code": "...", "field": "..." }`
  (see Section 12).
- **Success envelope**: list endpoints return `{ "data": [...], "count": <int> }`;
  single-object endpoints return `{ "data": { ... } }`. `POST`/`PATCH`/`DELETE` return the
  created/updated resource in `{ "data": { ... } }` with the appropriate 2xx status.
- **IDs**: the app currently generates string ids from `DateTime.now().microsecondsSinceEpoch`.
  Backend should use UUIDs; the client treats `id` as an opaque string, so this is a safe
  swap (see Section 15 TBD-1).
- **Dates/timestamps**: ISO-8601 UTC strings (`2026-08-14T09:30:00.000Z`). The app stores
  local `DateTime` objects and renders them via `toLocal()`.
- **Status codes**: `200` OK, `201` Created, `400` Bad Request, `401` Unauthorized,
  `403` Forbidden, `404` Not Found, `409` Conflict, `413` Payload Too Large,
  `422` Unprocessable Entity, `429` Too Many Requests, `500` Internal Server Error.

---

## 2. Authentication

### 2.1 `POST /auth/login`

Public. Authenticates a username/password and returns a JWT.

Request body:

```json
{
  "username": "admin",
  "password": "password"
}
```

- `username` is matched case-insensitively. Built-in accounts: `superadmin`, `admin`,
  `viewer` (demo password `password`). Custom accounts created via account-request
  approval log in with `username` = their ID lowercased (see Section 9 / 8).
- Roles on the wire are the exact strings `viewer` | `admin` | `superadmin`.

Response `200`:

```json
{
  "data": {
    "token": "<jwt>",
    "username": "admin",
    "role": "admin",
    "name": "Admin User",
    "id": "AD-1002"
  }
}
```

Errors:

| Status | Body `detail` |
| --- | --- |
| 401 | `Invalid username or password.` |
| 422 | `username and password are required.` |
| 429 | `Too many login attempts. Try again later.` |

Frontend mapping: `AuthService.login(...)` returns the session and persists it to
SharedPreferences under `poc_session`.

### 2.2 `GET /auth/me`

Protected. Returns the current user profile from the token.

Response `200` — same shape as the `data` object of `POST /auth/login` (minus `token`).
Used on cold start to validate a stored session. The Flutter app currently re-validates by
reading `poc_session` locally; this endpoint is the backend equivalent.

### 2.3 `POST /auth/logout`

Protected. Invalidates the token server-side (optional; the app may also just drop the
local session). Returns `204 No Content`.

### 2.4 `POST /auth/refresh`

`TBD — backend decision required` (see Section 15 TBD-2): refresh-token rotation, if
token lifetime requires it.

---

## 3. Inventory

### 3.1 Data model (item)

Derived from `InventoryItem` (`lib/models/inventory_item.dart`) and the persisted JSON.

| Field | Type | Notes |
| --- | --- | --- |
| `id` | string | PL number, e.g. `GRSP-0100`. Unique; `^[A-Za-z0-9-]+$`, uppercased. |
| `name` | string | Material description, e.g. `GRSP Sleeper 60 Kg`. |
| `quantity` | int | Total stock on hand. |
| `biIssued` | int | Quantity already issued against a bill/indent. |
| `available` | int | Derived: `max(quantity - biIssued, 0)`. Never persisted. |
| `uom` | string | Unit of measure (optional). |
| `status` | string | `Available` or `Unavailable`; derived from `available == 0`. |
| `section` | string | `Depot` \| `Sleeper` \| `Both`. |
| `searchFrequency` | int | Client-tracked search hit count (see 3.4). |
| `lastSearchedAt` | datetime? | Most recent search hit. |
| `lastEditedAt` | datetime? | Most recent create/edit. |
| `incomingQuantity` | int | Quantity on an open incoming/PO order. |
| `expectedAvailabilityDate` | date? | Expected arrival of incoming order. |
| `purchaseOrderStatus` | string | `none` \| `pending` \| `ordered`. |

Note: `searchFrequency` / `lastSearchedAt` / `lastEditedAt` are mutated by the client for
sorting/recency. They are persisted today; the backend should store them but they are not
security-relevant. (TBD-3: whether the backend wants to compute frequency server-side.)

### 3.2 Endpoints

#### `GET /inventory`

Roles: **viewer, admin, superadmin** — read.

Query params (optional):

| Param | Values | Notes |
| --- | --- | --- |
| `section` | `Depot`, `Sleeper`, `Both` | Filter by section membership. |
| `status` | `Available`, `Unavailable` | Client filters available/unavailable. |
| `q` | string | Client currently searches by `id`/`name` substring **client-side**; server-side search is optional (TBD-4). |

Response `200`:

```json
{
  "data": [
    {
      "id": "GRSP-0100",
      "name": "GRSP Sleeper 60 Kg",
      "quantity": 1200,
      "biIssued": 250,
      "available": 950,
      "uom": "pcs",
      "status": "Available",
      "section": "Depot",
      "searchFrequency": 12,
      "lastSearchedAt": "2026-08-14T08:00:00.000Z",
      "lastEditedAt": "2026-07-30T10:00:00.000Z",
      "incomingQuantity": 0,
      "expectedAvailabilityDate": null,
      "purchaseOrderStatus": "none"
    }
  ],
  "count": 1
}
```

#### `GET /inventory/{id}`

Roles: **viewer, admin, superadmin**. Returns the single item in `{ "data": {...} }`.
`404` with `detail: "Material not found."` if the PL is unknown.

#### `POST /inventory`

Roles: **admin, superadmin** (viewer forbidden). Creates a material (the app's
"ADD MATERIALS — DEPOT" and factory "ADD NEW MATERIALS" flows).

Request body:

```json
{
  "id": "GRSP-0200",
  "name": "GRSP Sleeper 60 Kg - New",
  "section": "Depot",
  "quantity": 500,
  "biIssued": 0,
  "incomingQuantity": 0,
  "expectedAvailabilityDate": null,
  "purchaseOrderStatus": "none"
}
```

- `id` required, unique (case-insensitive). Duplicate → `409` `detail: "Material PL already exists."`
- Sets `lastEditedAt` server-side.
- Returns `201` with the created item.

#### `PATCH /inventory/{id}`

Roles: **admin, superadmin** (viewer forbidden). Edits name/stock/BI/section/incoming
fields. The app's edit sheet allows editing **any** item, including out-of-stock ones.

Request body: any subset of `name`, `section`, `quantity`, `biIssued`, `incomingQuantity`,
`expectedAvailabilityDate`, `purchaseOrderStatus`; plus optional `id` to rename the PL
(reject on collision → `409`). Returns the updated item.

Notes for the backend:
- `available` is never written; always derived.
- The app's client-side edit sets `quantity` and `biIssued` as absolute values (not deltas).
- `lastEditedAt` updated on every edit.

### 3.3 Search / sort / filters (client-side)

Verified in `inventory_view.dart`: search by `id`/`name` substring, sort menu
(`Recent Searched`, `Recent Edited`, `Alphabetical A-Z`, `Alphabetical Z-A`), and a
"Most Frequently Searched" toggle are all computed **in the client** over the full list.
Consequences for the backend:

- `GET /inventory` should return the full (unpaginated or cursor-paginated) list; the
  client expects to sort/filter locally. Pagination contract is `TBD` (TBD-5) — the current
  UI renders all items in one `ListView`.
- Search-hit tracking: when the user searches, the client calls `registerSearch([...ids])`
  (in `InventoryController`) which increments `searchFrequency` and sets `lastSearchedAt`
  locally. There is **no** existing network call for this; if the backend must own these
  counters, add `POST /inventory/search-hits` (TBD-4).

### 3.4 Factories (Sleeper)

Derived from `WarehouseFactory` / `FactoryMaterial` (`lib/models/factory.dart`).
Factories group materials under the Sleeper section. A `FactoryMaterial` has the same
fields as an inventory item (`total` + `biIssued`, `available = max(total - biIssued, 0)`,
plus incoming/PO fields) but lives under a factory.

#### `GET /factories`

Roles: **viewer, admin, superadmin**. Returns all factories with their materials.

#### `GET /factories/{id}`

Roles: **viewer, admin, superadmin**.

#### `POST /factories`

Roles: **admin, superadmin**. Creates a factory. Body:

```json
{
  "name": "FACTORY_NAME_4",
  "location": "Delhi",
  "materials": [
    { "id": "F4-001", "name": "GRSP Sleepers 60 Kg", "total": 300, "biIssued": 0 }
  ]
}
```

- Empty material PLs are auto-generated (`PL-<n>`) by the client; backend may do the same.
- Name required → `422` if blank. Factory id generated server-side.
- Returns `201`.

#### `POST /factories/{id}/materials`

Roles: **admin, superadmin**. Adds a material to the factory (Sleeper "ADD NEW
MATERIALS"). Body: same fields as `POST /inventory`. Duplicate PL within the factory →
`409`. Returns `201`.

#### `PATCH /factories/{id}/materials/{materialId}`

Roles: **admin, superadmin**. Edits a factory material (same field semantics as
`PATCH /inventory/{id}`, scoped to the factory). `404` if material/factory unknown,
`409` on PL collision within the factory.

---

## 4. Viewer Requests

### 4.1 Data model

Derived from `ViewerRequest` (`lib/models/viewer_request.dart`).

| Field | Type | Notes |
| --- | --- | --- |
| `id` | string | Request id. |
| `viewerId` | string | Submitter's user id (e.g. `VW-1003`). |
| `viewerName` | string | Submitter display name. |
| `itemId` | string | Depot PL requested. |
| `itemName` | string | Material name (denormalized at submit time). |
| `quantity` | int | Requested quantity. |
| `createdAt` | datetime | Submit timestamp. |
| `section` | string | Always `Depot` today (requests target depot stock). |
| `status` | string | `Pending` \| `Accepted` \| `Rejected`. |
| `decisionBy` | string? | Actor role of the current decision: `admin` \| `superadmin`. Null while pending. |
| `decisionAt` | datetime? | Timestamp of the current decision. Null while pending. |
| `history` | list | Append-only entries `{ "status": "Accepted|Rejected|Undone", "actor": "<role>", "at": "<iso>" }`. |

Display labels (client-derived, `decisionActorLabel`):
`Accepted by Admin`, `Rejected by Superadmin`, `Pending`, etc.

### 4.2 Lifecycle and inventory side-effects (authoritative, from `inventory_controller.dart`)

1. **Create** (`Pending`). Viewer submits; quantity must be `>= 1` and `<= item.available`
   at submit time (client enforces this; **backend must re-enforce**).
2. **Accept** — allowed only on `Pending`. Effect:
   - `item.biIssued += quantity` (item `quantity`/total **unchanged**).
   - Precondition: `item.available >= quantity` at decision time. If not, the decision is
     refused **without** any inventory mutation (client returns "Insufficient stock").
   - Status → `Accepted`, `decisionBy`/`decisionAt` set, history entry appended.
   - An audit log entry `REQUEST ACCEPTED` is written (see Section 6).
3. **Reject** — allowed only on `Pending`. No inventory change. Status → `Rejected`.
   Audit entry `REQUEST REJECTED` written.
4. **Undo** — **superadmin only**. Allowed only on non-`Pending` (`Accepted`/`Rejected`).
   - If the request was `Accepted`: reverses the acceptance —
     `item.biIssued = max(item.biIssued - quantity, 0)` (total unchanged).
   - If it was `Rejected`: no inventory change.
   - Status → `Pending`, `decisionBy`/`decisionAt` cleared, history entry
     `{status: "Undone", actor: "superadmin"}` appended (the original decision is preserved
     in history).
   - Audit entry `REQUEST UNDONE` written.
   - The request is then re-decidable (Pending again).

Summary matrix:

| Action | Roles | Allowed when | Inventory effect |
| --- | --- | --- | --- |
| Create | viewer | always | none |
| Accept | admin, superadmin | `Pending` | `biIssued += qty` (total unchanged) |
| Reject | admin, superadmin | `Pending` | none |
| Undo | **superadmin** | not `Pending` | if was Accepted: `biIssued -= qty` (≥ 0); else none |

### 4.3 Endpoints

#### `POST /requests`

Roles: **viewer, admin, superadmin** can submit in principle; the frontend exposes the
form **only to viewer** (`ViewerRequestsView`). Keep `admin`/`superadmin` as allowed for
API symmetry, or restrict to viewer — `TBD` (TBD-6).

Request body:

```json
{
  "itemId": "GRSP-0100",
  "quantity": 25
}
```

Server behavior:
- Validate `quantity >= 1` and `quantity <= item.available` → `422`
  `"Cannot exceed available quantity (N)."` otherwise.
- `viewerId`/`viewerName` taken from the authenticated token, not the body.
- Returns `201` with the created request (`status: "Pending"`).

#### `GET /requests`

Roles: **viewer, admin, superadmin**.

- `viewer`: sees **only their own** requests (the frontend's `ViewerHistoryView` is the
  viewer's own-request history). Consider filtering server-side.
- `admin`: sees pending + processed (the `AdminRequestsView` shows both).
- `superadmin`: sees all (pending + processed) with undo capability.

Optional query params: `status` (`Pending|Accepted|Rejected`), `viewerId`.

#### `GET /requests/{id}`

Roles: **viewer, admin, superadmin** (viewer scoped to own). Returns request with full
`history`.

#### `POST /requests/{id}/accept`

Roles: **admin, superadmin**. Body: empty or `{}`. Behavior per 4.2 item 2.

Responses:

| Status | Body `detail` |
| --- | --- |
| 200 | updated request in `{ "data": {...} }` |
| 409 | `Request already processed.` (not pending) |
| 409 | `Insufficient available stock for this request.` (no mutation performed) |
| 404 | `Request not found.` |

#### `POST /requests/{id}/reject`

Roles: **admin, superadmin**. Body: empty or `{}`. Behavior per 4.2 item 3.
`409` `Request already processed.` when not pending; `404` unknown id.

#### `POST /requests/{id}/undo`

Roles: **superadmin only**. Admin → `403`. Behavior per 4.2 item 4.
`409` `Request is pending; nothing to undo.` when already pending; `404` unknown id.

---

## 5. Actions / Transactions

### 5.1 Transaction semantics (authoritative, from `addTransaction` in `inventory_controller.dart`)

A transaction is one of `INCOMING` or `DISPATCH` (plus implicit audit entries created by
request decisions and edits, Section 6). Every transaction carries a **proof/bill image**
which is **mandatory** for both incoming and dispatch (the UI blocks submit without it).

Inventory effects (per item):

| Transaction | Section | `quantity` (on hand) | `biIssued` | Factory material `total` |
| --- | --- | --- | --- | --- |
| INCOMING | Depot or Sleeper | `+qty` | unchanged | `+qty` when factory-scoped |
| DISPATCH | Depot | unchanged | `+qty` | n/a |
| DISPATCH | Sleeper (factory) | `−qty` if a matching PL exists | unchanged | `−qty` |

Rules verified in code:
- Dispatch always validates available stock first: depot dispatch needs
  `item.available >= qty`; factory dispatch is subject to the factory material's stock.
  Client message: `Insufficient available stock for dispatch.`
- Quantities are never allowed to go negative (clamped to `0`).
- **Edit / correction** (`editTransaction`, superadmin-only): reverses the original
  transaction's effect, then applies the new quantities, using the same per-type rules.
  Only `INCOMING` and `DISPATCH` logs are editable.
- All transaction changes are persisted and broadcast to listeners for real-time UI updates.

### 5.2 Data model (`TransactionLog`, `lib/models/transaction_log.dart`)

| Field | Type | Notes |
| --- | --- | --- |
| `id` | string | Log id. |
| `timestamp` | datetime | When recorded. |
| `type` | string | `INCOMING` \| `DISPATCH` \| `EDIT` \| `REQUEST ACCEPTED` \| `REQUEST REJECTED` \| `REQUEST UNDONE`. |
| `user` | string | Username of the actor. |
| `items` | list | `[{ "id", "name", "quantityChange" }]` — signed per type (positive for incoming/depot-dispatch; negative for factory dispatch). |
| `notes` | string? | Free text. |
| `photo` | string? | Original filename (stored as `[PROOF_ATTACHED.jpg]` marker today). |
| `photoData` | string? | Base64 image, only when `size <= 1 MiB` (client quirk, see TBD-7). |
| `refLogId` | string? | For `EDIT`: the id of the edited transaction. |
| `oldItems` | list? | For `EDIT`: the original items. |
| `section` | string? | `Depot` \| `Sleeper` (null for legacy logs). |
| `factoryName` | string? | For Sleeper-scoped transactions. |
| `person` | string? | Incoming: person in-charge; Dispatch: requested-by. |
| `comingFrom` | string? | Incoming only. |
| `dateOfArrival` | string? | Incoming only (display `dd MMM yyyy`). |
| `dateRequested` | string? | Dispatch only. |
| `dateLeaving` | string? | Dispatch only; must be `>= dateRequested` (client validates). |
| `truckNumber` | string? | Both. |

Dispatch form fields (from `transactions_view.dart`): requested by, request date,
leaving date, truck number + proof. Incoming form: person, coming from, date of arrival,
truck number + proof.

### 5.3 Endpoints

#### `GET /transactions`

Roles: **admin, superadmin**. (`viewer` has no ACTIONS/AUDIT tab in the frontend and no
history of transactions — see Section 6 and the discrepancy note in Section 16.)

Optional query params: `section` (`Depot|Sleeper`), `factoryName`, `type`, `dateFrom`,
`dateTo`. Returns newest-first list in `{ "data": [...], "count": N }`.

#### `POST /transactions`

Roles: **admin, superadmin**. Creates an incoming or dispatch transaction. The app sends
a JSON payload plus an image; model the endpoint as **multipart/form-data**
(following the reference spec):

| Form field | Type | Notes |
| --- | --- | --- |
| `type` | string | `INCOMING` \| `DISPATCH` |
| `items` | JSON string | `[{"id":"GRSP-0100","quantityChange":50}, ...]` |
| `notes` | string? | |
| `section` | string? | `Depot` \| `Sleeper` |
| `factoryName` | string? | Required when `section == Sleeper` |
| `person` | string? | |
| `comingFrom` | string? | Incoming only |
| `dateOfArrival` | string? | Incoming only |
| `dateRequested` | string? | Dispatch only |
| `dateLeaving` | string? | Dispatch only |
| `truckNumber` | string? | |
| `file` | binary | Proof/bill image, **mandatory**. |

Server behavior:
- Validates stock for dispatch (depot: `available >= qty`; factory: factory material stock).
  Failure → `409` `Insufficient available stock for dispatch.`
- Validates `dateLeaving >= dateRequested` for dispatch → `422`.
- Requires `file` → `422` `Bill / proof is mandatory.`
- Applies inventory effects from Section 5.1 atomically, writes the transaction log, and
  broadcasts a real-time event (Section 13).
- Returns `201` with the created transaction (image served separately, Section 7).

#### `GET /transactions/{id}`

Roles: **admin, superadmin**. Single transaction.

#### `PATCH /transactions/{id}`

Roles: **superadmin only** (admin → `403`). Corrects an existing `INCOMING` or `DISPATCH`
transaction (the app's audit edit flow).

Request body (JSON):

```json
{
  "items": [{ "id": "GRSP-0100", "quantityChange": 75 }]
}
```

Server behavior:
- Only `INCOMING` / `DISPATCH` targets (others → `422`).
- Reverses the original effect, applies the new quantities (per-type rules), clamps to 0.
- Writes a new `EDIT` audit entry with `refLogId` = target id and `oldItems`/`items`.
- Returns `200` with the new `EDIT` log. Broadcasts real-time update.

#### `DELETE /transactions/{id}`

No such operation exists in the client. `TBD` (TBD-8) whether the backend offers
deletion; the current product only supports correction via `PATCH`.

---

## 6. Audit / Logs

The audit trail is the full `TransactionLog` stream (Section 5.2). Request decisions and
undoes each append a log entry (`REQUEST ACCEPTED` / `REQUEST REJECTED` / `REQUEST UNDONE`)
whose `items` carry the requested quantity and whose `notes` read e.g.:

```
Viewer Request REQ-... — Accepted by Admin. Viewer: <name> (<id>)
```

### Endpoints

#### `GET /logs`

Roles: **admin, superadmin**. (`viewer` cannot see audit — no AUDIT tab in `ViewerShell`;
see Section 16 discrepancy note.)

Optional query params: `section`, `factoryName`, `type`, `user`, `dateFrom`, `dateTo`.
Returns newest-first.

#### `GET /logs/{id}`

Roles: **admin, superadmin**.

#### `GET /logs/{id}/proof`

Roles: **admin, superadmin**. Returns the proof image bytes (`image/jpeg`|`image/png`).
`404` if the log has no image or it was dropped because it exceeded the size limit
(Section 7). The Flutter detail dialog renders the image via `Image.memory(base64Decode(photoData))`
and shows a "View Proof" affordance only when image data is present.

---

## 7. Files / Proofs

The client currently:
- Picks an image via `image_picker` (camera or gallery), reads bytes, and **base64-encodes
  in memory**.
- Stores the base64 only when `size <= 1024 * 1024` bytes (1 MiB). **Oversized images are
  silently dropped** — the log keeps the filename and shows "Proof Attached" but there is
  no viewable image (client quirk worth flagging; see TBD-7).
- Displays stored proofs with `Image.memory`.

### Endpoints

#### `POST /files`

Roles: **admin, superadmin** (uploads come from transaction creation). Accepts
`multipart/form-data` with a `file` field. Returns `201`:

```json
{ "data": { "id": "<file-id>", "url": "/api/v1/files/<file-id>", "size": 524288 } }
```

Rejects with `413` `Payload Too Large` when the file exceeds the configured limit
(TBD-7 decides the limit; client cap is 1 MiB today).

#### `GET /files/{id}`

Roles: **admin, superadmin** (and any role if the proof is attached to a resource they may
read — `TBD`, TBD-9). Streams the stored bytes with the correct `Content-Type`.

Design note: transactions reference the proof by `file_id` instead of embedding base64.
This is the main migration from the current `photoData` base64 column; the Flutter client
change is out of scope for this document but the wire format is defined here so the client
can be adapted to it.

---

## 8. Permissions / Account Requests (New User registration)

The app has an account-request workflow (superadmin approves) rather than open signup.

### 8.1 Data model (`AccountRequest`, `lib/models/account_request.dart`)

| Field | Type | Notes |
| --- | --- | --- |
| `id` | string | Request id. |
| `name` | string | Display name. |
| `requestedId` | string | Desired login ID, uppercased; `^[A-Za-z0-9-]+$`, min 3 chars. |
| `password` | string | **Carried on the request in plaintext today** — see TBD-10. Never returned to any client after submission. |
| `role` | string | Only `admin` \| `viewer` may be requested (the form hides `superadmin`). |
| `submittedAt` | datetime | |
| `status` | string | `Pending` \| `Accepted` \| `Rejected`. |
| `decisionBy` | string? | `superadmin` (only role allowed to decide). |
| `decisionAt` | datetime? | |

### 8.2 Endpoints

#### `POST /account-requests`

**Anonymous / public** (the NEW USER form is on the login screen, before authentication).

Request body:

```json
{
  "name": "Ravi Kumar",
  "requestedId": "RV-2001",
  "password": "abcd",
  "role": "viewer"
}
```

Server validation (mirrors `NewUserRequestView` + `AuthService.isAccountIdTaken`):
- `requestedId` pattern `^[A-Za-z0-9-]+$`, min length 3 → `422`.
- `role` ∈ {`admin`, `viewer`}; `superadmin` → `422`.
- `password` min length 4 → `422` (TBD-10: whether to strengthen).
- **Duplicate guard**: requested ID must not collide with built-in accounts
  (`superadmin`/`admin`/`viewer`), existing custom accounts, or an existing *pending*
  account request → `409` `"That ID is already taken."`
- Returns `201` `{ "data": { "id": ..., "status": "Pending", ... } }` — **without `password`**.

#### `GET /account-requests`

Roles: **superadmin only** (admin → `403`; the frontend's `SuperadminPermissionView` is the
only consumer). Query param `status` optional. Returns list (no passwords).

#### `POST /account-requests/{id}/approve`

Roles: **superadmin only**. Creates the user account (id uppercased; username = lowercased
id), sets status `Accepted`, records `decisionBy`/`decisionAt`.
- Already decided → `409` `Request already processed.`
- Duplicate with an existing account at approval time → `409`.
- Returns the request (no password) + the created user.

#### `POST /account-requests/{id}/reject`

Roles: **superadmin only**. Sets status `Rejected`. Already decided → `409`.

---

## 9. Users

### `GET /users`

Roles: **superadmin only** (permission management surface is superadmin-only).

Returns all accounts (built-in + approved custom):

```json
{
  "data": [
    { "id": "AD-1002", "username": "admin", "name": "Admin User", "role": "admin", "createdAt": "2026-01-01T00:00:00.000Z" }
  ],
  "count": 1
}
```

Never returns passwords/hashes. Future user management (reset password, role change,
deactivate) — `TBD` (TBD-11). The Flutter app has no such UI today.

---

## 10. Data Models (summary)

| Model | Section | Key fields |
| --- | --- | --- |
| AuthSession / User | 2, 9 | `username`, `role`, `name`, `id` |
| InventoryItem | 3 | `id`, `name`, `quantity`, `biIssued`, `available*`, `status*`, `section`, `uom`, `searchFrequency`, `lastSearchedAt`, `lastEditedAt`, `incomingQuantity`, `expectedAvailabilityDate`, `purchaseOrderStatus` |
| WarehouseFactory / FactoryMaterial | 3.4 | factory: `id`, `name`, `location`, `materials[]`; material: like InventoryItem (total/biIssued) |
| ViewerRequest | 4 | `id`, `viewerId`, `viewerName`, `itemId`, `itemName`, `quantity`, `createdAt`, `section`, `status`, `decisionBy`, `decisionAt`, `history[]` |
| TransactionLog | 5.2 | `id`, `timestamp`, `type`, `user`, `items[]`, `notes`, `photo`, `photoData`/`fileId`, `refLogId`, `oldItems[]`, `section`, `factoryName`, `person`, `comingFrom`, `dateOfArrival`, `dateRequested`, `dateLeaving`, `truckNumber` |
| AccountRequest | 8.1 | `id`, `name`, `requestedId`, `password*`, `role`, `submittedAt`, `status`, `decisionBy`, `decisionAt` |

`*` = derived or internal (never the source of truth on the wire for mutation).

**Enum / label sets**:
- Roles: `viewer`, `admin`, `superadmin`.
- Request status: `Pending`, `Accepted`, `Rejected`.
- Transaction type: `INCOMING`, `DISPATCH`, `EDIT`, `REQUEST ACCEPTED`, `REQUEST REJECTED`, `REQUEST UNDONE`.
- Purchase order status: `none`, `pending`, `ordered`.
- Item status (derived): `Available`, `Unavailable`.
- Item section: `Depot`, `Sleeper`, `Both`.

---

## 11. Role Matrix

| Endpoint | Method | viewer | admin | superadmin | Notes |
| --- | --- | --- | --- | --- | --- |
| `/auth/login` | POST | ✅ | ✅ | ✅ | public |
| `/auth/me` | GET | ✅ | ✅ | ✅ | token required |
| `/auth/logout` | POST | ✅ | ✅ | ✅ | |
| `/auth/refresh` | POST | TBD | TBD | TBD | TBD-2 |
| `/inventory` | GET | ✅ | ✅ | ✅ | |
| `/inventory` | POST | ❌ | ✅ | ✅ | |
| `/inventory/{id}` | GET | ✅ | ✅ | ✅ | |
| `/inventory/{id}` | PATCH | ❌ | ✅ | ✅ | |
| `/factories` | GET | ✅ | ✅ | ✅ | |
| `/factories` | POST | ❌ | ✅ | ✅ | |
| `/factories/{id}` | GET | ✅ | ✅ | ✅ | |
| `/factories/{id}/materials` | POST | ❌ | ✅ | ✅ | |
| `/factories/{id}/materials/{materialId}` | PATCH | ❌ | ✅ | ✅ | |
| `/requests` | POST | ✅ | TBD | TBD | form is viewer-only in UI; TBD-6 |
| `/requests` | GET | own only | all | all | |
| `/requests/{id}` | GET | own only | all | all | |
| `/requests/{id}/accept` | POST | ❌ | ✅ | ✅ | |
| `/requests/{id}/reject` | POST | ❌ | ✅ | ✅ | |
| `/requests/{id}/undo` | POST | ❌ | ❌ | ✅ | **superadmin-only** |
| `/transactions` | GET | ❌ | ✅ | ✅ | no viewer UI (Section 16) |
| `/transactions` | POST | ❌ | ✅ | ✅ | multipart + mandatory file |
| `/transactions/{id}` | GET | ❌ | ✅ | ✅ | |
| `/transactions/{id}` | PATCH | ❌ | ❌ | ✅ | **superadmin-only** correction |
| `/logs` | GET | ❌ | ✅ | ✅ | no viewer UI (Section 16) |
| `/logs/{id}` | GET | ❌ | ✅ | ✅ | |
| `/logs/{id}/proof` | GET | ❌ | ✅ | ✅ | |
| `/files` | POST | ❌ | ✅ | ✅ | |
| `/files/{id}` | GET | TBD | ✅ | ✅ | TBD-9 |
| `/account-requests` | POST | ✅ (public) | ✅ (public) | ✅ (public) | anonymous |
| `/account-requests` | GET | ❌ | ❌ | ✅ | **superadmin-only** |
| `/account-requests/{id}/approve` | POST | ❌ | ❌ | ✅ | **superadmin-only** |
| `/account-requests/{id}/reject` | POST | ❌ | ❌ | ✅ | **superadmin-only** |
| `/users` | GET | ❌ | ❌ | ✅ | **superadmin-only** |
| WS `/ws/inventory` | — | ✅ | ✅ | ✅ | push-only, Section 13 |

Legend: ✅ allowed · ❌ forbidden (403) · TBD under review.

---

## 12. Errors

Uniform error envelope:

```json
{
  "detail": "Human readable reason",
  "error": { "code": "VALIDATION_ERROR", "field": "quantity" }
}
```

| HTTP | `code` | Typical trigger |
| --- | --- | --- |
| 400 | `BAD_REQUEST` | malformed JSON / multipart |
| 401 | `UNAUTHORIZED` | missing/invalid/expired token, bad credentials |
| 403 | `FORBIDDEN` | role not allowed on the endpoint |
| 404 | `NOT_FOUND` | unknown id (material, request, transaction, log, file) |
| 409 | `CONFLICT` | duplicate PL, already-processed request, insufficient stock, taken ID |
| 413 | `PAYLOAD_TOO_LARGE` | proof image above upload limit (TBD-7) |
| 422 | `VALIDATION_ERROR` | field-level validation failures |
| 429 | `RATE_LIMITED` | login/abuse throttling |
| 500 | `SERVER_ERROR` | unexpected failure |

Validation details: when a request body fails field validation, return `422` and, where
useful, `error.field` naming the offending field. The Flutter app reads snackbar messages
from plain strings, so `detail` should be user-presentable.

---

## 13. Real-Time

- **Endpoint**: `WS /ws/inventory` (per the reference spec).
- **Auth**: first message or query/token handshake with the JWT (`?token=` or a
  `{"type":"auth","token":"..."}` frame). All three roles may connect (viewer = read-only).
- **Purpose**: the app is a single-user demo today, but the controller persists and
  re-renders on every mutation (`ChangeNotifier`). A multi-device backend needs to push:
  - `inventory_changed` — after `POST /inventory`, `PATCH /inventory/{id}`, any transaction,
    any request accept/undo.
  - `transaction_created` — after `POST /transactions`.
  - `transaction_updated` — after `PATCH /transactions/{id}` (superadmin correction).
  - `request_updated` — after accept/reject/undo, targeted at the owning viewer + all
    admin/superadmin sessions.
  - `account_request_created` — to superadmin sessions.
  - `account_request_updated` — to superadmin sessions.
- **Event envelope**:

  ```json
  { "type": "request_updated", "data": { "requestId": "...", "status": "Accepted" } }
  ```

- **Current state of the client**: there is **no WebSocket / SSE / polling code in the
  Flutter app today** (verified: no `http`, `dio`, `Uri.parse`, `WebSocket`, or `HttpClient`
  usage anywhere under `lib/`). The frontend is entirely local and reactive to its own
  `InventoryController`. Therefore the WS is **not currently consumed** and is specified as
  the forward-looking contract for a multi-user deployment. No endpoint in this document
  blocks on it; all REST responses already return the authoritative resource.

---

## 14. Flutter Service → Endpoint Mapping

| Flutter service / view | Current local behavior | Backend endpoint(s) |
| --- | --- | --- |
| `AuthService.login` | verifies credentials, builds session, saves `poc_session` | `POST /auth/login` |
| `AuthService.createAccount` | persists custom account after superadmin approval | `POST /account-requests/{id}/approve` (server-side account creation) |
| `AuthService.isAccountIdTaken` | duplicate check across built-ins + custom | `POST /account-requests` `409` guard |
| `AccountRequestService.addRequest` | NEW USER form submit | `POST /account-requests` |
| `AccountRequestService` load/approve/reject | permission list + decisions | `GET /account-requests`, `POST /account-requests/{id}/approve` / `.../reject` |
| `InventoryService.loadInventory/saveInventory` | SharedPreferences `warehouse_inventory`, CSV seed | `GET /inventory`, `POST /inventory`, `PATCH /inventory/{id}` |
| `InventoryService.loadFactories/saveFactories` | SharedPreferences `warehouse_factories`, demo seed | `GET /factories`, `POST /factories`, `POST/PATCH .../materials` |
| `InventoryService.loadLogs/saveLogs` | SharedPreferences `warehouse_logs` | `GET /logs`, `GET /transactions` |
| `RequestService.addRequest` | viewer request submit | `POST /requests` |
| `RequestService.loadRequests/updateStatus` | viewer history + admin/superadmin lists | `GET /requests`, `POST /requests/{id}/accept`/`reject`/`undo` |
| `InventoryController.addTransaction` | incoming/dispatch + audit log + proof base64 | `POST /transactions` (multipart), `POST /files` |
| `InventoryController.editTransaction` | superadmin audit correction | `PATCH /transactions/{id}` |
| `InventoryController.acceptRequest/rejectRequest/undoRequest` | request decisions + audit entries | `POST /requests/{id}/accept|reject|undo` |
| `InventoryController.addMaterial/editMaterial/editFactoryMaterial/addFactory` | depot/sleeper material CRUD | `POST/PATCH /inventory`, `POST/PATCH /factories...` |
| `InventoryController.registerSearch` | client-side frequency counters | (client-only today) — TBD-4 |
| `InventoryView` search/sort/filter | 100% client-side over full list | none required; pagination TBD-5 |
| `LogsView` detail + proof dialog | `Image.memory(base64Decode(photoData))` | `GET /logs/{id}/proof` or `GET /files/{id}` |
| `TransactionsView` proof picker | `image_picker` + 1 MiB cap | `POST /files` (server-side cap TBD-7) |

---

## 15. Backend Implementation Notes

1. **Atomicity**: every mutating endpoint that touches both inventory and logs
   (transactions, request accept/undo, correction) must apply inventory + audit +
   broadcast in a single transaction; on failure nothing is partially written.
2. **Idempotency / concurrency**: request accept/reject/undo and account-request
   approve/reject must be guarded by the `Pending` check **under a row lock** to avoid
   double-processing when two admins act simultaneously. The Flutter app enforces the same
   guard in-memory; the backend is the source of truth.
3. **Validation must live on the server** (not just the client): stock availability for
   dispatch and request acceptance, quantity bounds, PL uniqueness, date ordering.
4. **Seeding**: the app seeds depot inventory from `assets/material_serial_mappings.csv`
   and three demo factories on first run. The backend should provide a seed/migration for
   the same demo dataset (or leave seeding to the client via `POST`).
5. **Proofs**: store files on disk/object store; store `fileId` on the transaction/log.
   Do not round-trip base64 in JSON responses.
6. **Auth**: JWT with `sub`, `role`, `name`, `id` claims. Expiry + refresh policy TBD-2.
   Never log or return password material.
7. **Migration path**: the current client has zero network code; adopting this API is a
   client-side refactor (swap `SharedPreferences` services for an HTTP client) that is out
   of scope here but is safe because the resource shapes above mirror the existing JSON
   the client already serializes.
8. **Rate limiting** on `/auth/login` and anonymous `/account-requests` (TBD-12).
9. **Logging**: audit `EDIT` entries reference the original transaction via `refLogId`;
   request audit entries embed the request id + actor role in `notes`; keep both patterns
   consistent, ideally with structured fields (`refRequestId`, `actorRole`).

## 16. Discrepancies vs. the baseline role assumptions

Verified against the actual code; items where the app **differs from** a naive
"viewer = read everything, admin = full, superadmin = full + override" baseline:

1. **Viewer cannot read transactions or the audit log at all.** `ViewerShell` has only
   INVENTORY | REQUESTS | HISTORY; there is no ACTIONS or AUDIT tab. HISTORY is the
   viewer's **own request history**, not inventory change history. → `GET /transactions`,
   `GET /logs`, `GET /logs/{id}`, `GET /transactions/{id}` are admin/superadmin-only in the
   matrix above.
2. **Undo/override is strictly superadmin.** Admins can accept/reject pending requests but
   have no undo control; only `POST /requests/{id}/undo` exists and rejects non-superadmins.
3. **Permission management is strictly superadmin.** Admins have no account-request list
   or approval surface.
4. **Admin can create/edit inventory** (depot and sleeper/factory materials), so
   `POST/PATCH /inventory` and the factory material endpoints are **admin+**, not
   superadmin-only.
5. **Transaction correction is strictly superadmin** (`LogsView.canEdit = _isSuperadmin`),
   matching `PATCH /transactions/{id}` being superadmin-only.
6. **Request submission is viewer-centric in the UI**; admin/superadmin have no request
   form, so the `admin`/`superadmin` allowance on `POST /requests` is a design choice
   (TBD-6), not a demonstrated behavior.
7. **Client caps proof images at 1 MiB and silently drops larger ones** — the uploaded
   proof is stored (filename) but never viewable. The backend should define the real limit
   (TBD-7) and reject with `413` rather than silently truncating.
8. **Client-side enforcement is not a substitute for server-side checks**: the frontend
   blocks over-available request quantities and dispatch stock at submit time; the backend
   must re-check at decision/creation time (stock may have changed between screens).

## 17. Open Questions (TBD)

- TBD-1: Migrate generated `microsecondsSinceEpoch` ids to UUIDs.
- TBD-2: JWT expiry, refresh token strategy.
- TBD-3: Own search-frequency counters server-side or keep client-side.
- TBD-4: Server-side search (`q` param) vs. pure client filtering; `POST /inventory/search-hits`.
- TBD-5: Pagination contract for inventory/logs/transactions/requests.
- TBD-6: Allow `admin`/`superadmin` to submit viewer requests via API.
- TBD-7: Proof upload size limit and file storage backend (current client cap 1 MiB).
- TBD-8: Transaction deletion support.
- TBD-9: `GET /files/{id}` access scope (any authenticated role vs. admin+).
- TBD-10: Password storage on account requests (plaintext today) → send hashed/one-time use; password policy (min 4 chars today).
- TBD-11: User management (password reset, role change, deactivate).
- TBD-12: Rate limiting / abuse controls for public endpoints.
- TBD-13: API versioning, CORS origins, TLS requirements.

---

*This document was produced by analyzing the existing Flutter codebase only. No Dart/Flutter
source files, `pubspec.yaml`, or project configuration were modified. No backend code was
written.*
