# Railway Warehouse Flutter API Contract

**Contract status:** Implemented — this document describes only behavior
implemented by the current backend, verified against the route
implementation and generated `openapi.json`. After final review, place
this exact file in the frontend repository so both sides share it.

**Base path:** `/api/v1`

**Wire format:** lowerCamelCase JSON; multipart only for file upload

## 1. Conventions

### 1.1 Base URL and transport

The Flutter build receives `WAREHOUSE_API_BASE_URL`. If it already ends in
`/api/v1`, the client uses it unchanged; otherwise the client appends
`/api/v1`. The development default is `http://localhost:8000`. Production must
use the deployed HTTPS origin.
JSON bodies send `Content-Type: application/json`.

### 1.2 Authentication and authorization

Protected requests use:

```http
Authorization: Bearer <accessToken>
```

Access tokens remain in memory. Refresh tokens are transported only in Secure,
HttpOnly, SameSite cookies and never appear in a JSON request or response,
client-readable storage, URL, or application log. Authentication endpoints use
the cookie directly; no client-type header selects or alters refresh-token
transport. The backend enforces authorization and data scope; frontend
visibility is not a security boundary.
Wire roles are exactly `VIEWER`, `ADMIN`, and `SUPERADMIN`. Wire module names
are exactly `DEPOT` and `SLEEPER`. Transaction scope values are `DEPOT` and
`FACTORY`; `SLEEPER` UI/module operations map to `FACTORY` plus an
authoritative `factoryId`. `BOTH` is inventory catalog membership only.

### 1.3 IDs, dates, and normalization

- Server-generated identifiers are opaque lowercase UUIDv4 strings. Material
  IDs are authoritative domain strings and case-insensitively unique.
- Every mutation uses authoritative IDs. Names, list indexes, timestamps,
  material names, filenames, and display labels are never identities.
- Timestamps are server-authored ISO-8601 UTC strings ending in `Z`.
  Every serialized timestamp (`createdAt`, `updatedAt`, `decisionAt`, every
  `history[].at`, audit `occurredAt`, account approval/rejection timestamps)
  carries an explicit zone; naive datetimes are never emitted. For one
  decision, `decisionAt` and the corresponding latest history entry
  represent the same instant. Operational date-only values use `YYYY-MM-DD`.
- The backend trims surrounding whitespace from identifiers and display
  text. Login identifiers compare case-insensitively; usernames are stored
  lowercase while the canonical `accountId` preserves the submitted
  uppercase value.

### 1.4 Pagination, filtering, and sorting

Collections use cursor pagination:

```text
limit=1..100                 default 50
cursor=<opaque token>        omitted for the first page
q=<case-insensitive text>    maximum 100 characters where supported
sort=<field>,asc|desc        canonical field and direction
```

```json
{
  "data": [],
  "page": {"limit": 50, "nextCursor": null, "hasMore": false},
  "meta": {"requestId": "70f772bf-87fd-43b9-a70a-f78e62ed9c6d"}
}
```

There is no total count. When `hasMore` is true, `nextCursor` is non-null,
opaque, and non-repeating. Cursors are composite `(timestamp, id)` tokens,
so rows sharing a timestamp are never skipped or repeated; combining a
cursor with a custom sort returns `400`. Canonical newest-first sorting is
`sort=createdAt,desc` for requests and transactions and
`sort=occurredAt,desc` for audits. The legacy `-field` form (for example
`-createdAt`) remains accepted.

### 1.5 Envelopes and HTTP behavior

Successful `200`/`201` JSON single-resource responses use:

```json
{
  "data": {},
  "meta": {"requestId": "70f772bf-87fd-43b9-a70a-f78e62ed9c6d"}
}
```

Binary file-content responses do not use a JSON envelope. Resource creation
returns `201`; reads and state transitions return `200`. Account
deactivation and factory archival return `200` with the updated resource;
file deletion returns `204`. Errors use:

```json
{
  "error": {
    "code": "VALIDATION_ERROR",
    "message": "The request could not be validated.",
    "details": [],
    "retryable": false
  },
  "meta": {"requestId": "70f772bf-87fd-43b9-a70a-f78e62ed9c6d"}
}
```

| HTTP | Meaning and standard codes |
| --- | --- |
| `400` | Validation failure or malformed request: `BAD_REQUEST` |
| `401` | Unauthenticated: `UNAUTHORIZED`, `TOKEN_EXPIRED`, `INVALID_REFRESH_TOKEN` |
| `403` | Authenticated but unauthorized: `FORBIDDEN`, `ACCOUNT_INACTIVE` |
| `404` | Resource absent or concealed: `NOT_FOUND` |
| `409` | Conflict/already processed: `CONFLICT`, `DUPLICATE_ID`, `INVALID_TRANSITION`, `INSUFFICIENT_STOCK`, `IDEMPOTENCY_CONFLICT`, `FILE_IN_USE`, `CONSISTENCY_CONFLICT`, `REQUEST_ALREADY_FULFILLED`, `SOURCE_REQUEST_ITEMS_MISMATCH`, `FACTORY_HAS_ACTIVE_DEPENDENCIES`, `LAST_SUPERADMIN`, `SELF_MANAGEMENT_FORBIDDEN` |
| `412` | Stale `If-Match`: `VERSION_CONFLICT` |
| `413` | File too large: `FILE_TOO_LARGE` |
| `415` | Unsupported or invalid content: `UNSUPPORTED_MEDIA_TYPE` |
| `422` | Business/semantic validation: `VALIDATION_ERROR`, `MALWARE_DETECTED` |
| `428` | Required `Idempotency-Key` or `If-Match` missing: `PRECONDITION_REQUIRED` |
| `429` | Rate limited: `RATE_LIMITED`, with integer-seconds `Retry-After` |
| `500` | Server failure: `INTERNAL_ERROR`; no stack trace |
| `503` | Temporary dependency failure: `SERVICE_UNAVAILABLE`, normally retryable |

Unknown fields are rejected with `422 VALIDATION_ERROR`. `400` is reserved for
malformed syntax/cursors; domain rules use `422` or `409` as shown above.

### 1.6 Idempotency and optimistic locking

Every business mutation, including `DELETE`, requires a UUID
`Idempotency-Key`, except login, refresh, and logout. Each independently-created
request line and each uploaded file receives its own key. The same key and same
request returns the original result without repeating side effects and may set
`Idempotency-Replayed: true`; a different request returns
`409 IDEMPOTENCY_CONFLICT`. A missing or malformed key returns `428`. A network
retry reuses the key. Mutable resources expose integer `version` and
`ETag: "<version>"`. `PATCH`, delete, and state transitions require
`If-Match: "<version>"`. A stale version returns `412 VERSION_CONFLICT`;
the client reloads rather than silently merging.

| Endpoint | `Idempotency-Key` | `If-Match` |
| --- | --- | --- |
| Account approval/rejection | Required | Required |
| Account deactivation | Required | Required |
| Factory archive | Required | Required |
| Request creation | Required; no version exists at creation | — |
| Request Accept / Reject / Undo | Required | Required |
| Transaction creation | Required | — |
| Transaction correction / reverse | Required | Required |
| File upload / delete | Required | Required for delete |

## 2. Authentication and Accounts

### 2.1 Session endpoints

| Method and path | Role | Request | Success |
| --- | --- | --- | --- |
| `POST /auth/login` | Public | `{"username":"employee123","password":"submitted password"}` | `200` token set and active user |
| `POST /auth/refresh` | Refresh-token cookie holder | Empty JSON object or no body; refresh cookie is sent automatically | `200` rotated refresh cookie, access token, and active user |
| `POST /auth/logout` | Authenticated | Empty JSON object or no body; refresh cookie is sent automatically | `204` and expired refresh cookie |
| `GET /auth/me` | Authenticated | No body | `200` active user |

Login and refresh return `accessToken`, `accessTokenExpiresAt`, `tokenType:
"Bearer"`, and `user` containing `id`, `accountId`, `username`, `name`,
`role`, `status: "ACTIVE"`, `createdAt`, `updatedAt`, and integer `version`.
Pending, rejected, or deactivated accounts cannot authenticate. Invalid
credentials return `401`; inactive accounts return `403`; malformed fields
return `422`; throttling may return `429`. The backend sets and rotates the
refresh token only with `Set-Cookie`; the response JSON never contains a
refresh token or its expiry. No credential appears in logs or error details.

### 2.2 New account request

```http
POST /account-requests
Accept: application/json
Content-Type: application/json
Idempotency-Key: 29ea59d5-cc53-42bd-9ff3-8b483b22125d
```

```json
{
  "name": "Employee Name",
  "requestedId": "EMPLOYEE123",
  "password": "submitted password",
  "role": "VIEWER"
}
```

Fields are `name` (1–200 chars), `requestedId` (3–64 chars,
letters/digits/hyphen), `password` (minimum 12 chars), and `role`
(`VIEWER` or `ADMIN`). `confirmPassword` is a frontend-only control and is
never transmitted, persisted, logged, audited, or returned. The backend
hashes the submitted password with Argon2id immediately; passwords and
hashes never appear in any response. `requestedId` is trimmed and enforced
unique case-insensitively against users and unresolved requests. Approval
activates the same submitted credential. Success is `201` with a redacted
account request:

```json
{
  "data": {
    "id": "f1a52d86-332f-4f45-bec2-e8242d62eb59",
    "name": "Employee Name",
    "requestedId": "EMPLOYEE123",
    "role": "VIEWER",
    "submittedAt": "2026-09-15T08:15:00.000Z",
    "status": "PENDING",
    "decisionBy": null,
    "decisionAt": null,
    "version": 1
  },
  "meta": {"requestId": "0c71141d-f447-40b8-a8cc-fb78ad443499"}
}
```

Errors: `400/422` validation, `409 DUPLICATE_ID`, `429`, `500`. This public
endpoint has no `401/403/404` case. Duplicate messaging exposes no
credential or account-state details.

### 2.3 Account request decisions

`GET /account-requests` is SUPERADMIN-only, cursor-paginated, and returns the
redacted shape above. It returns `401`, `403`, `400` for an invalid cursor, or
`500`. It never returns passwords or password hashes. Approval:

```http
POST /account-requests/f1a52d86-332f-4f45-bec2-e8242d62eb59/approve
Authorization: Bearer <accessToken>
Content-Type: application/json
Idempotency-Key: de9d2937-16dc-42dc-8de9-60d79ce5db92
If-Match: "1"
```

```json
{}
```

Success `200` atomically changes that authoritative request to `ACCEPTED` and
creates an active user using the password submitted with that request; the
submitted password is never replaced with a default:

```json
{
  "data": {
    "accountRequest": {"id":"f1a52d86-332f-4f45-bec2-e8242d62eb59","name":"Employee Name","requestedId":"EMPLOYEE123","role":"VIEWER","submittedAt":"2026-09-15T08:15:00.000Z","status":"ACCEPTED","decisionBy":"9abcb00e-a9e2-49ae-a9ba-b10982dc664d","decisionAt":"2026-09-15T08:20:00.000Z","version":2},
    "user": {"id":"64fe8cff-3f9f-41dc-a494-b5e182ee5fdb","accountId":"EMPLOYEE123","username":"employee123","name":"Employee Name","role":"VIEWER","status":"ACTIVE","createdAt":"2026-09-15T08:20:00.000Z","updatedAt":"2026-09-15T08:20:00.000Z","version":1}
  },
  "meta": {"requestId":"c6b9a8e5-5a10-422a-a530-56b146ce14a6"}
}
```

Rejection uses `POST /account-requests/{accountRequestId}/reject` with the same
headers and either `{}` or `{"reason":"Duplicate employment request"}`.
Success `200` returns the redacted request with `status: "REJECTED"`, decision
fields, and incremented version. Reason is optional, trimmed, blank-to-null,
and at most 500 characters. Both transitions return `401`, `403`,
`404 NOT_FOUND`, `409 INVALID_TRANSITION` when no longer pending, `412`,
`422`, or `500` as applicable.

### 2.4 User list

```http
GET /users?limit=50&cursor=<opaque>
Authorization: Bearer <accessToken>
Accept: application/json
```

SUPERADMIN only. Each user has non-empty `id`, `accountId`, `username`, and
`name`; a string `role` (`VIEWER`, `ADMIN`, or `SUPERADMIN`);
`status: "ACTIVE"`; valid `createdAt`/`updatedAt`; and integer `version >= 1`.
The default collection returns active users only. Success is the standard
`200` collection. Invalid cursor returns `400`; missing/invalid
authentication returns `401`; VIEWER/ADMIN return `403`; server failure
returns `500`.

### 2.5 User administration (SUPERADMIN only)

`POST /users/admins` creates an ADMIN/SUPERADMIN directly (`201`).
`PATCH /users/{userId}` edits name/role (`200`, `If-Match` required).
`POST /users/{userId}/reset-password` accepts `{"newPassword":"..."}` (minimum
12 chars, `Idempotency-Key` + `If-Match` required), sets the new password,
and revokes that user's sessions. Success is `204 No Content` with an empty
body; `newPassword` is a request field and is never returned.

`DELETE /users/{userId}` performs account deactivation, not permanent
deletion:

```http
DELETE /users/64fe8cff-3f9f-41dc-a494-b5e182ee5fdb
Authorization: Bearer <accessToken>
Content-Type: application/json
Idempotency-Key: f657d27d-fad5-4382-913b-ea355c2ac5c4
If-Match: "3"
```

```json
{}
```

SUPERADMIN only. VIEWER and ADMIN receive `403`. The authoritative `userId`,
never username/name/index, identifies the account. Deactivation preserves
audit, transaction, and request attribution. The user can no longer
authenticate, active refresh tokens are revoked, and the account is excluded
from the default active `GET /users` list. Success `200` returns the
deactivated resource:

```json
{
  "data": {"id":"64fe8cff-3f9f-41dc-a494-b5e182ee5fdb","status":"INACTIVE","deactivatedAt":"2026-09-15T09:00:00.000Z","version":4},
  "meta": {"requestId":"1ed37bba-0a15-4f19-9efa-663b88dafee1"}
}
```

Errors: `401`, `403`, `404`, `409 SELF_MANAGEMENT_FORBIDDEN` for the caller's
own active account, `409 LAST_SUPERADMIN` when deactivation would leave no
active Superadmin, `412`, `422`, `500`. No response exposes credentials.

## 3. Inventory and Factories

### 3.1 Inventory

Routes are `GET /inventory`, `POST /inventory`, `GET /inventory/{materialId}`,
`PATCH /inventory/{materialId}`, and `POST /inventory/search-hits`.
Authenticated roles can list and read; ADMIN/SUPERADMIN create/edit.
Mutations use the authoritative material ID and fields `id`, `name`,
`quantity`, `biIssued`, `uom`, `section`, `incomingQuantity`,
`expectedAvailabilityDate`, and `purchaseOrderStatus`; update may add optional
`reason`. Response-only fields include `available`, `status`, search fields,
timestamps, and `version`. `available = quantity - biIssued`; quantities are
integers `>= 0` and `biIssued <= quantity`. Purchase order values are `NONE`,
`PENDING`, `ORDERED`. The frontend sends search hits as:

```json
{"materialIds":["T-6902","T-5836"],"searchedAt":"2026-09-15T09:10:00.000Z"}
```

The list accepts `q`, `status`, `section`, `sort`, `limit`, and `cursor`.
Standard success envelopes and `400/401/403/404/409/412/422/500` apply.
Search-hit success returns `updated` entries containing `materialId`,
`searchFrequency`, and nullable `lastSearchedAt`.

### 3.2 Factories

`GET /factories` lists authoritative `id`, `name`, `location`,
`materialCount`, timestamps, and version; the default list contains ACTIVE
factories only (`?status=ARCHIVED` includes archived history).
`GET /factories/{factoryId}` returns one factory without embedded materials.
Factory material routes are:

```text
GET   /factories/{factoryId}/materials
POST  /factories/{factoryId}/materials
GET   /factories/{factoryId}/materials/{materialId}
PATCH /factories/{factoryId}/materials/{materialId}
```

Authenticated roles read; ADMIN/SUPERADMIN mutate. Material fields are `id`,
`name`, `total`, `biIssued`, `incomingQuantity`,
`expectedAvailabilityDate`, and `purchaseOrderStatus`; update may include an
optional reason. Responses add `available`, `status`, timestamps, and version.
`available = total - biIssued`; factory stock never dual-writes Depot stock.
`POST /factories` sends `{"name":"Bengaluru Sleeper Plant","location":"Bengaluru"}`
and returns `201` with the Factory resource. Materials are created one
endpoint call at a time; this is not atomic.

### 3.3 Archive factory

```http
DELETE /factories/740d19ed-dbe1-40c0-82f1-cf258ac93f53
Authorization: Bearer <accessToken>
Content-Type: application/json
Idempotency-Key: 65f634bd-f2c6-42a9-8bec-801ce4e3565a
If-Match: "4"
```

```json
{}
```

SUPERADMIN only; ADMIN/VIEWER receive `403`. The path uses `factoryId`, never
the factory name. Archival is soft: inventory, processed request history,
transactions, and audit attribution remain queryable. Only `PENDING` requests
block archival (`409 FACTORY_HAS_ACTIVE_DEPENDENCIES`). Archived factories
reject new Sleeper requests and factory transactions (`409`) and are excluded
from default listings. Success `200`:

```json
{
  "data": {"id":"740d19ed-dbe1-40c0-82f1-cf258ac93f53","name":"Bengaluru Sleeper Plant","status":"ARCHIVED","archivedAt":"2026-09-15T09:30:00.000Z","version":5},
  "meta": {"requestId":"2559b81d-3b9b-446b-80e2-73704d62819b"}
}
```

Errors: `401`, `403`, `404`, `409`, `412`, `422`, `500`.

## 4. Material Requests

For every Request resource, `decisionBy` is the authoritative user UUID or
null. `history[].actor.id` is the same authoritative user UUID;
`history[].actor.accountId` is the business/display account ID; and
`history[].actor.role` is `VIEWER`, `ADMIN`, or `SUPERADMIN`.

### 4.1 Create request

```http
POST /requests
Authorization: Bearer <accessToken>
Accept: application/json
Content-Type: application/json
Idempotency-Key: bb5c8058-d759-4c4f-bac7-08c7ecc99037
```

```json
{"module":"DEPOT","factoryId":null,"itemId":"T-6902","quantity":10}
```

```json
{"module":"SLEEPER","factoryId":"740d19ed-dbe1-40c0-82f1-cf258ac93f53","itemId":"T-5836","quantity":10}
```

VIEWER only. Quantity is a positive integer up to `2147483647`; material must
belong to the selected ledger. Sleeper requires an active factory; Depot
requires null/absent factory. Creation does not reserve or alter stock. Initial
status is `PENDING`. The real frontend submits one `POST /requests` per material
line, sequentially, each with a distinct idempotency key and its own
authoritative request ID. This sequence is not atomic: successful lines remain
successful if another line fails, and the frontend reports successful item IDs
and per-item failure messages. Accepting/rejecting one ID never changes
sibling IDs. No atomic batch endpoint exists. Success `201` returns one request:

```json
{
  "data": {
    "id":"56c12c16-5ac2-4893-a3d0-d474c70c6b42","viewerId":"f6d90009-d951-4701-93f3-889d46747282","viewerAccountId":"VW-2048","viewerName":"Track Maintainer",
    "itemId":"T-5836","materialNumber":"T-5836","itemName":"Switch for trap - 52 kg","quantity":10,
    "module":"SLEEPER","section":"SLEEPER","factoryId":"740d19ed-dbe1-40c0-82f1-cf258ac93f53","factoryName":"Bengaluru Sleeper Plant",
    "status":"PENDING","decisionBy":null,"decisionAt":null,"history":[],"relatedTransactionId":null,
    "createdAt":"2026-09-15T10:00:00.000Z","updatedAt":"2026-09-15T10:00:00.000Z","version":1
  },
  "meta":{"requestId":"c344631e-eeaf-4250-894d72625bb41516"}
}
```

`section` mirrors `module` for compatibility. Errors: `400/422`, `401`,
`403`, `404` material/factory, `409` duplicate/business conflict, `500`.

### 4.2 List, filtering, and ordering

```http
GET /requests?module=SLEEPER&factoryId=740d19ed-dbe1-40c0-82f1-cf258ac93f53&status=PENDING&sort=createdAt,desc&limit=50
Authorization: Bearer <accessToken>
```

Supported query parameters are `module`, `factoryId`, `status`, `viewerId`,
`itemId`, `dateFrom`, `dateTo`, `sort`, `limit`, and `cursor`. `status` values
are `PENDING`, `ACCEPTED`, and `REJECTED`. Omit status to include pending and
processed history. The backend enforces visibility:

- VIEWER receives only their own records regardless of supplied `viewerId`.
- ADMIN/SUPERADMIN receive only authorized module/factory records.
- `factoryId` is valid only with `module=SLEEPER`.
- Results are newest first by `(createdAt, id)` by default.

Success `200` is the standard collection of request resources. Errors:
`400/422` invalid filters, `401`, `403`, `500`.

### 4.3 Pending counts

```http
GET /requests/pending-counts
Authorization: Bearer <accessToken>
```

Returns `PENDING` request counts under the caller's visibility (Viewers see
only their own; optional `module`/`factoryId` narrow further). Counts update
on create, accept, reject, and undo. `byModule` is a sparse map: an omitted
`DEPOT` entry means zero Depot requests, an omitted `SLEEPER` entry means
zero Sleeper requests, and an empty `byModule` map is valid when the total
is zero. `byFactory` maps factory IDs to counts and may be empty.

```json
{
  "data": {"total":3,"byModule":{"DEPOT":2,"SLEEPER":1},"byFactory":{"740d19ed-dbe1-40c0-82f1-cf258ac93f53":1}},
  "meta": {"requestId":"c344631e-eeaf-4250-894d72625bb41516"}
}
```

Requires authentication (`401` otherwise).

### 4.4 Accept

```http
POST /requests/56c12c16-5ac2-4893-a3d0-d474c70c6b42/accept
Authorization: Bearer <accessToken>
Content-Type: application/json
Idempotency-Key: 7ae0785f-5dd2-4ff6-9bf9-c98324129639
If-Match: "1"
```

```json
{}
```

ADMIN/SUPERADMIN only and only within their authorized module/factory scope.
Under one database transaction, the backend verifies `PENDING`, locks the
selected ledger material, validates sufficient stock, updates the request
and stock, and appends history/audit. Stock rules are exactly:

```text
Create Pending:
Total unchanged
BI Issued unchanged
Available unchanged
Accept:
Total unchanged
BI Issued += requested quantity
Available = Total - BI Issued
Reject:
No stock change
Undo Accepted:
Total unchanged
BI Issued -= previously accepted quantity
Available = Total - BI Issued
Undo Rejected:
No stock change
```

Success `200` returns the updated request directly in `data`, including
`decisionAt` and the matching history entry. The frontend reloads
authoritative stock through `GET /inventory` and `GET /factories`. Errors:
`401`, `403`, `404`, `409 INVALID_TRANSITION` if no longer pending,
`409 INSUFFICIENT_STOCK`, `412`, `422`, `500`. No partial stock/request write
is permitted and replay cannot issue twice.

### 4.5 Reject

Uses the same authorization, content, idempotency, and `If-Match` headers as
Accept, with path `POST /requests/{requestId}/reject`:

```json
{"reason":"Material is not currently required"}
```

Reason is optional, trimmed, maximum 500 characters, and blank becomes absent
or null. For example `{"reason":"Material is not currently required"}`.
Reject sets `REJECTED`, makes no stock change, returns the updated
request with `decisionAt` and the history entry carrying the reason, and may
also return a top-level `rejectionReason` migration field. Errors: `401`,
`403`, `404`, `409 INVALID_TRANSITION`, `412`, `422`, `500`.

### 4.6 Undo

```http
POST /requests/56c12c16-5ac2-4893-a3d0-d474c70c6b42/undo
Authorization: Bearer <accessToken>
Content-Type: application/json
Idempotency-Key: 3f186267-66bc-4dd5-8828-594702031d14
If-Match: "2"
```

```json
{"reason":"Decision entered against the wrong request"}
```

SUPERADMIN only; ADMIN/VIEWER receive `403`. A Pending request cannot be undone.
The backend performs Undo atomically in one database transaction: it locks the
authoritative request and affected inventory ledger, validates the prior
decision and exact reversal, applies any stock change, returns the request to
`PENDING`, clears current decision fields, appends History and audit records,
increments the version, and commits all effects together. Undo Accepted
restores issued stock; Undo Rejected makes no stock change and clears the
current rejection reason while preserving history. Success `200` returns the
complete updated request directly in `data`. Errors: `401`, `403`, `404`,
`409 INVALID_TRANSITION`, `409 CONSISTENCY_CONFLICT`, `412`, `422`, `500`.

## 5. Transactions and Attachments

### 5.1 Create and correct transactions

Routes are `GET /transactions`, `POST /transactions`,
`GET /transactions/{transactionId}`, SUPERADMIN-only
`PATCH /transactions/{transactionId}`, and SUPERADMIN-only
`POST /transactions/{transactionId}/reverse`.
ADMIN/SUPERADMIN can list and create. Lists support `scope`, `factoryId`,
`type`, `sort`, `limit`, and `cursor` and enforce authorized module/factory
visibility. Every create has 1..100 unique `items`; duplicate material IDs
are rejected. Each `quantityChange` is a positive integer `1..2147483647`.
`scope=FACTORY` requires `factoryId`; `scope=DEPOT` requires it absent/null.
Material IDs must belong to that ledger. Success returns a unique
authoritative transaction UUID. Create request headers:

```http
POST /transactions
Authorization: Bearer <accessToken>
Accept: application/json
Content-Type: application/json
Idempotency-Key: 985f66f7-7457-40eb-871c-6120961018f6
```

Canonical Incoming body:

```json
{
  "type":"INCOMING","scope":"DEPOT","items":[{"materialId":"T-6902","quantityChange":25}],
  "notes":"Delivery against scheduled supply","person":"North Zone Supplier","comingFrom":"Delhi","dateOfArrival":"2026-09-15","truckNumber":"KA01AB1234",
  "billFileId":"0ddbf6af-89db-49bf-a528-c8785622768d","proofFileIds":["467253ce-eb95-4347-b050-9f446f03f9dd"]
}
```

Canonical Dispatch body:

```json
{
  "type":"DISPATCH","scope":"FACTORY","factoryId":"740d19ed-dbe1-40c0-82f1-cf258ac93f53","items":[{"materialId":"T-5836","quantityChange":10}],
  "notes":"Dispatch to renewal site","person":"South Section Engineering Team","dateRequested":"2026-09-14","dateLeaving":"2026-09-15","truckNumber":"KA02CD5678",
  "billFileId":"53a7795e-c2ca-41fb-993f-c81f2308b2df","proofFileIds":["a914e8a2-58aa-44df-80a3-83d66c1a8978"]
}
```

Bill is mandatory for both transaction types. Proof is optional; omitting
`proofFileIds` preserves existing Proofs on correction and an explicit empty
list removes all Proof references. `person` and `truckNumber` are required.
Incoming additionally requires `comingFrom` and `dateOfArrival` and omits
dispatch dates. Dispatch requires `dateRequested` and `dateLeaving`, with
leaving not before requested, and omits incoming fields. Notes are optional,
trimmed, maximum 2000 characters.

Stock effects are atomic:

| Type | Scope | Effect |
| --- | --- | --- |
| INCOMING | DEPOT | `quantity += quantityChange` |
| DISPATCH | DEPOT | `biIssued += quantityChange` |
| INCOMING | FACTORY | `total += quantityChange` |
| DISPATCH | FACTORY | `total` unchanged, `biIssued += quantityChange` (provisional issue ledger pending product confirmation) |

Success `201` returns the complete transaction. Every item has required
`materialId` and `quantityChange`, server-authored `materialNameSnapshot`,
and optional `materialNumberSnapshot`. The response also contains logistics
fields, Bill/Proof metadata, `createdBy`, timestamps, and version.
Transaction creation errors are `400/422`, `401`, `403`, `404`,
`409 INSUFFICIENT_STOCK`, `409 FILE_IN_USE`, `409 IDEMPOTENCY_CONFLICT`,
`409 REQUEST_ALREADY_FULFILLED`, `409 SOURCE_REQUEST_ITEMS_MISMATCH`, and
`500`. Correction reason is optional, trimmed, and at most 500 characters.
Correction contract:

```http
PATCH /transactions/71fa206b-bf16-469a-bf4f-5386851dd66e
Authorization: Bearer <accessToken>
Content-Type: application/json
Idempotency-Key: ef357f76-f292-4e91-8312-7da5f8a70ae9
If-Match: "1"
```

```json
{"items":[{"materialId":"T-6902","quantityChange":30}],"notes":"Corrected after bill review","person":"North Zone Supplier","truckNumber":"KA01AB1234","billFileId":"0ddbf6af-89db-49bf-a528-c8785622768d","proofFileIds":[],"comingFrom":"Delhi","dateOfArrival":"2026-09-15","reason":"Bill confirms 30 pieces"}
```

SUPERADMIN only. `type`, `scope`, `factoryId`, original actor, and creation time
remain immutable. The backend atomically reverses the old effective stock
change, validates and applies the corrected change, advances version, and
appends `TRANSACTION_CORRECTED`. Success `200` returns the complete updated
Transaction directly in `data` with `correctedAt`. Errors: `400/422`, `401`,
`403`, `404`, `409 INSUFFICIENT_STOCK`, `409 CONSISTENCY_CONFLICT`,
`409 FILE_IN_USE`, `412`, `500`.

Reversal (`POST /transactions/{transactionId}/reverse`, SUPERADMIN only,
`Idempotency-Key` + `If-Match` required) atomically reverses the
transaction's effective stock change, stamps `reversedAt`, and frees linked
requests for future links. A second reversal returns
`409 INVALID_TRANSITION`. Success `200` returns the updated transaction.

### 5.2 Upload

```http
POST /files
Authorization: Bearer <accessToken>
Idempotency-Key: 07bc8f67-1987-4ba7-b25f-abba590ef0cc
Content-Type: multipart/form-data; boundary=...
```

Multipart fields are exactly `purpose` (`BILL` or `PROOF`) and binary `file`.
ADMIN/SUPERADMIN only. Allowed input types are `application/pdf`, `image/jpeg`,
`image/png`, and `image/webp`; maximum size is 10 MiB (`10 * 1024 * 1024`
bytes). The backend validates declared MIME, extension, and binary
signature/content and does not trust extension alone. Bills are no longer PDF-only and Proofs are no longer image-only. Filenames are sanitized
for metadata/display and never used as storage paths. Both `BILL` and `PROOF`
accept all four content types after server-side byte inspection. Original
bytes are preserved and response metadata always describes the actual stored
bytes. Success `201`:

```json
{
  "data": {"id":"0ddbf6af-89db-49bf-a528-c8785622768d","purpose":"BILL","fileName":"supplier-bill.pdf","contentType":"application/pdf","sizeBytes":482193,"sha256":"7e885a...","status":"READY","createdAt":"2026-09-15T11:00:00.000Z","referenced":false,"version":1},
  "meta":{"requestId":"49e9280a-60fc-45ec-b708-090ed25d4f90"}
}
```

The response requires at least `id`. Errors: `400/422` invalid purpose or
filename, `401`, `403`, `413 FILE_TOO_LARGE`, `415 UNSUPPORTED_MEDIA_TYPE`,
`409 IDEMPOTENCY_CONFLICT`, `422 MALWARE_DETECTED` when scanning finds
malware, `503 SERVICE_UNAVAILABLE` (`retryable: true`) when scanning or
storage is temporarily unavailable, `500`. Neither failure creates a usable
file record and staged bytes are deleted.

Duplicate-content handling: same-key replay returns the original response and
file ID. A different key with identical bytes, the same purpose, and the same
uploader returns the existing accessible record (`200`) so a resubmitted form
is never permanently blocked. Same bytes with a different purpose returns
`422` (a `BILL` never silently becomes a `PROOF` or vice versa). Bytes matching
another user's file create an isolated new record; no foreign file ID or
metadata is disclosed. Attachment rule: `billFileId` and every `proofFileIds`
entry must name a file uploaded by the authenticated caller (`ADMIN` and
`SUPERADMIN` alike); foreign IDs fail exactly like missing files (`404`)
without revealing existence.

### 5.3 Bill and Proof references

Backend transaction validation rejects submission unless `billFileId` names an
accessible, successfully uploaded `READY` BILL. Bill remains logically and
visually separate from Proof. Canonical multiple Proof persistence uses
`proofFileIds` (zero to 10 unique IDs, order preserved, duplicates rejected);
every file must be an authorized `READY` PROOF, and responses return ordered
`proofFiles` metadata. The legacy singular `proofFileId` input remains
accepted during migration: if both forms are present and the plural list is
non-empty, the singular ID must equal its first element; if the plural list
is empty, singular must be null/absent. Omission on PATCH preserves Proofs;
`proofFileIds: []` removes all Proof references. Proof is optional in the
finalized contract. Successful create/correction returns `proofFileIds` plus
ordered metadata:

```json
{"proofFileIds":["467253ce-eb95-4347-b050-9f446f03f9dd","9d84140a-a8ca-46f7-bf20-d9a351df1b4c"],"proofFiles":[{"id":"467253ce-eb95-4347-b050-9f446f03f9dd","purpose":"PROOF","fileName":"delivery-front.webp","contentType":"image/webp","sizeBytes":318200},{"id":"9d84140a-a8ca-46f7-bf20-d9a351df1b4c","purpose":"PROOF","fileName":"delivery-rear.jpg","contentType":"image/jpeg","sizeBytes":287110}]}
```

Endpoint-specific errors are `401`, `403`, `404` for an unknown/concealed file,
`409 FILE_IN_USE`, `412` for PATCH, `422` for more than 10, duplicate IDs,
mixed singular/plural mismatch, wrong purpose, or inaccessible/not-ready files,
and `500`.

### 5.4 Authenticated file retrieval

```http
GET /files/0ddbf6af-89db-49bf-a528-c8785622768d/content
Authorization: Bearer <accessToken>
Accept: */*
```

The opaque file ID, not a filename or URL token, identifies content. Only
`READY` files are retrievable. Responses return binary bytes with correct
`Content-Type`, safe `Content-Disposition`, `Content-Length`,
`Cache-Control: private, no-store`, and `X-Content-Type-Options: nosniff`.
Byte-range requests return `206` with `Content-Range`. Access tokens never
appear in URLs or query strings. ADMIN/SUPERADMIN can retrieve authorized
Bills and Proofs. A VIEWER may retrieve an authorized Bill linked to their
own accepted request/history but never receives Proof metadata or bytes.
Success is `200` bytes. Errors: `401`, `403`, `404` (including missing
stored bytes), `503` when storage is temporarily unavailable, and `500`.

`GET /files` lists file metadata (ADMIN/SUPERADMIN, cursor-paginated,
deleted files excluded). `GET /files/{fileId}` returns one file's metadata
with the same visibility rules (`404` for deleted or concealed files).
`DELETE /files/{fileId}` (`Idempotency-Key` + `If-Match` required) removes
the stored object and marks the row deleted (`204`); referenced files return
`409 FILE_IN_USE`; deleted files are absent from list/get/download/attach/
duplicate-reuse (all `404`). Re-uploading identical content repairs the
record in place and returns a usable file.

### 5.5 Request/transaction linkage

Request responses expose nullable `relatedTransactionId`. The write-side
relationship is optional `sourceRequestIds` on `POST /transactions`:

```json
{"sourceRequestIds":["56c12c16-5ac2-4893-a3d0-d474c70c6b42"]}
```

Each unique authoritative request must belong to the transaction actor's
authorized module/factory, have compatible material/quantity fulfillment, and
not already be linked. An invalid link returns `404` when concealed or
`409 REQUEST_ALREADY_FULFILLED`; transaction, stock, and links roll back
together. Incompatible material/quantity returns a structured business error
without exposing internal identifiers:

```json
{
  "code": "SOURCE_REQUEST_ITEMS_MISMATCH",
  "message": "The selected viewer request does not match the dispatched material and quantity.",
  "details": [
    {
      "field": "sourceRequestIds",
      "code": "MATERIAL_OR_QUANTITY_MISMATCH",
      "message": "Dispatch the same material and required quantity, or deselect this request."
    }
  ]
}
```

Aggregate fulfilment policy (exact match): linked requests are grouped by
material and each group's summed accepted quantity must equal the dispatched
line quantity (`sum == quantityChange`). A group above or below the line is
rejected with the error above. Every linked request must additionally exist,
be `ACCEPTED`, match the transaction scope/module (Sleeper requests must name
the identical `factoryId`), reference a Dispatch item material, and not
already back another live transaction (`409 REQUEST_ALREADY_FULFILLED`).
Reversing a transaction frees its requests for future links.

Idempotency keys are UUIDs; missing or malformed keys return `428`.
List cursors are opaque composite `(timestamp, id)` tokens; cursors combined
with a custom sort return `400`. No filename, timestamp, material-name, or
local-state matching is allowed. Cardinality is many requests to one
transaction, while each request links to at most one fulfilling transaction
in v1. The Flutter transaction DTO serializes `sourceRequestIds` when
authoritative accepted request IDs are supplied.
`sourceRequestIds` accepts zero to 100 unique request UUIDs. Success is the
normal `201` Transaction response and each source Request subsequently returns
that transaction's ID as `relatedTransactionId`. Errors are `401`, `403`,
`404`, `409 REQUEST_ALREADY_FULFILLED`, `409` scope/material/quantity
conflict, `422` duplicate/too-many/malformed IDs, and `500`.
Viewer History receives Bill metadata only when the request belongs to the
authenticated Viewer, `relatedTransactionId` resolves to a transaction, and
the Bill is authorized. Proof metadata remains omitted. Canonical attachment
metadata uses `id`; during migration the request projection may also return
the same value as `billAttachment.fileId`, which clients accept while
preferring canonical `id`.

## 6. Audit Contract

`GET /logs` is ADMIN/SUPERADMIN only and uses cursor pagination. Filters
include `eventType`, `entityType`, `entityId`, `actorId`, `module`,
`factoryId`, date range, `sort`, `limit`, and `cursor`. Authorization is
enforced per event; VIEWER receives `403`.

```http
GET /logs?module=SLEEPER&factoryId=740d19ed-dbe1-40c0-82f1-cf258ac93f53&sort=occurredAt,desc&limit=50
Authorization: Bearer <accessToken>
Accept: application/json
```

Every event contains:

```json
{
  "id":"255bb70b-1159-4d80-8314-6d65f4dff475",
  "eventType":"REQUEST_UNDONE","entityType":"REQUEST","entityId":"56c12c16-5ac2-4893-a3d0-d474c70c6b42",
  "actor":{"id":"0b76e762-493f-4013-b272-e04651b58944","accountId":"SA-2051","name":"Warehouse Superadmin","role":"SUPERADMIN"},
  "module":"SLEEPER","factoryId":"740d19ed-dbe1-40c0-82f1-cf258ac93f53",
  "occurredAt":"2026-09-15T10:30:00.000Z",
  "requestId":"9568648d-01d5-4faa-9cba-f9ae93a79e12",
  "reason":"Decision entered against the wrong request",
  "before":{"status":"ACCEPTED","scope":"FACTORY","factoryId":"740d19ed-dbe1-40c0-82f1-cf258ac93f53","factoryNameSnapshot":"Bengaluru Sleeper Plant"},
  "after":{"status":"PENDING","scope":"FACTORY","factoryId":"740d19ed-dbe1-40c0-82f1-cf258ac93f53","factoryNameSnapshot":"Bengaluru Sleeper Plant"}
}
```

Immutable events cover account approval/rejection/deactivation, factory
creation/archive, request creation, acceptance/rejection/undo, Incoming and
Dispatch transactions, uploads, deletions, and permission changes. Audit
insertion shares the business transaction so failure cannot leave an
unaudited mutation. Ordinary operations cannot update/delete audit records.
Passwords, hashes, tokens, authorization headers, file bytes, storage paths,
base64 payloads, and stack traces never appear. Success is `200` collection.
Errors: `400/422`, `401`, `403`, `500`. `GET /logs/{logId}` returns one
event; `GET /log/{api_path}` exposes the bounded operational log.
`GET /material-serial-mappings` returns serial mappings. `POST /ocr`
returns `501 FEATURE_NOT_IMPLEMENTED`.

## 7. Operational Endpoints and Future Capabilities

`GET /health` is the lightweight liveness signal (process alive, database
reachable). `GET /ready` is the readiness signal: `200` only when the
database, current migration revision, object storage, rate limiting store
(when configured), and file scanner (when configured) are all reachable,
otherwise `503`. Deployment instructions live in `README.md`; this contract
covers only the frontend/backend integration surface.

Not part of the current frontend workflow: true atomic multi-item batch
requests (one idempotent call per line remains the contract), real-time
notifications/WebSockets, and OCR (the route returns `501`).

## 8. Endpoint Permission Summary

| Endpoint | VIEWER | ADMIN | SUPERADMIN |
| --- | --- | --- | --- |
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

## 9. Resolved Contract Decisions

1. Factory Dispatch accounting: `DISPATCH`/`FACTORY` keeps `total`
   unchanged and applies `biIssued += quantityChange` (provisional issue
   ledger pending product confirmation).
2. Identifier normalization: trim + case-insensitive compare; usernames
   stored lowercase; `accountId` preserves submitted uppercase.
3. Compatibility fields: response `section` mirrors `module`; singular
   `proofFileId` input remains accepted with `proofFileIds` canonical;
   request `itemId` and `billAttachment.fileId` aliases retained.
4. Retention: unreferenced uploads are swept after `ORPHAN_RETENTION_DAYS`
   (default 7); soft-deleted file rows stay for audit; archived users and
   factories stay readable; transactions and audits are immutable.
5. Uploaded images keep their original media type; response metadata always
   describes the actual stored bytes.
6. No atomic multi-line request endpoint exists; one non-atomic,
   idempotent request per material line remains the contract.

## 10. Compatibility Notes

- The current Flutter response parsers retain several legacy fields and defaults.
  Backend responses provide the complete required fields rather than
  relying on frontend defaults.
- Compatibility fields include request `itemId`, singular transaction
  `proofFileId`/`proofFile` for response rendering, and audit `id`, nested
  `actor`, and `occurredAt`. They cannot be replaced until a coordinated
  Flutter release.
- Access tokens appear only in login and refresh responses. Refresh tokens
  never appear in JSON responses. No response exposes plaintext passwords,
  password hashes, internal storage paths, raw stack traces, or unredacted audit
  payloads.
