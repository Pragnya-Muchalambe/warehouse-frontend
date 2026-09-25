# Railway Warehouse Flutter API Contract

**Contract status:** Final frontend/backend integration contract

**Base path:** `/api/v1`

**Wire format:** lowerCamelCase JSON; multipart only for file upload

This document specifies the final contract required by the Railway Warehouse
Flutter application. Requirements marked as backend changes remain mandatory
contract behavior even when deployment verification is pending.

### Backend handoff priorities

| Priority | Backend work |
| --- | --- |
| P0 | Authentication/account approval compatibility |
| P0 | Scoped Depot/Sleeper requests and independent decisions |
| P0 | Accept/Reject/Undo with correct stock transaction |
| P0 | Required Bill and authenticated file retrieval |
| P1 | Rejection-reason persistence |
| P1 | Multiple Proof persistence |
| P1 | Viewer Bill association |
| P1 | Account deactivation and factory archive |
| P1 | Immutable structured audit events |
| P2 | True atomic multi-item batch |
| P2 | Real-time notifications and byte-range PDF retrieval |

## 1. Status Labels

Every capability uses one of these labels:

- **EXISTING/SUPPORTED:** the route and relevant behavior are described by the
  backend reference and consumed by the frontend. This is not a deployment or
  integration-test claim.
- **FRONTEND-REQUIRED BACKEND CHANGE:** required by the finalized frontend but
  absent from, or incompatible with, the backend reference.
- **EXISTING ROUTE — CONTRACT CHANGE REQUIRED:** the route exists, but its DTO,
  authorization, or behavior must change for the finalized frontend contract.
- **OPTIONAL/FUTURE:** not required by the current frontend workflow.
- **FRONTEND-ONLY — NO API CHANGE:** presentation or navigation behavior that
  consumes API state but requires no endpoint.

## 2. Conventions

### 2.1 Base URL and transport

The Flutter build receives `WAREHOUSE_API_BASE_URL`. If it already ends in
`/api/v1`, the client uses it unchanged; otherwise the client appends
`/api/v1`. The development default is `http://localhost:8000`. Production must
use the deployed HTTPS origin. JSON requests send `Accept: application/json`;
JSON bodies send `Content-Type: application/json`.

### 2.2 Authentication and authorization

Protected requests use:

```http
Authorization: Bearer <accessToken>
```

Access tokens remain in memory. Refresh tokens are transported only in Secure,
HttpOnly, SameSite cookies and must never appear in a JSON request or response,
client-readable storage, URL, or application log. Authentication endpoints use
the cookie directly; `X-Client-Type` is not required and must not select or alter
refresh-token transport. The backend must enforce authorization and data scope;
frontend visibility is not a security boundary.
Wire roles are exactly `VIEWER`, `ADMIN`, and `SUPERADMIN`. Wire module names
are exactly `DEPOT` and `SLEEPER`. Existing transaction scope values remain
`DEPOT` and `FACTORY`; `SLEEPER` UI/module operations map to `FACTORY` plus an
authoritative `factoryId`. `BOTH` is inventory catalog membership only.

### 2.3 IDs, dates, normalization, and factory scope

- Server-generated identifiers are opaque lowercase UUIDv4 strings. Material
  IDs are authoritative domain strings and case-insensitively unique.
- Every mutation uses authoritative IDs. Names, list indexes, timestamps,
  material names, filenames, and display labels are never identities.
- Timestamps are server-authored ISO-8601/RFC3339 UTC strings ending in `Z`.
  Operational date-only values use `YYYY-MM-DD`.
- The backend trims surrounding whitespace from identifiers and display text.
  User/account login identifiers are compared case-insensitively; the exact
  backend normalization/case-folding algorithm remains unresolved. The stored
  canonical display value is preserved. The current registration UI submits
  `requestedId` trimmed and uppercased.
- Request scope migration is defined once in section 5.2. Transaction scope
  continues to use `DEPOT` or `FACTORY` as defined in section 6.1.

### 2.4 Pagination, filtering, and sorting

Collections use cursor pagination:

```text
limit=1..100                 default 50; frontend currently requests 100
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

There is no total count. When `hasMore` is true, `nextCursor` must be non-null,
opaque, and non-repeating. Canonical newest-first sorting is
`sort=createdAt,desc` for requests and transactions and
`sort=occurredAt,desc` for audits. The current frontend's `sort=-createdAt` and
`sort=-occurredAt` forms are temporary legacy aliases accepted during migration.

### 2.5 Envelopes and HTTP behavior

Successful `200`/`201` JSON single-resource responses use:

```json
{
  "data": {},
  "meta": {"requestId": "70f772bf-87fd-43b9-a70a-f78e62ed9c6d"}
}
```

Binary file-content responses do not use a JSON envelope. `204 No Content` is
used only where explicitly documented. Resource creation
returns `201`; reads and state transitions return `200`; deletion may return
`200` with an archived resource or `204` as stated by that endpoint.
Errors use:

```json
{
  "error": {
    "code": "VALIDATION_ERROR",
    "message": "The request could not be validated.",
    "details": [
      {"field": "quantity", "code": "POSITIVE_INTEGER", "message": "Quantity must be a positive integer."}
    ],
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
| `409` | Conflict/already processed: `CONFLICT`, `DUPLICATE_ID`, `INVALID_TRANSITION`, `INSUFFICIENT_STOCK`, `IDEMPOTENCY_CONFLICT`, `FILE_IN_USE`, `CONSISTENCY_CONFLICT` |
| `412` | Stale `If-Match`: `VERSION_CONFLICT` |
| `413` | File too large: `FILE_TOO_LARGE` |
| `415` | Unsupported or invalid content: `UNSUPPORTED_MEDIA_TYPE` |
| `422` | Business/semantic validation: `VALIDATION_ERROR` |
| `428` | Required `If-Match` missing: `PRECONDITION_REQUIRED` |
| `429` | Rate limited: `RATE_LIMITED`, with integer-seconds `Retry-After` |
| `500` | Server failure: `INTERNAL_ERROR`; no stack trace |
| `503` | Temporary dependency failure: `SERVICE_UNAVAILABLE`, normally retryable |

Unknown fields are rejected with `422 VALIDATION_ERROR`. `400` is reserved for
malformed syntax/cursors; domain rules use `422` or `409` as shown above.

### 2.6 Idempotency and optimistic locking

Every business mutation, including `DELETE`, requires a UUID
`Idempotency-Key`, except login, refresh, and logout. Each independently-created
request line and each uploaded file receives its own key. The same key and same
request returns the original result without repeating side effects and may set
`Idempotency-Replayed: true`; a different request returns
`409 IDEMPOTENCY_CONFLICT`. A network retry reuses the key.
Mutable resources expose integer `version` and `ETag: "<version>"`. `PATCH`,
delete, and state transitions require `If-Match: "<version>"`. A stale version
returns `412 VERSION_CONFLICT`; the client reloads rather than silently merging.
The current Flutter API client already sends `Idempotency-Key` for implemented
business mutations and sends `If-Match` whenever a service supplies a resource
version. Making either header mandatory on a new or changed route requires a
coordinated frontend/backend rollout only if that route is not already invoked
through this existing version-aware client path.

| Endpoint | Current Flutter sends `Idempotency-Key` | Current Flutter sends `If-Match` | Backend requirement |
| --- | --- | --- | --- |
| Account approval/rejection | Yes | Yes | Require both |
| Account deactivation | Yes | Yes | Require both |
| Factory archive | Yes, in the currently disabled real-service method | Yes, in the currently disabled real-service method | Require both when the feature is enabled |
| Request creation | Yes | No | Require idempotency; no version exists at creation |
| Request Accept | Yes | Yes | Require both |
| Request Reject | Yes | Yes | Require both |
| Request Undo | Yes | Yes | Require both |
| Transaction creation | Yes | No | Require idempotency; no `If-Match` |
| Transaction correction | Yes | Yes | Require both |
| File upload | Yes | No | Require idempotency; no `If-Match` |

For any future route that lacks required frontend header support, use a
**COORDINATED FRONTEND/BACKEND CHANGE** in this order: release frontend header
support; let the backend accept and observe the header; enforce it only after
compatible frontend deployment.

### 2.7 Endpoint failure examples

Every changed/proposed JSON endpoint below uses the standard envelope. Its
listed statuses have these concrete representations; binary and `204` responses
are the explicit exceptions.

```json
{"error":{"code":"BAD_REQUEST","message":"The request is malformed.","details":[{"field":"quantity","code":"INVALID_VALUE","message":"Quantity is invalid."}],"retryable":false},"meta":{"requestId":"42f4f470-a877-4a62-80f5-c566c87317a6"}}
```

```json
{"error":{"code":"UNAUTHORIZED","message":"Authentication is required.","details":[],"retryable":false},"meta":{"requestId":"c02978db-6a8e-4ab0-884c-4a6277ad5718"}}
```

```json
{"error":{"code":"FORBIDDEN","message":"This account is not permitted to perform the operation.","details":[],"retryable":false},"meta":{"requestId":"a2e04a14-a6f5-478c-a6d3-14f51b9e2fe3"}}
```

```json
{"error":{"code":"NOT_FOUND","message":"The requested resource was not found.","details":[],"retryable":false},"meta":{"requestId":"f1073f2e-2b5c-431d-814a-d01e84436f47"}}
```

```json
{"error":{"code":"INVALID_TRANSITION","message":"The resource is no longer in a valid state for this operation.","details":[],"retryable":false},"meta":{"requestId":"93ac23da-11bd-41d3-8ccd-68ae2e026c31"}}
```

```json
{"error":{"code":"VALIDATION_ERROR","message":"The request violates a business rule.","details":[{"field":"reason","code":"MAX_LENGTH","message":"Reason must not exceed 500 characters."}],"retryable":false},"meta":{"requestId":"22cd718c-ce97-477a-87e4-b4c100d19553"}}
```

## 3. Authentication and Accounts

### 3.1 Session endpoints — EXISTING/SUPPORTED

| Method and path | Role | Request | Success |
| --- | --- | --- | --- |
| `POST /auth/login` | Public | `{"username":"employee123","password":"submitted password"}` | `200` token set and active user |
| `POST /auth/refresh` | Refresh-token cookie holder | Empty JSON object or no body; refresh cookie is sent automatically | `200` rotated refresh cookie, access token, and active user |
| `POST /auth/logout` | Authenticated | Empty JSON object or no body; refresh cookie is sent automatically | `204` and expired refresh cookie |
| `GET /auth/me` | Authenticated | No body | `200` active user |

Login and refresh return `accessToken`, `accessTokenExpiresAt`, `tokenType:
"Bearer"`, and `user` containing `id`,
`accountId`, `username`, `name`, `role`, `status: "ACTIVE"`, `createdAt`,
`updatedAt`, and integer `version`. Pending, rejected, archived, disabled, or
deleted accounts cannot authenticate. Invalid credentials return `401`;
inactive accounts return `403`; malformed fields return `422`; throttling may
return `429`. The backend sets and rotates the refresh token only with
`Set-Cookie`; the response JSON never contains a refresh token or its expiry.
No credential appears in logs or error details.

### 3.2 New account request — EXISTING ROUTE — CONTRACT CHANGE REQUIRED

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

The exact frontend fields are `name`, `requestedId`, `password`, and `role`.
The backend reference names the route but does not define this DTO; accepting
and returning these exact fields is therefore a required backend contract
change/clarification, not a claim about current implementation.
Only `VIEWER` or `ADMIN` may be requested. `confirmPassword` is
**FRONTEND-ONLY — NO API CHANGE** and must never be transmitted, persisted,
logged, audited, or returned. The backend must hash the submitted password with
a production password hash such as Argon2id immediately. The password and hash
must never appear in any response.
`requestedId` is trimmed and uniqueness is enforced case-insensitively against
active/inactive users and unresolved account requests. Approval activates the
same submitted credential. Success is `201` with a redacted account request:

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
endpoint has no `401/403/404` case. Public duplicate messaging must not expose
credential or account-state details.

### 3.3 Account request decisions — EXISTING ROUTE — CONTRACT CHANGE REQUIRED

`GET /account-requests` is SUPERADMIN-only, cursor-paginated, and returns the
redacted shape above. It returns `401`, `403`, `400` for an invalid cursor, or
`500`. It never returns passwords or password hashes.
Approval:

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
creates an active user using the password submitted with that request:

```json
{
  "data": {
    "accountRequest": {"id":"f1a52d86-332f-4f45-bec2-e8242d62eb59","name":"Employee Name","requestedId":"EMPLOYEE123","role":"VIEWER","submittedAt":"2026-09-15T08:15:00.000Z","status":"ACCEPTED","decisionBy":"9abcb00e-a9e2-49ae-a9ba-b10982dc664d","decisionAt":"2026-09-15T08:20:00.000Z","version":2},
    "user": {"id":"64fe8cff-3f9f-41dc-a494-b5e182ee5fdb","accountId":"EMPLOYEE123","username":"employee123","name":"Employee Name","role":"VIEWER","status":"ACTIVE","createdAt":"2026-09-15T08:20:00.000Z","updatedAt":"2026-09-15T08:20:00.000Z","version":1}
  },
  "meta": {"requestId":"c6b9a8e5-5a10-422a-a530-56b146ce14a6"}
}
```

The backend must not replace the submitted password with a default. A future
password-setup/reset flow must be explicitly contracted before changing this.
Rejection uses `POST /account-requests/{accountRequestId}/reject` with the same
headers and either `{}` or `{"reason":"Duplicate employment request"}`.
Success `200` returns the redacted request with `status: "REJECTED"`, decision
fields, and incremented version. Reason is optional, trimmed, blank-to-null,
and at most 500 characters.
**FRONTEND-REQUIRED BACKEND CHANGE:** the exact approval response
`data.accountRequest` plus `data.user`, and optional persisted rejection reason,
are required because the backend reference does not fully define them.
Both transitions return `401`, `403`, `404 NOT_FOUND`, `409 INVALID_TRANSITION`
when no longer pending, `412`, `422`, or `500` as applicable.

### 3.4 User list — EXISTING/SUPPORTED

```http
GET /users?limit=50&cursor=<opaque>
Authorization: Bearer <accessToken>
Accept: application/json
```

SUPERADMIN only. The current parser requires each returned user to have
non-empty `id`, `accountId`, `username`, and `name`; a string `role`;
`status: "ACTIVE"`; valid `createdAt`/`updatedAt`; and integer `version >= 1`.
The finalized backend contract restricts role to `VIEWER`, `ADMIN`, or
`SUPERADMIN`, even though this model parser does not itself enforce that enum.
Until inactive-user parsing is added, the default collection
must return active users only. Success is the standard `200` collection.
Invalid cursor returns `400`; missing/invalid authentication returns `401`;
VIEWER/ADMIN return `403`; server failure returns `500`.

### 3.5 Delete employee account — FRONTEND-REQUIRED BACKEND CHANGE

The backend reference has `GET /users` but no delete route. Despite its HTTP
method name, `DELETE /users/{userId}` performs account deactivation, not
permanent deletion. Required contract:

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
never username/name/index, identifies the account. The required behavior is
soft deletion/deactivation so audit, transaction, and request attribution
remain immutable. The user can no longer authenticate and is excluded from
the default active `GET /users` list.
Success `200` returns the deactivated resource. A legacy `204` response is
tolerated by the current frontend but is not the canonical contract:

```json
{
  "data": {"id":"64fe8cff-3f9f-41dc-a494-b5e182ee5fdb","status":"INACTIVE","deactivatedAt":"2026-09-15T09:00:00.000Z","version":4},
  "meta": {"requestId":"1ed37bba-0a15-4f19-9efa-663b88dafee1"}
}
```

Errors: `401`, `403`, `404`, `409 SELF_MANAGEMENT_FORBIDDEN` for the caller's
own active account, `409 LAST_SUPERADMIN` or another documented business
conflict, `412`, `422`, `500`. No response exposes credentials.

## 4. Inventory and Factories

### 4.1 Inventory — EXISTING/SUPPORTED

Existing routes are `GET /inventory`, `POST /inventory`,
`PATCH /inventory/{materialId}`, and `POST /inventory/search-hits`.
Authenticated roles can list. ADMIN/SUPERADMIN create/edit. Mutations use the
authoritative material ID and fields `id`, `name`, `quantity`, `biIssued`,
`uom`, `section`, `incomingQuantity`, `expectedAvailabilityDate`, and
`purchaseOrderStatus`; update may add optional `reason`. Response-only fields
include `available`, `status`, search fields, timestamps, and `version`.
`available = quantity - biIssued`; quantities are integer `0..2147483647` and
`biIssued <= quantity`. Purchase order values are `NONE`, `PENDING`, `ORDERED`.
The frontend sends search hits as:

```json
{"materialIds":["T-6902","T-5836"],"searchedAt":"2026-09-15T09:10:00.000Z"}
```

The list accepts `q`, `status`, `section`, `sort`, `limit`, and `cursor` where
implemented. Standard success envelopes and `400/401/403/404/409/412/422/500`
apply. Search-hit success returns `updated` entries containing `materialId`,
`searchFrequency`, and nullable `lastSearchedAt`.

### 4.2 Factory list and details — EXISTING/SUPPORTED

`GET /factories` lists authoritative `id`, `name`, `location`, `materialCount`,
timestamps, and version. `GET /factories/{factoryId}` is supported by the
backend reference but **OPTIONAL/FUTURE** for the frontend. Factory material
routes are:

```text
GET   /factories/{factoryId}/materials
POST  /factories/{factoryId}/materials
GET   /factories/{factoryId}/materials/{materialId}  OPTIONAL/FUTURE frontend use
PATCH /factories/{factoryId}/materials/{materialId}
```

Authenticated roles read; ADMIN/SUPERADMIN mutate. Material fields are `id`,
`name`, `total`, `biIssued`, `incomingQuantity`,
`expectedAvailabilityDate`, and `purchaseOrderStatus`; update may include an
optional reason. Responses add `available`, `status`, timestamps, and version.
`available = total - biIssued`; factory stock never dual-writes Depot stock.
`POST /factories` sends `{"name":"Bengaluru Sleeper Plant","location":"Bengaluru"}`
and returns `201` with the Factory resource. Materials are subsequently created
one endpoint call at a time; this is not atomic. A failure preserves prior
successful resources and is reported as partial completion.

### 4.3 Delete factory — FRONTEND-REQUIRED BACKEND CHANGE

The established resource convention makes the required route:

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
the factory name. Required semantics are factory archival, not destructive
erasure, unless the backend team explicitly approves permanent deletion.
Inventory, processed request history, transactions, and audit attribution must
remain queryable. Pending
requests or any dependency that cannot safely be archived returns
`409 FACTORY_HAS_ACTIVE_DEPENDENCIES` with machine-readable details.
Success `200`:

```json
{
  "data": {"id":"740d19ed-dbe1-40c0-82f1-cf258ac93f53","name":"Bengaluru Sleeper Plant","status":"ARCHIVED","archivedAt":"2026-09-15T09:30:00.000Z","version":5},
  "meta": {"requestId":"2559b81d-3b9b-446b-80e2-73704d62819b"}
}
```

The default factory list excludes archived factories after success. Errors:
`401`, `403`, `404`, `409`, `412`, `422`, `500`.

## 5. Material Requests

For every Request resource, `decisionBy` is the authoritative user UUID or
null. `history[].actor.id` is the same authoritative user UUID;
`history[].actor.accountId` is the business/display account ID; and
`history[].actor.role` is `VIEWER`, `ADMIN`, or `SUPERADMIN`.

### 5.1 Existing singular request routes — EXISTING/SUPPORTED

The backend reference currently defines:

```text
GET  /requests
POST /requests                         body: {"itemId":"T-6902","quantity":10}
GET  /requests/{requestId}
POST /requests/{requestId}/accept
POST /requests/{requestId}/reject
POST /requests/{requestId}/undo
```

This classification applies to the existence of the singular route paths.
Accept, Reject, and Undo require the contract changes documented in sections
5.4, 5.5, and 5.6 respectively.
The existing create body has no module/factory field and can safely represent
only Depot creation. The real frontend submits one `POST /requests` per material
line, sequentially. Each line has a distinct idempotency key and receives its
own authoritative request ID. This sequence is not atomic: successful lines
remain successful if another line fails, and the frontend reports successful
item IDs and per-item failure messages. Accepting/rejecting one ID must never
change sibling IDs.

### 5.2 Explicit Depot and Sleeper request scope — FRONTEND-REQUIRED BACKEND CHANGE

`POST /requests` must add these fields while retaining current `itemId` during
migration (`itemId` is the current frontend/backend field corresponding to the
conceptual material ID):

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
status is `PENDING`. The Flutter client serializes both fields for Depot and
Sleeper requests.
Success `201` returns one request:

```json
{
  "data": {
    "id":"56c12c16-5ac2-4893-a3d0-d474c70c6b42","viewerId":"f6d90009-d951-4701-93f3-889d46747282","viewerAccountId":"VW-2048","viewerName":"Track Maintainer",
    "itemId":"T-5836","materialNumber":"T-5836","itemName":"Switch for trap - 52 kg","quantity":10,
    "module":"SLEEPER","section":"SLEEPER","factoryId":"740d19ed-dbe1-40c0-82f1-cf258ac93f53","factoryName":"Bengaluru Sleeper Plant",
    "status":"PENDING","decisionBy":null,"decisionAt":null,"history":[],"relatedTransactionId":null,
    "createdAt":"2026-09-15T10:00:00.000Z","updatedAt":"2026-09-15T10:00:00.000Z","version":1
  },
  "meta":{"requestId":"c344631e-eeac-4250-894d-72625bb41516"}
}
```

The current parser consumes `section`, not `module`; it maps `DEPOT` to Depot
and any present non-Depot value to Sleeper. `section` is therefore retained as
a migration-compatible response field and must match `module` until Flutter
parses `module`. Errors: `400/422`, `401`, `403`, `404` material/factory, `409`
duplicate/business conflict, `500`.
A true atomic batch endpoint is **OPTIONAL/FUTURE**. If introduced, it should
accept 1..100 unique lines and return per-line results unless explicit
all-or-nothing transactionality is guaranteed. It must not be described as the
current sequential frontend behavior.

### 5.3 Request list, filtering, and ordering — FRONTEND-REQUIRED BACKEND CHANGE

```http
GET /requests?module=SLEEPER&factoryId=740d19ed-dbe1-40c0-82f1-cf258ac93f53&status=PENDING&sort=createdAt,desc&limit=50
Authorization: Bearer <accessToken>
```

Supported query concepts must be `module`, `factoryId`, `status`, `viewerId`,
`sort`, `limit`, and `cursor`. `status` values are `PENDING`, `ACCEPTED`, and
`REJECTED`. Omit status to include pending and processed History. The backend
enforces visibility:

- VIEWER receives only their own records regardless of supplied `viewerId`.
- ADMIN/SUPERADMIN receive only authorized module/factory records.
- `factoryId` is valid only with `module=SLEEPER`.
- Results are newest first when requested.

The current Flutter call supplies only `limit=100` and `cursor`; adding these
query parameters to frontend calls is a coordinated follow-up. Server-side
role/ownership filtering is required even when no filters are supplied.
Success `200` is the standard collection of request resources. Errors:
`400/422` invalid filters, `401`, `403`, `404` inaccessible factory, `500`.
Notification badges/red dots are **FRONTEND-ONLY — NO API CHANGE** and may be
computed from visible pending requests. No pending-count endpoint is required.

### 5.4 Accept — EXISTING ROUTE — CONTRACT CHANGE REQUIRED

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
Under one database transaction, verify `PENDING`, lock the selected ledger
material, validate sufficient stock, update the request and stock, and append
history/audit. Never clamp an inconsistent value.
Request stock rules are exactly:

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

For Depot inventory responses, the legacy field `quantity` represents total
stock. It does not mean that accepting a request replaces total stock.
Success `200` returns the updated request directly in `data`, because the
current `RequestService` parses `data` as a request. The frontend separately
reloads authoritative stock through `GET /inventory` and `GET /factories`,
including `GET /factories/{factoryId}/materials` for Sleeper requests:

```json
{"data":{"id":"56c12c16-5ac2-4893-a3d0-d474c70c6b42","viewerId":"f6d90009-d951-4701-93f3-889d46747282","viewerAccountId":"VW-2048","viewerName":"Track Maintainer","itemId":"T-5836","materialNumber":"T-5836","itemName":"Switch for trap - 52 kg","quantity":10,"module":"SLEEPER","section":"SLEEPER","factoryId":"740d19ed-dbe1-40c0-82f1-cf258ac93f53","factoryName":"Bengaluru Sleeper Plant","status":"ACCEPTED","decisionBy":"0b76e762-493f-4013-b272-e04651b58944","decisionAt":"2026-09-15T10:10:00.000Z","history":[{"status":"ACCEPTED","actor":{"id":"0b76e762-493f-4013-b272-e04651b58944","accountId":"SA-2051","name":"Warehouse Superadmin","role":"SUPERADMIN"},"at":"2026-09-15T10:10:00.000Z","reason":null}],"relatedTransactionId":null,"createdAt":"2026-09-15T10:00:00.000Z","updatedAt":"2026-09-15T10:10:00.000Z","version":2},"meta":{"requestId":"99fa5975-8883-4235-8e0b-9d4346be750a"}}
```

Errors: `401`, `403`, `404`, `409 INVALID_TRANSITION` if no longer pending,
`409 INSUFFICIENT_STOCK`, `412`, `422`, `500`. No partial stock/request write
is permitted and replay cannot issue twice.

### 5.5 Reject — EXISTING ROUTE — CONTRACT CHANGE REQUIRED

Uses the same authorization, content, idempotency, and `If-Match` headers as
Accept, with path `POST /requests/{requestId}/reject`:

```json
{"reason":"Material is not currently required"}
```

Reason is optional, trimmed, maximum 500 characters, and blank becomes absent
or null. It applies only to the authoritative selected request. Reject sets
`REJECTED`, makes no stock change, and returns the updated request. For current
frontend compatibility, the appended `history` entry contains the reason; a
top-level `rejectionReason` may additionally be returned as a migration field,
but the current UI reads History and must not depend solely on it. Pending and
Accepted current state must not show a stale active reason. Historical entries
remain append-only. Success example:

```json
{"data":{"id":"56c12c16-5ac2-4893-a3d0-d474c70c6b42","viewerId":"f6d90009-d951-4701-93f3-889d46747282","viewerName":"Track Maintainer","itemId":"T-5836","itemName":"Switch for trap - 52 kg","quantity":10,"module":"SLEEPER","section":"SLEEPER","factoryId":"740d19ed-dbe1-40c0-82f1-cf258ac93f53","status":"REJECTED","decisionBy":"0b76e762-493f-4013-b272-e04651b58944","decisionAt":"2026-09-15T10:10:00.000Z","rejectionReason":"Material is not currently required","history":[{"status":"REJECTED","actor":{"id":"0b76e762-493f-4013-b272-e04651b58944","accountId":"AD-2048","name":"Warehouse Admin","role":"ADMIN"},"at":"2026-09-15T10:10:00.000Z","reason":"Material is not currently required"}],"relatedTransactionId":null,"createdAt":"2026-09-15T10:00:00.000Z","updatedAt":"2026-09-15T10:10:00.000Z","version":2},"meta":{"requestId":"f833775e-8b5e-410e-879e-232fac684640"}}
```

Errors: `401`, `403`, `404`, `409 INVALID_TRANSITION`, `412`, `422`, `500`.

### 5.6 Undo — EXISTING ROUTE — CONTRACT CHANGE REQUIRED

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
The backend performs Undo atomically in one database transaction. It locks the
authoritative request and affected inventory ledger, validates the prior
decision and exact reversal, applies any stock change, returns the request to
`PENDING`, clears current decision fields, appends History and audit records,
increments the version, and commits all effects together. Any failure rolls back
all effects; partial stock, request, History, audit, or version writes are
forbidden.
Undo Accepted restores issued stock, returns current state to `PENDING`, clears
current `decisionBy`/`decisionAt`, and preserves append-only History. Undo
Rejected returns current state to `PENDING`, makes no stock change, makes the
current rejection reason null/inactive, preserves the historical rejection,
and appends a Pending/Undo history entry with the Superadmin actor and optional
undo reason. Never clamp an inconsistent balance.
Success `200` returns the complete updated request directly in `data`. The
frontend separately reloads `GET /inventory` and `GET /factories` followed by
`GET /factories/{factoryId}/materials` for authoritative stock.
Undo Accepted:

```json
{"data":{"id":"56c12c16-5ac2-4893-a3d0-d474c70c6b42","viewerId":"f6d90009-d951-4701-93f3-889d46747282","itemId":"T-5836","itemName":"Switch for trap - 52 kg","quantity":10,"module":"SLEEPER","section":"SLEEPER","factoryId":"740d19ed-dbe1-40c0-82f1-cf258ac93f53","status":"PENDING","decisionBy":null,"decisionAt":null,"rejectionReason":null,"history":[{"status":"ACCEPTED","actor":{"id":"0b76e762-493f-4013-b272-e04651b58944","accountId":"AD-2048","name":"Warehouse Admin","role":"ADMIN"},"at":"2026-09-15T10:10:00.000Z","reason":null},{"status":"PENDING","actor":{"id":"9abcb00e-a9e2-49ae-a9ba-b10982dc664d","accountId":"SA-2051","name":"Warehouse Superadmin","role":"SUPERADMIN"},"at":"2026-09-15T10:20:00.000Z","reason":"Decision entered against the wrong request"}],"relatedTransactionId":null,"createdAt":"2026-09-15T10:00:00.000Z","updatedAt":"2026-09-15T10:20:00.000Z","version":3},"meta":{"requestId":"9568648d-01d5-4faa-9cba-f9ae93a79e12"}}
```

Undo Rejected:

```json
{"data":{"id":"7417e77d-0f52-476e-b3c8-611df2019f13","viewerId":"f6d90009-d951-4701-93f3-889d46747282","itemId":"T-6902","itemName":"Improved SEJ","quantity":5,"module":"DEPOT","section":"DEPOT","factoryId":null,"status":"PENDING","decisionBy":null,"decisionAt":null,"rejectionReason":null,"history":[{"status":"REJECTED","actor":{"id":"0b76e762-493f-4013-b272-e04651b58944","accountId":"AD-2048","name":"Warehouse Admin","role":"ADMIN"},"at":"2026-09-15T10:10:00.000Z","reason":"Not currently required"},{"status":"PENDING","actor":{"id":"9abcb00e-a9e2-49ae-a9ba-b10982dc664d","accountId":"SA-2051","name":"Warehouse Superadmin","role":"SUPERADMIN"},"at":"2026-09-15T10:20:00.000Z","reason":"Request should be reconsidered"}],"relatedTransactionId":null,"createdAt":"2026-09-15T10:00:00.000Z","updatedAt":"2026-09-15T10:20:00.000Z","version":3},"meta":{"requestId":"f7cbf3bd-d9f8-4631-b972-ee41720ed0d0"}}
```

Errors: `401`, `403`, `404`, `409 INVALID_TRANSITION`,
`409 CONSISTENCY_CONFLICT`, `412`, `422`, `500`. The frontend confirmation
dialog is **FRONTEND-ONLY — NO API CHANGE** and is not a backend precondition.

## 6. Transactions and Attachments

### 6.1 Transaction routes — EXISTING ROUTES — CONTRACT CHANGES REQUIRED

Existing routes are `GET /transactions`, `POST /transactions`,
`GET /transactions/{transactionId}`, and SUPERADMIN-only
`PATCH /transactions/{transactionId}`. ADMIN/SUPERADMIN can list and create.
Lists support `scope`, `factoryId`, `type`, `sort`, `limit`, and `cursor` and
must enforce authorized module/factory visibility.
Every create has 1..100 unique `items`; duplicate material IDs are rejected.
Each `quantityChange` is a positive integer `1..2147483647`. `scope=FACTORY`
requires `factoryId`; `scope=DEPOT` requires it absent/null. Material IDs must
belong to that ledger. Success returns a unique authoritative transaction UUID;
production IDs must never use `fixture-*` or another test convention.
Create request headers:

```http
POST /transactions
Authorization: Bearer <accessToken>
Accept: application/json
Content-Type: application/json
Idempotency-Key: 985f66f7-7457-40eb-871c-6120961018f6
```

Proposed canonical Incoming body:

```json
{
  "type":"INCOMING","scope":"DEPOT","items":[{"materialId":"T-6902","quantityChange":25}],
  "notes":"Delivery against scheduled supply","person":"North Zone Supplier","comingFrom":"Delhi","dateOfArrival":"2026-09-15","truckNumber":"KA01AB1234",
  "billFileId":"0ddbf6af-89db-49bf-a528-c8785622768d","proofFileIds":["467253ce-eb95-4347-b050-9f446f03f9dd"]
}
```

Proposed canonical Dispatch body:

```json
{
  "type":"DISPATCH","scope":"FACTORY","factoryId":"740d19ed-dbe1-40c0-82f1-cf258ac93f53","items":[{"materialId":"T-5836","quantityChange":10}],
  "notes":"Dispatch to renewal site","person":"South Section Engineering Team","dateRequested":"2026-09-14","dateLeaving":"2026-09-15","truckNumber":"KA02CD5678",
  "billFileId":"53a7795e-c2ca-41fb-993f-c81f2308b2df","proofFileIds":["a914e8a2-58aa-44df-80a3-83d66c1a8978"]
}
```

Bill is mandatory for both transaction types. Proof is optional in the
finalized frontend. `person` and `truckNumber` are required. Incoming additionally
requires `comingFrom` and `dateOfArrival` and omits dispatch dates. Dispatch
requires `dateRequested` and `dateLeaving`, with leaving not before requested,
and omits incoming fields. Notes are optional, trimmed, maximum 2000.

#### BLOCKING DOMAIN DECISION — FACTORY DISPATCH ACCOUNTING

The sources disagree. `backend-developer-api.md` currently defines Factory
Dispatch as `total -= quantityChange`, followed by
`available = total - biIssued`. The local/mock transaction behavior instead
keeps `total` unchanged and applies `biIssued += quantityChange`, followed by
the same availability formula. No approved product requirement resolves this
conflict. The backend team must confirm one model before implementing Factory
Dispatch; neither local/mock behavior nor this proposal is evidence of approval.
The non-conflicting transaction stock effects are atomic:

| Type | Scope | Effect |
| --- | --- | --- |
| INCOMING | DEPOT | `quantity += quantityChange` |
| DISPATCH | DEPOT | `biIssued += quantityChange` |
| INCOMING | FACTORY | `total += quantityChange` |

Success `201` returns the complete transaction. Every item has required
`materialId` and `quantityChange`, server-authored `materialNameSnapshot`, and
optional `materialNumberSnapshot`. The response also contains logistics fields,
Bill/Proof metadata, `createdBy`, timestamps, and version.
Transaction creation errors are `400/422`, `401`, `403`, `404`,
`409 INSUFFICIENT_STOCK`, `409 FILE_IN_USE`, `409 IDEMPOTENCY_CONFLICT`, and
`500`. It does not return upload-only `413`/`415` and does not use `412`.
**FRONTEND-REQUIRED BACKEND CHANGE:** Proof must be optional. The backend
reference currently requires `proofFileId`, which conflicts with the finalized
frontend. On correction, omitting `proofFileIds` preserves existing Proofs and
an explicit empty list removes all Proofs; `proofFileIds: null` is invalid.
`billFileId` remains required and non-null for creation and correction.
Correction reason is optional, trimmed, and at most 500 characters.
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
Transaction reversal is **OPTIONAL/FUTURE**; the current frontend has no action.

### 6.2 Upload — EXISTING/SUPPORTED

```http
POST /files
Authorization: Bearer <accessToken>
Idempotency-Key: 07bc8f67-1987-4ba7-b25f-abba590ef0cc
Content-Type: multipart/form-data; boundary=...
```

Multipart fields are exactly `purpose` (`BILL` or `PROOF`) and binary `file`.
ADMIN/SUPERADMIN only. Allowed input types are `application/pdf`, `image/jpeg`,
`image/png`, and `image/webp`; maximum size is 10 MiB (`10 * 1024 * 1024`
bytes). Validate declared MIME, extension, and binary signature/content; do not
trust extension alone. Sanitize filenames for metadata/display and never use
them as storage paths. If images are converted after validation, response
metadata must describe the actual returned/stored bytes.
Success `201`:

```json
{
  "data": {"id":"0ddbf6af-89db-49bf-a528-c8785622768d","purpose":"BILL","fileName":"supplier-bill.pdf","contentType":"application/pdf","sizeBytes":482193,"sha256":"7e885a...","status":"READY","createdAt":"2026-09-15T11:00:00.000Z","referenced":false,"version":1},
  "meta":{"requestId":"49e9280a-60fc-45ec-b708-090ed25d4f90"}
}
```

The current frontend parser requires at least returned `id`; the complete
metadata above is the finalized contract. Errors: `400/422` invalid purpose or
filename, `401`, `403`, `413 FILE_TOO_LARGE`, `415 UNSUPPORTED_MEDIA_TYPE`,
`409 IDEMPOTENCY_CONFLICT`, `500`.

### 6.3 Bill and Proof references — EXISTING ROUTE — CONTRACT CHANGE REQUIRED

Backend transaction validation rejects submission unless `billFileId` names an
accessible, successfully uploaded `READY` BILL. Bill remains logically and
visually separate from Proof.
Current compatibility supports one persisted Proof through singular
`proofFileId` and `proofFile`. Flutter prefers canonical `proofFileIds` and
ordered `proofFiles`, using singular fields only when plural fields are absent.
Proof is optional in the finalized contract.
**FRONTEND-REQUIRED BACKEND CHANGE:** canonical multiple Proof persistence:
Affected endpoints are ADMIN/SUPERADMIN `POST /transactions` and
SUPERADMIN-only `PATCH /transactions/{transactionId}`. Both use the JSON,
Bearer, idempotency, and, for PATCH, `If-Match` headers shown in sections 6.1.
The plural field is part of the transaction body alongside required
`billFileId`:

```json
{"proofFileIds":["467253ce-eb95-4347-b050-9f446f03f9dd","9d84140a-a8ca-46f7-bf20-d9a351df1b4c"]}
```

Allow zero to 10 unique IDs, preserve order, reject duplicates, require every
file to be an authorized `READY` PROOF, and return ordered `proofFiles` metadata.
During migration, the backend may additionally accept legacy `proofFileId` and
return singular metadata for the first Proof. If both request forms are present
and the plural list is non-empty, the singular ID must equal its first element;
if the plural list is empty, singular must be null/absent. Omission on PATCH
preserves Proofs; `proofFileIds: []` removes all Proof references. Removing a
pre-submission selection does not delete an upload. Unreferenced-file cleanup is
an unresolved retention decision.
Successful create/correction returns `proofFileIds` plus ordered metadata:

```json
{"proofFileIds":["467253ce-eb95-4347-b050-9f446f03f9dd","9d84140a-a8ca-46f7-bf20-d9a351df1b4c"],"proofFiles":[{"id":"467253ce-eb95-4347-b050-9f446f03f9dd","purpose":"PROOF","fileName":"delivery-front.webp","contentType":"image/webp","sizeBytes":318200},{"id":"9d84140a-a8ca-46f7-bf20-d9a351df1b4c","purpose":"PROOF","fileName":"delivery-rear.jpg","contentType":"image/jpeg","sizeBytes":287110}]}
```

Endpoint-specific errors are `401`, `403`, `404` for an unknown/concealed file,
`409 FILE_IN_USE`, `412` for PATCH, `422` for more than 10, duplicate IDs,
mixed singular/plural mismatch, wrong purpose, or inaccessible/not-ready files,
and `500`.

### 6.4 Authenticated file retrieval — EXISTING ROUTE — CONTRACT CHANGE REQUIRED

```http
GET /files/0ddbf6af-89db-49bf-a528-c8785622768d/content
Authorization: Bearer <accessToken>
Accept: */*
```

The opaque file ID, not a filename or URL token, identifies content. Return
binary bytes with correct `Content-Type`, safe `Content-Disposition`, optional
`Content-Length`, and `Cache-Control: private, no-store` for protected content.
Never require access tokens in URLs or query strings. Byte-range support and
`206` are **OPTIONAL/FUTURE** for large PDFs.
ADMIN/SUPERADMIN can retrieve authorized Bills and Proofs. A VIEWER may retrieve
an authorized Bill linked to their own request/history but must not receive
Proof metadata or bytes unless a future policy explicitly permits it. This
Viewer Bill access is a **FRONTEND-REQUIRED BACKEND CHANGE** because the backend
reference currently denies VIEWER transaction-file access.
Success is `200` bytes. Errors: `401`, `403`, `404`, `415` only when stored
metadata/content is invalid, and `500`. PDF/image rendering is
**FRONTEND-ONLY — NO API CHANGE**.

### 6.5 Viewer Bill association — FRONTEND-REQUIRED BACKEND CHANGE

Request responses must expose nullable `relatedTransactionId`. The chosen
write-side relationship is optional `sourceRequestIds` on `POST /transactions`:

```json
{"sourceRequestIds":["56c12c16-5ac2-4893-a3d0-d474c70c6b42"]}
```

Each unique authoritative request must belong to the transaction actor's
authorized module/factory, have compatible material/quantity fulfillment, and
not already be linked. An invalid link returns `404` when concealed or
`409 REQUEST_ALREADY_FULFILLED`; transaction, stock, and links roll back
together. No filename, timestamp, material-name, or local-state matching is
allowed. Cardinality is many requests to one transaction, while each request
links to at most one fulfilling transaction in v1. The Flutter transaction DTO
serializes `sourceRequestIds` when authoritative accepted request IDs are
supplied.
`sourceRequestIds` accepts zero to 100 unique request UUIDs and is sent under
the ADMIN/SUPERADMIN `POST /transactions` headers in section 6.1. Success is the
normal `201` Transaction response and each source Request subsequently returns
that transaction's ID as `relatedTransactionId`. Errors are `401`, `403`, `404`,
`409 REQUEST_ALREADY_FULFILLED`, `409` scope/material/quantity conflict,
`422` duplicate/too-many/malformed IDs, and `500`.
Viewer History receives Bill metadata only when the request belongs to the
authenticated Viewer, `relatedTransactionId` resolves to a transaction, and
the Bill is authorized. Proof metadata remains omitted. Example request fields:

```json
{"id":"56c12c16-5ac2-4893-a3d0-d474c70c6b42","relatedTransactionId":"71fa206b-bf16-469a-bf4f-5386851dd66e","billAttachment":{"id":"0ddbf6af-89db-49bf-a528-c8785622768d","fileName":"supplier-bill.pdf","contentType":"application/pdf","sizeBytes":482193}}
```

Canonical attachment metadata uses `id`. During migration only, the request
projection may also return the same value as `billAttachment.fileId`; Flutter
accepts both while preferring canonical `id`.

## 7. Audit Contract

### 7.1 Audit list — EXISTING ROUTE — CONTRACT CHANGE REQUIRED

`GET /logs` is ADMIN/SUPERADMIN only and uses cursor pagination. Filters should
include `eventType`, `entityType`, `entityId`, `actorId`, `module`, `factoryId`,
date range, `sort`, `limit`, and `cursor`. Authorization is enforced per event;
VIEWER receives `403`.

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

The current parser consumes canonical `id`, `eventType`, `entityType`,
`entityId`, nested `actor`, `occurredAt`, `requestId`, `reason`, `before`,
`after`, `billFile`, and singular `proofFile`. Current scope rendering reads
`scope`, `factoryId`, and
`factoryNameSnapshot` from `before`/`after`; top-level module/factory fields are
useful filters but do not replace snapshots. Structured details must be concise
and redacted; raw JSON need not be displayed.
**FRONTEND-REQUIRED BACKEND CHANGE:** immutable events must cover account
approval/rejection/deactivation, factory creation/archive, request creation,
acceptance/rejection/undo, and Incoming/Dispatch transactions. Audit insertion
must share the business transaction so failure cannot leave an unaudited
mutation. Ordinary frontend operations cannot update/delete audit records.
Passwords, hashes, tokens, authorization headers, file bytes, storage paths,
base64 payloads, and stack traces are forbidden.
Success is `200` collection. Errors: `400/422`, `401`, `403`, `500`.

## 8. Optional/Future Backend Capabilities

These backend-reference routes are not required by current frontend workflows:

- `GET /health`
- `POST /users/admins` and `PATCH /users/{userId}`
- `GET /inventory/{materialId}`
- `GET/PATCH /factories/{factoryId}`
- Factory-material detail GET
- Request detail GET
- File list/metadata/delete and orphan-cleanup UI
- Transaction reversal
- Audit detail and custom request logs
- Material serial mappings
- Byte-range file retrieval
- Atomic request batches
- Real-time notifications/WebSockets
- OCR; the referenced route currently returns `501 FEATURE_NOT_IMPLEMENTED`

An existing route is not a frontend requirement merely because it appears in
the backend reference.

## 9. Frontend-Only — No API Change

The following remain frontend responsibilities and must not produce new
backend endpoints:

- Redirect to History after successful request submission
- Review Request screen and stable batch-row widget keys
- Confirmation dialogs and rejection-dialog layout
- Password visibility toggles and Confirm Password UI
- Footer/drawer notification badges and hamburger red dot
- Pending-card styling
- Image and PDF preview UI
- Actions-page layout and responsive design

These features consume authenticated API state where needed. Dialog presence
does not alter backend authorization, idempotency, or validation requirements.

## 10. Endpoint Permission Summary

| Endpoint | VIEWER | ADMIN | SUPERADMIN | Status |
| --- | --- | --- | --- | --- |
| Authentication | Public/current session | Public/current session | Public/current session | EXISTING/SUPPORTED |
| Account request creation/decisions | Public creation | Deny | Superadmin decisions | EXISTING ROUTE — CONTRACT CHANGE REQUIRED |
| `GET /users` | Deny | Deny | Allow | EXISTING/SUPPORTED |
| `DELETE /users/{userId}` | Deny | Deny | Allow | FRONTEND-REQUIRED BACKEND CHANGE |
| Inventory/factory reads | Allow | Allow | Allow | EXISTING/SUPPORTED |
| Inventory/factory/material writes | Deny | Allow | Allow | EXISTING/SUPPORTED |
| Factory archive/delete | Deny | Deny | Allow | FRONTEND-REQUIRED BACKEND CHANGE |
| Request create/list | Create and own-only list | Scoped list | Scoped list | EXISTING ROUTE — CONTRACT CHANGE REQUIRED |
| Request accept/reject | Deny | Allow in scope | Allow in scope | EXISTING ROUTE — CONTRACT CHANGE REQUIRED |
| Request undo | Deny | Deny | Allow in scope | EXISTING ROUTE — CONTRACT CHANGE REQUIRED |
| Transaction create/list | Deny | Allow in scope | Allow in scope | EXISTING ROUTE — CONTRACT CHANGE REQUIRED |
| File upload | Deny | Allow | Allow | EXISTING/SUPPORTED |
| File content | Own related Bill only | Authorized Bill/Proof | Authorized Bill/Proof | EXISTING ROUTE — CONTRACT CHANGE REQUIRED |
| Audit list | Deny | Operational scope | All authorized | EXISTING ROUTE — CONTRACT CHANGE REQUIRED |

## 11. Unresolved Contract Decisions

The following require backend/product confirmation and are not implementation
claims:

1. Whether factory Dispatch permanently follows the backend reference's
   `total -= quantityChange` rule or should use a `biIssued` issue ledger.
2. Exact backend normalization/case-folding algorithm for `requestedId`, and
   whether `accountId` always preserves the submitted uppercase value.
3. Migration duration for request `section` alongside required `module` and
   singular `proofFileId` alongside plural Proof fields.
4. Retention periods and cleanup mechanism for unreferenced uploads, archived
   users/factories, transactions, and immutable audits.
5. Whether image uploads retain their original media type or are converted to
   JPEG after validation; returned metadata must always match stored bytes.
6. Whether an atomic multi-line request endpoint will be added later; current
   required behavior remains one non-atomic request per material line.

## 12. Compatibility Notes

- Local/mock services demonstrate frontend behavior only. They are not evidence
  of backend support, durability, security, audit completeness, or exact
  transactionality.
- The current Flutter response parsers retain several legacy fields and defaults.
  Backend responses should provide the complete required fields rather than
  relying on frontend defaults.
- Current compatibility fields include request `itemId`, singular transaction
  `proofFileId`/`proofFile` for response rendering, and audit `id`, nested
  `actor`, and `occurredAt`. They cannot be replaced until a coordinated
  Flutter release.
- Access tokens may appear only in login and refresh responses. Refresh tokens
  never appear in JSON responses. No response may expose plaintext passwords,
  password hashes, internal storage paths, raw stack traces, or unredacted audit
  payloads.
