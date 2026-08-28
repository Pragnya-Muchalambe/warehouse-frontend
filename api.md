Status: Planned production API specification. Backend implementation pending.

# Warehouse Production API Specification

**Specification version:** 1.0.0-draft.1
**Proposed configurable base URL:** `${WAREHOUSE_API_BASE_URL}/api/v1`
**Example only:** `https://warehouse.example.in/api/v1`

This document is an implementation-ready contract proposed for replacing the current Flutter proof-of-concept's local persistence. It describes intended behavior, not an implemented, deployed, or tested backend.

Normative terms `MUST`, `MUST NOT`, `SHOULD`, and `MAY` carry their RFC 2119 meanings.

## 1. Status Labels

Statements are tagged where their status could otherwise be ambiguous:

| Label | Meaning |
| --- | --- |
| **Current local Flutter** | Behavior observed in the repository. It is device-local and is not a network contract. |
| **Proposed backend** | Normative production API behavior specified here. Backend implementation is pending. |
| **Assumption/recommendation** | A safe production decision that still requires product or architecture confirmation. |

## 2. Planned Technology Stack

### 2.1 Proposed Backend

| Concern | Planned decision |
| --- | --- |
| API style | Versioned JSON REST under `/api/v1`; multipart only for file upload. |
| Framework | **Assumption/recommendation:** FastAPI with Pydantic and SQLAlchemy/Alembic. The contract is framework-neutral if another REST framework is selected. |
| Database | **Assumption/recommendation:** PostgreSQL 16 or later. |
| File storage | **Assumption/recommendation:** S3-compatible private object storage, with metadata and references in PostgreSQL. Local disk is unsuitable for horizontally scaled production. |
| Authentication | Short-lived JWT access tokens plus opaque, rotating refresh tokens. |
| Password hashing | Argon2id using current OWASP parameters; hashes and plaintext passwords are never returned or logged. |
| Deployment | TLS-terminated containers behind a reverse proxy/load balancer. |
| Observability | Structured application logs, metrics, traces, and immutable business audit records. |
| API documentation | Generated OpenAPI 3.1 must match this contract. |
| Background work | Optional worker for virus scanning, orphan-file cleanup, and exports. Transactional stock updates remain synchronous. |

### 2.2 Current Flutter Dependencies

**Current local Flutter:** `shared_preferences`, `csv`, and `image_picker` provide local storage, CSV seeding, and image capture. No HTTP client, secure token storage, WebSocket, or SSE client is declared in `pubspec.yaml`.

**Assumption/recommendation:** the examples below use conceptual `package:http` and secure storage APIs. They are illustrative only and do not claim those dependencies are installed.

## 3. Current Frontend vs Planned Backend

| Area | Current local Flutter | Proposed backend |
| --- | --- | --- |
| Persistence | JSON in `SharedPreferences`. | PostgreSQL is authoritative. |
| Authentication | Local credential comparison; local session JSON. | Server-side account approval, Argon2id verification, access JWT, rotating refresh token. |
| IDs | Microsecond timestamps and seeded strings. | UUIDs for generated resources; preserve material PL identifiers where possible. |
| Depot seed | CSV read on first run; random quantity `0..20`. | Deterministic migration/seed; quantities explicitly configured, never random. |
| Factory seed | Three local demo factories. | Explicit seed migration or administrative creation. |
| Search | Client substring filtering; local hit counters. | Server search/filter/sort/pagination and atomic hit registration. |
| Stock mutation | In-memory update followed by multiple local writes; negative totals are clamped. | Database transaction, row locks, reject negative outcomes, append audit. |
| Factory stock | Factory action can also mutate matching main inventory by PL. | Factory ledger alone is authoritative for factory operations; no depot dual-write. |
| Files | Bill and Proof bytes base64-encoded only up to 1 MiB; larger bytes silently omitted. | Bill and Proof uploaded independently to object storage, each up to configurable 10 MiB. |
| Transactions | Bill and Proof are independently required in the current form. | `billFileId` and `proofFileId` are independent and both required for new transactions. |
| Real time | No network client support. | REST only in this version. WebSocket/SSE is optional future work, not a contracted endpoint. |

## 4. Quick Start

These commands illustrate the proposed API and use placeholders, not repository credentials.

```bash
export WAREHOUSE_API_BASE_URL="https://warehouse.example.in"

curl --request POST \
  "$WAREHOUSE_API_BASE_URL/api/v1/auth/login" \
  --header "Content-Type: application/json" \
  --data '{"username":"operator@example.invalid","password":"<secret>"}'
```

Use the returned access token:

```bash
curl "$WAREHOUSE_API_BASE_URL/api/v1/inventory?q=T-6902&limit=20" \
  --header "Authorization: Bearer <access-token>"
```

Upload Bill and Proof independently, then create a JSON transaction:

```bash
curl --request POST "$WAREHOUSE_API_BASE_URL/api/v1/files" \
  --header "Authorization: Bearer <access-token>" \
  --form "purpose=BILL" \
  --form "file=@bill.pdf;type=application/pdf"

curl --request POST "$WAREHOUSE_API_BASE_URL/api/v1/files" \
  --header "Authorization: Bearer <access-token>" \
  --form "purpose=PROOF" \
  --form "file=@delivery.webp;type=image/webp"
```

## 5. Global Conventions

### 5.1 Transport and Media Types

- Production MUST use HTTPS. Plain HTTP MAY be used only in isolated local development.
- JSON requests use `Content-Type: application/json` and UTF-8.
- JSON responses use `application/json; charset=utf-8`.
- File upload alone uses `multipart/form-data`.
- File content responses use the stored validated MIME type.
- Clients SHOULD send `Accept: application/json`, except when downloading file content.
- Unknown JSON fields MUST produce `422 VALIDATION_ERROR` to expose client/server drift.
- Request bodies are limited to 1 MiB unless the endpoint is a file upload.

### 5.2 Headers

| Header | Requirement | Meaning |
| --- | --- | --- |
| `Authorization: Bearer <accessToken>` | Required on protected endpoints. | Access JWT. |
| `Idempotency-Key` | Required on specified create/action endpoints; UUID recommended. | Deduplicates retries for 24 hours per actor and endpoint. |
| `If-Match` | Required on mutable resource `PATCH` operations. | Exact quoted integer resource version, for example `"4"`. |
| `X-Request-Id` | Optional request; always returned. | Client correlation ID or server-generated UUID. |
| `Accept-Language` | Optional. | Reserved; API enum values and default messages remain English. |

Every response MUST include `X-Request-Id`. Resource responses SHOULD include `ETag: "<version>"`. Sensitive responses MUST include `Cache-Control: no-store`.

### 5.3 Success Envelopes

Single resource:

```json
{
  "data": {
    "id": "018f4f3d-17ce-7d5e-bcd3-2c4abf989423",
    "version": 1
  },
  "meta": {
    "requestId": "8995e46e-32b1-4aa4-9740-8cd25966c877"
  }
}
```

Collection:

```json
{
  "data": [],
  "page": {
    "limit": 50,
    "nextCursor": null,
    "hasMore": false
  },
  "meta": {
    "requestId": "8995e46e-32b1-4aa4-9740-8cd25966c877"
  }
}
```

Actions returning no resource use `204 No Content` with no body. The API does not return a generic success boolean.

### 5.4 Error Envelope

Every non-2xx JSON response MUST use:

```json
{
  "error": {
    "code": "VALIDATION_ERROR",
    "message": "The request contains invalid fields.",
    "details": [
      {
        "field": "items[0].quantityChange",
        "code": "MUST_BE_POSITIVE",
        "message": "Must be greater than zero."
      }
    ],
    "retryable": false
  },
  "meta": {
    "requestId": "8995e46e-32b1-4aa4-9740-8cd25966c877"
  }
}
```

| HTTP | Stable code | Use |
| --- | --- | --- |
| `400` | `BAD_REQUEST` | Malformed JSON/multipart, invalid cursor, conflicting parameters. |
| `401` | `UNAUTHORIZED`, `TOKEN_EXPIRED`, `INVALID_REFRESH_TOKEN` | Authentication failed. |
| `403` | `FORBIDDEN`, `ACCOUNT_INACTIVE` | Authenticated but not allowed. |
| `404` | `NOT_FOUND` | Resource absent or intentionally concealed. |
| `409` | `CONFLICT`, `DUPLICATE_ID`, `INSUFFICIENT_STOCK`, `INVALID_TRANSITION`, `IDEMPOTENCY_CONFLICT` | State conflict. |
| `412` | `VERSION_CONFLICT` | `If-Match` does not match current version. |
| `413` | `FILE_TOO_LARGE` | Upload exceeds configured limit. |
| `415` | `UNSUPPORTED_MEDIA_TYPE` | File or body media type rejected. |
| `422` | `VALIDATION_ERROR` | Semantically invalid fields. |
| `429` | `RATE_LIMITED` | Throttling. Include `Retry-After`. |
| `500` | `INTERNAL_ERROR` | Unexpected failure; no internals exposed. |
| `503` | `SERVICE_UNAVAILABLE` | Required dependency unavailable. |

Clients MAY retry only when `retryable` is true, or for network failure/`429`/`503`, using exponential backoff with jitter. Mutations MUST be retried with the same `Idempotency-Key`.

### 5.5 Pagination, Filter, Search, and Sort

**Assumption/recommendation:** cursor pagination is standard for every collection.

| Query | Default | Rules |
| --- | --- | --- |
| `limit` | `50` | Integer `1..100`. |
| `cursor` | absent | Opaque server token; clients MUST NOT parse it. |
| `q` | absent | Trimmed case-insensitive substring over documented fields; max 100 characters. |
| `sort` | endpoint-specific | Comma-separated fields; prefix `-` means descending. |
| filters | absent | Exact enums/IDs unless documented otherwise. Repeated values use comma-separated enums. |

Sort always has a deterministic ID tie-breaker. Invalid fields return `400 BAD_REQUEST`. `nextCursor` is valid only with the same query/filter/sort set. Collection endpoints do not promise a total count because exact counts are expensive and race-prone; a future `total` MAY be added to `page` without changing semantics.

### 5.6 Dates, Timestamps, IDs, and Naming

- JSON field names use `lowerCamelCase`.
- Enum wire values use uppercase snake case unless this specification explicitly preserves an established value.
- Timestamps are RFC 3339 UTC with `Z`, for example `2026-08-27T10:15:30.123Z`.
- Date-only logistics fields use ISO `YYYY-MM-DD`; they are not timestamps.
- Server sets `createdAt`, `updatedAt`, and actor fields. Client-supplied transaction time is not accepted.
- Generated resource IDs are UUIDv7 if available, otherwise UUIDv4, serialized lowercase with hyphens.
- User-facing account IDs and material IDs remain opaque strings. Material IDs SHOULD preserve PL identifiers exactly after trimming internal CSV line breaks and surrounding whitespace.
- PL comparisons are case-insensitive for uniqueness. Responses return the canonical stored spelling.
- `version` is a positive integer incremented on each mutable business change.
- Names are trimmed, Unicode-normalized, `1..200` characters, and must contain at least one non-whitespace character.

### 5.7 Idempotency Semantics

- Required for: account request creation/decision, admin creation, material/factory creation, request creation/decision, file upload, transaction creation/correction/reversal, and search-hit registration.
- The server stores actor, endpoint, key, canonical request hash, status, and response for at least 24 hours.
- Same key and same request returns the original status/body and `Idempotency-Replayed: true` without repeating side effects.
- Same key with a different request returns `409 IDEMPOTENCY_CONFLICT`.
- Authentication login/refresh/logout use token-specific replay controls instead of `Idempotency-Key`.

## 6. Authentication and Token Handling

### 6.1 Token Model

**Assumption/recommendation requiring confirmation:**

- Access JWT lifetime: 15 minutes.
- Refresh token lifetime: 30 days idle, 90 days absolute.
- Refresh tokens are opaque 256-bit random values, stored hashed server-side, and rotated on every refresh.
- Reuse of an already-rotated refresh token revokes its entire token family.
- JWT includes `iss`, `aud`, `sub` (user UUID), `role`, `iat`, `exp`, `jti`, and `sessionId`.
- The server reads identity and role from persisted user state for sensitive operations; it does not trust client-submitted actor fields.
- Mobile refresh tokens belong in OS-backed secure storage. Access tokens SHOULD remain in memory.
- Logout revokes the refresh session and deny-lists the current access `jti` until expiry.
- Passwords are hashed with Argon2id. Neither plaintext passwords nor hashes are returned, audited, or logged.

Account approval is entirely server-side and atomically creates the account. Password reset is **optional future functionality** because the current repository has no reset workflow. No password-reset endpoint is part of version 1; adding one requires verified recovery channels, one-time expiring tokens, session revocation, rate limits, and a separate contract revision.

### 6.2 User Resource

```json
{
  "id": "f49b7b8c-ddf4-4eec-b3fc-25cb2ad938a9",
  "accountId": "OP-2048",
  "username": "op-2048",
  "name": "Depot Operator",
  "role": "ADMIN",
  "status": "ACTIVE",
  "createdAt": "2026-08-27T10:15:30.123Z",
  "updatedAt": "2026-08-27T10:15:30.123Z",
  "version": 1
}
```

Passwords and password hashes are never fields on this resource.

## 7. Roles and Permission Principles

| Role | Capabilities |
| --- | --- |
| `VIEWER` | Read depot/factory inventory and mappings; create and read own material requests; read own profile. |
| `ADMIN` | Viewer read capabilities; create/edit inventory and factories; process requests; upload/read transaction files; create/read transactions and logs. Cannot manage users, undo decisions, correct/reverse transactions, or view account requests. |
| `SUPERADMIN` | All administrative capabilities; account/user management; request undo; transaction correction and proposed reversal. |

Rules:

- Roles are not implicitly user-editable. Only `SUPERADMIN` may manage users.
- A superadmin MUST NOT demote/deactivate their own account.
- The last active superadmin MUST NOT be demoted or deactivated.
- `ADMIN` creation is restricted to `SUPERADMIN`; anonymous account requests may request `ADMIN` or `VIEWER`, but only superadmin approval activates the account.
- Viewers cannot access transaction files merely because they can read inventory.
- Resource ownership is server-derived. A viewer's `viewerId` query cannot expand access beyond their own records.

## 8. Core Resource Schemas

### 8.1 Inventory Material

```json
{
  "id": "T-6902",
  "name": "Improved SEJ -60 Kg (with 80 mm max: gap) B.G.60 kg (UIC) on PSC sleepers",
  "quantity": 120,
  "biIssued": 20,
  "available": 100,
  "uom": "Pieces",
  "status": "AVAILABLE",
  "section": "DEPOT",
  "searchFrequency": 7,
  "lastSearchedAt": "2026-08-27T09:00:00.000Z",
  "lastEditedAt": "2026-08-26T11:00:00.000Z",
  "incomingQuantity": 40,
  "expectedAvailabilityDate": "2026-09-03",
  "purchaseOrderStatus": "ORDERED",
  "createdAt": "2026-08-01T00:00:00.000Z",
  "updatedAt": "2026-08-26T11:00:00.000Z",
  "version": 3
}
```

`available = quantity - biIssued`; production validation guarantees this is non-negative. `status` is derived as `AVAILABLE` when `available > 0`, otherwise `UNAVAILABLE`; clients cannot write it.

### 8.2 Factory and Factory Material

```json
{
  "id": "740d19ed-dbe1-40c0-82f1-cf258ac93f53",
  "name": "Bengaluru Sleeper Plant",
  "location": "Bangalore",
  "materialCount": 1,
  "createdAt": "2026-08-01T00:00:00.000Z",
  "updatedAt": "2026-08-27T08:00:00.000Z",
  "version": 2
}
```

```json
{
  "id": "T-5836",
  "name": "Switch for trap - 52 kg",
  "total": 300,
  "biIssued": 60,
  "available": 240,
  "status": "AVAILABLE",
  "incomingQuantity": 50,
  "expectedAvailabilityDate": "2026-09-03",
  "purchaseOrderStatus": "PENDING",
  "createdAt": "2026-08-01T00:00:00.000Z",
  "updatedAt": "2026-08-27T08:00:00.000Z",
  "version": 2
}
```

For factory material, `total` remains `total`; it is not renamed to `quantity`. Factory stock is authoritative within `(factoryId, materialId)` and MUST NOT dual-write depot/main inventory.

### 8.3 Material Request

```json
{
  "id": "f29552b0-f075-4c20-943a-23c8e02b8047",
  "viewerId": "f49b7b8c-ddf4-4eec-b3fc-25cb2ad938a9",
  "viewerAccountId": "VW-2048",
  "viewerName": "Depot Viewer",
  "itemId": "T-5836",
  "itemName": "Switch for trap - 52 kg",
  "quantity": 5,
  "section": "DEPOT",
  "status": "PENDING",
  "decisionBy": null,
  "decisionAt": null,
  "history": [],
  "createdAt": "2026-08-27T10:15:30.123Z",
  "updatedAt": "2026-08-27T10:15:30.123Z",
  "version": 1
}
```

### 8.4 File Metadata

```json
{
  "id": "0ddbf6af-89db-49bf-a528-c8785622768d",
  "purpose": "BILL",
  "fileName": "supplier-bill.pdf",
  "contentType": "application/pdf",
  "sizeBytes": 482193,
  "sha256": "b5cfc9a6f04d28f339e5d5417bd649a7ed0ff02bf65d12c74f32e41f87d2b2ec",
  "status": "READY",
  "createdBy": {
    "id": "f49b7b8c-ddf4-4eec-b3fc-25cb2ad938a9",
    "accountId": "AD-2048",
    "name": "Depot Operator"
  },
  "createdAt": "2026-08-27T10:10:00.000Z",
  "referenced": false,
  "version": 1
}
```

### 8.5 Transaction

```json
{
  "id": "71fa206b-bf16-469a-bf4f-5386851dd66e",
  "type": "INCOMING",
  "scope": "DEPOT",
  "factoryId": null,
  "factoryNameSnapshot": null,
  "items": [
    {
      "materialId": "T-6902",
      "materialNameSnapshot": "Improved SEJ -60 Kg (with 80 mm max: gap) B.G.60 kg (UIC) on PSC sleepers",
      "quantityChange": 25
    }
  ],
  "notes": "Delivery against scheduled supply",
  "person": "North Zone Supplier",
  "comingFrom": "Delhi",
  "dateOfArrival": "2026-08-27",
  "dateRequested": null,
  "dateLeaving": null,
  "truckNumber": "KA01AB1234",
  "billFileId": "0ddbf6af-89db-49bf-a528-c8785622768d",
  "proofFileId": "467253ce-eb95-4347-b050-9f446f03f9dd",
  "billFile": {
    "id": "0ddbf6af-89db-49bf-a528-c8785622768d",
    "purpose": "BILL",
    "fileName": "supplier-bill.pdf",
    "contentType": "application/pdf",
    "sizeBytes": 482193
  },
  "proofFile": {
    "id": "467253ce-eb95-4347-b050-9f446f03f9dd",
    "purpose": "PROOF",
    "fileName": "delivery.webp",
    "contentType": "image/webp",
    "sizeBytes": 318200
  },
  "createdBy": {
    "id": "f49b7b8c-ddf4-4eec-b3fc-25cb2ad938a9",
    "accountId": "AD-2048",
    "name": "Depot Operator"
  },
  "createdAt": "2026-08-27T10:15:30.123Z",
  "updatedAt": "2026-08-27T10:15:30.123Z",
  "correctedAt": null,
  "reversedAt": null,
  "version": 1
}
```

`quantityChange` is always a positive magnitude. `type` and `scope` determine direction; clients MUST NOT send signed quantities.

### 8.6 Audit Log

```json
{
  "id": "255bb70b-1159-4d80-8314-6d65f4dff475",
  "eventType": "TRANSACTION_CREATED",
  "entityType": "TRANSACTION",
  "entityId": "71fa206b-bf16-469a-bf4f-5386851dd66e",
  "actor": {
    "id": "f49b7b8c-ddf4-4eec-b3fc-25cb2ad938a9",
    "accountId": "AD-2048",
    "name": "Depot Operator",
    "role": "ADMIN"
  },
  "occurredAt": "2026-08-27T10:15:30.123Z",
  "requestId": "8995e46e-32b1-4aa4-9740-8cd25966c877",
  "reason": null,
  "before": null,
  "after": {"type":"INCOMING","scope":"DEPOT"},
  "billFile": {"id":"0ddbf6af-89db-49bf-a528-c8785622768d","purpose":"BILL","fileName":"supplier-bill.pdf"},
  "proofFile": {"id":"467253ce-eb95-4347-b050-9f446f03f9dd","purpose":"PROOF","fileName":"delivery.webp"}
}
```

Audit always exposes separate `billFile` and `proofFile` metadata. It never collapses them into `file`, `fileId`, `photo`, or a generic attachment.

## 9. Complete Endpoint Reference

The general envelope, headers, pagination, error, versioning, and idempotency rules in Section 5 apply to every endpoint. Each endpoint below states endpoint-specific requirements and complete successful representation.

### 9.1 Health

#### `GET /health`

- **Purpose:** Load-balancer liveness/readiness signal; no business data.
- **Auth/roles:** Public; no role.
- **Parameters/headers/body:** No path/query/body. `Authorization` ignored. No idempotency key.
- **Success:** `200 OK`.

```json
{
  "data": {
    "status": "UP",
    "service": "warehouse-api",
    "specVersion": "1.0.0-draft.1",
    "time": "2026-08-27T10:15:30.123Z"
  },
  "meta": {"requestId":"8995e46e-32b1-4aa4-9740-8cd25966c877"}
}
```

- **Errors/validation/auth:** `503 SERVICE_UNAVAILABLE` when required database/storage readiness checks fail. Response MUST NOT expose dependency addresses or secrets.
- **Side effects/audit/inventory:** None; no business audit.
- **Idempotency/retry:** Safe and idempotent; retry with backoff on network failure/`503`.

### 9.2 Authentication

#### `POST /auth/login`

- **Purpose:** Authenticate an active user and create a refresh session.
- **Auth/roles:** Public; all active roles may authenticate.
- **Parameters/headers/body:** JSON body below. No query/path parameters. `username` is trimmed and matched case-insensitively; password remains case-sensitive. No `Idempotency-Key`.

```json
{"username":"op-2048","password":"<secret>"}
```

- **Success:** `200 OK`, `Cache-Control: no-store`.

```json
{
  "data": {
    "accessToken": "<jwt>",
    "accessTokenExpiresAt": "2026-08-27T10:30:30.123Z",
    "refreshToken": "<opaque-refresh-token>",
    "refreshTokenExpiresAt": "2026-09-26T10:15:30.123Z",
    "tokenType": "Bearer",
    "user": {
      "id": "f49b7b8c-ddf4-4eec-b3fc-25cb2ad938a9",
      "accountId": "OP-2048",
      "username": "op-2048",
      "name": "Depot Operator",
      "role": "ADMIN",
      "status": "ACTIVE",
      "createdAt": "2026-08-01T00:00:00.000Z",
      "updatedAt": "2026-08-01T00:00:00.000Z",
      "version": 1
    }
  },
  "meta": {"requestId":"8995e46e-32b1-4aa4-9740-8cd25966c877"}
}
```

- **Errors/validation/auth:** `422` missing/blank username or password; `401 UNAUTHORIZED` uses one generic message for unknown user/wrong password; `403 ACCOUNT_INACTIVE`; `429 RATE_LIMITED`. Never reveal account existence.
- **Side effects/audit/inventory:** Creates hashed refresh-session record; records security event `LOGIN_SUCCEEDED` or redacted `LOGIN_FAILED`; no inventory effect.
- **Idempotency/retry:** Not idempotent because each success creates a session. Client may retry once after an unknown network outcome; duplicate sessions are acceptable and independently revocable.

#### `POST /auth/refresh`

- **Purpose:** Rotate a refresh token and issue a new access token.
- **Auth/roles:** Public transport endpoint; possession of a valid refresh token authenticates the session.
- **Parameters/headers/body:** No bearer token required. JSON body:

```json
{"refreshToken":"<opaque-refresh-token>"}
```

- **Success:** `200 OK`, `Cache-Control: no-store`.

```json
{
  "data": {
    "accessToken": "<new-jwt>",
    "accessTokenExpiresAt": "2026-08-27T10:45:30.123Z",
    "refreshToken": "<new-opaque-refresh-token>",
    "refreshTokenExpiresAt": "2026-09-26T10:30:30.123Z",
    "tokenType": "Bearer",
    "user": {
      "id": "f49b7b8c-ddf4-4eec-b3fc-25cb2ad938a9",
      "accountId": "OP-2048",
      "username": "op-2048",
      "name": "Depot Operator",
      "role": "ADMIN",
      "status": "ACTIVE",
      "createdAt": "2026-08-01T00:00:00.000Z",
      "updatedAt": "2026-08-01T00:00:00.000Z",
      "version": 1
    }
  },
  "meta": {"requestId":"8995e46e-32b1-4aa4-9740-8cd25966c877"}
}
```
- **Errors/validation/auth:** `422` missing token; `401 INVALID_REFRESH_TOKEN` invalid/expired/revoked token; detected token reuse revokes the family; `403 ACCOUNT_INACTIVE`; `429` abuse throttle.
- **Side effects/audit/inventory:** Atomically revokes old refresh token and persists replacement; security audit only; no inventory effect.
- **Idempotency/retry:** Rotation creates a retry hazard. Server SHOULD retain the immediately replaced response for a 30-second grace keyed by old token and client session, returning the same replacement once. Otherwise an old-token retry returns `401` and the client must re-login.

#### `POST /auth/logout`

- **Purpose:** Revoke the current refresh session and access token.
- **Auth/roles:** Any authenticated `VIEWER`, `ADMIN`, or `SUPERADMIN`.
- **Parameters/headers/body:** Bearer token required. JSON body includes the refresh token for the same session:

```json
{"refreshToken":"<opaque-refresh-token>"}
```

- **Success:** `204 No Content`, including when that session is already revoked. The response has no body.
- **Errors/validation/auth:** `401` if access token is missing/invalid; `422` malformed body. A refresh token from another session is not revoked and returns `403`.
- **Side effects/audit/inventory:** Revokes refresh session and access `jti`; logs `LOGOUT`; no inventory effect.
- **Idempotency/retry:** Idempotent by session; safe to retry. Client clears local tokens even if network logout fails.

#### `GET /auth/me`

- **Purpose:** Validate the session and retrieve authoritative current profile/role/status.
- **Auth/roles:** Any authenticated role.
- **Parameters/headers/body:** Bearer token; no body/path/query.
- **Success:** `200 OK`.

```json
{
  "data": {
    "id": "f49b7b8c-ddf4-4eec-b3fc-25cb2ad938a9",
    "accountId": "OP-2048",
    "username": "op-2048",
    "name": "Depot Operator",
    "role": "ADMIN",
    "status": "ACTIVE",
    "createdAt": "2026-08-01T00:00:00.000Z",
    "updatedAt": "2026-08-01T00:00:00.000Z",
    "version": 1
  },
  "meta": {"requestId":"8995e46e-32b1-4aa4-9740-8cd25966c877"}
}
```
- **Errors/validation/auth:** `401 UNAUTHORIZED`/`TOKEN_EXPIRED`; `403 ACCOUNT_INACTIVE`.
- **Side effects/audit/inventory:** May update non-audited `lastSeenAt`; no business audit or inventory effect.
- **Idempotency/retry:** Safe/idempotent; retry after refresh on `TOKEN_EXPIRED`.

### 9.3 Account Requests and Users

#### `POST /account-requests`

- **Purpose:** Submit a pre-login request for a `VIEWER` or `ADMIN` account.
- **Auth/roles:** Public/anonymous.
- **Parameters/headers/body:** `Idempotency-Key` required. No query/path. JSON:

```json
{
  "name": "New Depot Viewer",
  "requestedId": "VW-2048",
  "password": "<strong-secret>",
  "role": "VIEWER"
}
```

- **Success:** `201 Created` with `Location: /api/v1/account-requests/<id>`; response deliberately excludes password:

```json
{
  "data": {
    "id": "79ff39b8-826c-40f3-b09c-f6af17745fb8",
    "name": "New Depot Viewer",
    "requestedId": "VW-2048",
    "role": "VIEWER",
    "status": "PENDING",
    "submittedAt": "2026-08-27T10:15:30.123Z",
    "decisionBy": null,
    "decisionAt": null,
    "version": 1
  },
  "meta": {"requestId":"8995e46e-32b1-4aa4-9740-8cd25966c877"}
}
```

- **Errors/validation/auth:** name `1..200`; requested ID `3..64`, `^[A-Za-z0-9-]+$`, canonical uppercase; role only `VIEWER|ADMIN`; recommended password minimum 12 characters and compromised-password screening. `409 DUPLICATE_ID` for collision with active users or pending requests, using a non-enumerating public message; `429` rate limit/CAPTCHA policy.
- **Side effects/audit/inventory:** Password is immediately Argon2id-hashed and plaintext discarded; creates pending request and `ACCOUNT_REQUEST_CREATED` audit without secret; no user/inventory yet.
- **Idempotency/retry:** Required key. Same key replays the redacted response; never hashes/stores a duplicate.

#### `GET /account-requests`

- **Purpose:** List account requests for superadmin review.
- **Auth/roles:** `SUPERADMIN` only.
- **Parameters/headers/body:** Bearer token. Queries: `status=PENDING|ACCEPTED|REJECTED`, `role=VIEWER|ADMIN`, `q` over name/requestedId, `sort=-submittedAt|submittedAt|requestedId`, pagination. No body.
- **Success:** `200 OK` collection where each item has exactly the redacted account-request fields shown above; newest first by default.

```json
{
  "data": [{
    "id": "79ff39b8-826c-40f3-b09c-f6af17745fb8",
    "name": "New Depot Viewer",
    "requestedId": "VW-2048",
    "role": "VIEWER",
    "status": "PENDING",
    "submittedAt": "2026-08-27T10:15:30.123Z",
    "decisionBy": null,
    "decisionAt": null,
    "version": 1
  }],
  "page": {"limit":50,"nextCursor":null,"hasMore":false},
  "meta": {"requestId":"8995e46e-32b1-4aa4-9740-8cd25966c877"}
}
```
- **Errors/validation/auth:** `401`; `403` other roles; `400` invalid enum/sort/cursor.
- **Side effects/audit/inventory:** Read may be access-logged; no business or inventory mutation.
- **Idempotency/retry:** Safe/idempotent.

#### `POST /account-requests/{accountRequestId}/approve`

- **Purpose:** Atomically approve a pending request and create its active user.
- **Auth/roles:** `SUPERADMIN` only.
- **Parameters/headers/body:** UUID path; `Idempotency-Key` and `If-Match` required; body `{}`.
- **Success:** `200 OK`:

```json
{
  "data": {
    "accountRequest": {
      "id": "79ff39b8-826c-40f3-b09c-f6af17745fb8",
      "name": "New Depot Viewer",
      "requestedId": "VW-2048",
      "role": "VIEWER",
      "status": "ACCEPTED",
      "submittedAt": "2026-08-27T10:15:30.123Z",
      "decisionBy": "f105dcb5-216c-4ff7-a589-9fef95eca25f",
      "decisionAt": "2026-08-27T10:20:00.000Z",
      "version": 2
    },
    "user": {
      "id": "f49b7b8c-ddf4-4eec-b3fc-25cb2ad938a9",
      "accountId": "VW-2048",
      "username": "vw-2048",
      "name": "New Depot Viewer",
      "role": "VIEWER",
      "status": "ACTIVE",
      "createdAt": "2026-08-27T10:20:00.000Z",
      "updatedAt": "2026-08-27T10:20:00.000Z",
      "version": 1
    }
  },
  "meta": {"requestId":"8995e46e-32b1-4aa4-9740-8cd25966c877"}
}
```

- **Errors/validation/auth:** `404`; `409 INVALID_TRANSITION` if not pending; `409 DUPLICATE_ID` on approval-time collision; `412 VERSION_CONFLICT`; `401/403`.
- **Side effects/audit/inventory:** Under one DB transaction and row lock, creates user using stored hash, marks request accepted, removes hash from request retention where feasible, records `ACCOUNT_REQUEST_APPROVED` and `USER_CREATED`; no inventory effect. Password is never returned.
- **Idempotency/retry:** Required key; replay returns original pair without creating another user.

#### `POST /account-requests/{accountRequestId}/reject`

- **Purpose:** Reject a pending account request.
- **Auth/roles:** `SUPERADMIN` only.
- **Parameters/headers/body:** UUID path; `Idempotency-Key`, `If-Match`; JSON reason required:

```json
{"reason":"Requested access could not be verified."}
```

- **Success:** `200 OK` with complete redacted account request, `status: "REJECTED"`, decision fields and incremented version.

```json
{
  "data": {
    "id": "79ff39b8-826c-40f3-b09c-f6af17745fb8",
    "name": "New Depot Viewer",
    "requestedId": "VW-2048",
    "role": "VIEWER",
    "status": "REJECTED",
    "submittedAt": "2026-08-27T10:15:30.123Z",
    "decisionBy": "f105dcb5-216c-4ff7-a589-9fef95eca25f",
    "decisionAt": "2026-08-27T10:20:00.000Z",
    "version": 2
  },
  "meta": {"requestId":"8995e46e-32b1-4aa4-9740-8cd25966c877"}
}
```
- **Errors/validation/auth:** reason `1..500`; `404`; `409 INVALID_TRANSITION`; `412`; `401/403`.
- **Side effects/audit/inventory:** Marks rejected, deletes stored password hash, writes `ACCOUNT_REQUEST_REJECTED` with reason; no user/inventory.
- **Idempotency/retry:** Required key; safe replay.

#### `GET /users`

- **Purpose:** List users for superadmin permission management.
- **Auth/roles:** `SUPERADMIN` only.
- **Parameters/headers/body:** Queries `role`, `status=ACTIVE|INACTIVE`, `q` over accountId/username/name, `sort=name|-createdAt|accountId`, pagination. No body.
- **Success:** `200 OK` paginated complete user resources; no password fields.

```json
{
  "data": [{
    "id": "f49b7b8c-ddf4-4eec-b3fc-25cb2ad938a9",
    "accountId": "OP-2048",
    "username": "op-2048",
    "name": "Depot Operator",
    "role": "ADMIN",
    "status": "ACTIVE",
    "createdAt": "2026-08-01T00:00:00.000Z",
    "updatedAt": "2026-08-01T00:00:00.000Z",
    "version": 1
  }],
  "page": {"limit":50,"nextCursor":null,"hasMore":false},
  "meta": {"requestId":"8995e46e-32b1-4aa4-9740-8cd25966c877"}
}
```
- **Errors/validation/auth:** `401/403`; `400` invalid query.
- **Side effects/audit/inventory:** None beyond access log.
- **Idempotency/retry:** Safe/idempotent.

#### `POST /users/admins`

- **Purpose:** Directly create an admin when an account-request workflow is inappropriate.
- **Auth/roles:** `SUPERADMIN` only.
- **Parameters/headers/body:** `Idempotency-Key` required. JSON:

```json
{
  "accountId": "AD-2050",
  "username": "ad-2050",
  "name": "Regional Administrator",
  "password": "<strong-secret>"
}
```

- **Success:** `201 Created`, `Location: /api/v1/users/<id>`, complete User Resource with role `ADMIN`, without password.

```json
{
  "data": {
    "id": "4f78fb92-55d2-4bed-b922-22d59d268ee1",
    "accountId": "AD-2050",
    "username": "ad-2050",
    "name": "Regional Administrator",
    "role": "ADMIN",
    "status": "ACTIVE",
    "createdAt": "2026-08-27T10:20:00.000Z",
    "updatedAt": "2026-08-27T10:20:00.000Z",
    "version": 1
  },
  "meta": {"requestId":"8995e46e-32b1-4aa4-9740-8cd25966c877"}
}
```
- **Errors/validation/auth:** accountId/username uniqueness case-insensitive; accountId pattern as above; username `3..64`; name rules; recommended password policy; `409 DUPLICATE_ID`; `401/403`; `422` invalid fields.
- **Side effects/audit/inventory:** Hashes password, creates active admin, records `USER_CREATED` with creation mode `DIRECT_ADMIN`; no inventory.
- **Idempotency/retry:** Required key; replay cannot duplicate account.

#### `PATCH /users/{userId}`

- **Purpose:** Proposed user management beyond the existing UI: rename, role change, activation/deactivation.
- **Auth/roles:** `SUPERADMIN` only.
- **Parameters/headers/body:** UUID path; `If-Match` required; `Idempotency-Key` required. At least one field:

```json
{"name":"Regional Warehouse Administrator","role":"ADMIN","status":"ACTIVE"}
```

- **Success:** `200 OK` complete updated User Resource and new ETag.

```json
{
  "data": {
    "id": "4f78fb92-55d2-4bed-b922-22d59d268ee1",
    "accountId": "AD-2050",
    "username": "ad-2050",
    "name": "Regional Warehouse Administrator",
    "role": "ADMIN",
    "status": "ACTIVE",
    "createdAt": "2026-08-27T10:20:00.000Z",
    "updatedAt": "2026-08-27T10:25:00.000Z",
    "version": 2
  },
  "meta": {"requestId":"8995e46e-32b1-4aa4-9740-8cd25966c877"}
}
```
- **Errors/validation/auth:** `404`; `412`; `422` invalid enum/name; `409 LAST_SUPERADMIN`; `409 SELF_MANAGEMENT_FORBIDDEN` for own demotion/deactivation; account ID and username are immutable in v1; cannot promote directly to `SUPERADMIN` without an explicit organizational policy, recommended rejection `422`.
- **Side effects/audit/inventory:** Writes before/after `USER_UPDATED`; deactivation revokes all sessions atomically; no inventory.
- **Idempotency/retry:** Required key plus version; replay safe. A new key with stale ETag returns `412`.

### 9.4 Depot Inventory and Seed Mapping

#### `GET /inventory`

- **Purpose:** List/search/filter/sort depot/main inventory.
- **Auth/roles:** Any authenticated role.
- **Parameters/headers/body:** Queries `q` over id/name; `section=DEPOT|SLEEPER|BOTH`; `status=AVAILABLE|UNAVAILABLE`; `purchaseOrderStatus=NONE|PENDING|ORDERED`; `sort=-lastSearchedAt|-lastEditedAt|name|-name|-searchFrequency|id`; pagination. No body.
- **Success:** `200 OK` collection of complete Inventory Material objects. Default `sort=name,id`.

```json
{
  "data": [{
    "id":"T-6902","name":"Improved SEJ -60 Kg (with 80 mm max: gap) B.G.60 kg (UIC) on PSC sleepers",
    "quantity":120,"biIssued":20,"available":100,"uom":"Pieces","status":"AVAILABLE","section":"DEPOT",
    "searchFrequency":7,"lastSearchedAt":"2026-08-27T09:00:00.000Z","lastEditedAt":"2026-08-26T11:00:00.000Z",
    "incomingQuantity":40,"expectedAvailabilityDate":"2026-09-03","purchaseOrderStatus":"ORDERED",
    "createdAt":"2026-08-01T00:00:00.000Z","updatedAt":"2026-08-26T11:00:00.000Z","version":3
  }],
  "page": {"limit":50,"nextCursor":null,"hasMore":false},
  "meta": {"requestId":"8995e46e-32b1-4aa4-9740-8cd25966c877"}
}
```
- **Errors/validation/auth:** `401/403 inactive`; `400` invalid filters/sort/cursor.
- **Side effects/audit/inventory:** Search itself does not increment hits; use `/inventory/search-hits`. No mutation.
- **Idempotency/retry:** Safe/idempotent.

#### `POST /inventory`

- **Purpose:** Create a depot/main material.
- **Auth/roles:** `ADMIN`, `SUPERADMIN`.
- **Parameters/headers/body:** `Idempotency-Key` required. JSON:

```json
{
  "id": "T-6902",
  "name": "Improved SEJ -60 Kg (with 80 mm max: gap) B.G.60 kg (UIC) on PSC sleepers",
  "quantity": 120,
  "biIssued": 20,
  "uom": "Pieces",
  "section": "DEPOT",
  "incomingQuantity": 40,
  "expectedAvailabilityDate": "2026-09-03",
  "purchaseOrderStatus": "ORDERED"
}
```

- **Success:** `201 Created`, Location header, complete Inventory Material.

```json
{
  "data": {
    "id":"T-6902","name":"Improved SEJ -60 Kg (with 80 mm max: gap) B.G.60 kg (UIC) on PSC sleepers",
    "quantity":120,"biIssued":20,"available":100,"uom":"Pieces","status":"AVAILABLE","section":"DEPOT",
    "searchFrequency":0,"lastSearchedAt":null,"lastEditedAt":"2026-08-27T10:15:30.123Z",
    "incomingQuantity":40,"expectedAvailabilityDate":"2026-09-03","purchaseOrderStatus":"ORDERED",
    "createdAt":"2026-08-27T10:15:30.123Z","updatedAt":"2026-08-27T10:15:30.123Z","version":1
  },
  "meta": {"requestId":"8995e46e-32b1-4aa4-9740-8cd25966c877"}
}
```
- **Errors/validation/auth:** ID nonblank max 128 and unique case-insensitively; integer quantities `0..2147483647`; `biIssued <= quantity`; PO cross-field rules in Section 10; `409 DUPLICATE_ID`; `422`; `401/403`. `status`, available, counters, timestamps are not writable.
- **Side effects/audit/inventory:** Creates ledger balance and `MATERIAL_CREATED`; this initial balance is audited as administrative initialization, not an incoming transaction.
- **Idempotency/retry:** Required key; safe replay.

#### `POST /inventory/search-hits`

- **Purpose:** Record materials actually presented/selected for a meaningful frontend search.
- **Auth/roles:** Any authenticated role.
- **Parameters/headers/body:** `Idempotency-Key` required. Maximum 100 unique IDs:

```json
{"materialIds":["T-6902","T-5836"],"searchedAt":"2026-08-27T10:15:00.000Z"}
```

- **Success:** `200 OK`:

```json
{
  "data": {
    "updated": [
      {"materialId":"T-6902","searchFrequency":8,"lastSearchedAt":"2026-08-27T10:15:00.000Z"},
      {"materialId":"T-5836","searchFrequency":3,"lastSearchedAt":"2026-08-27T10:15:00.000Z"}
    ]
  },
  "meta": {"requestId":"8995e46e-32b1-4aa4-9740-8cd25966c877"}
}
```

- **Errors/validation/auth:** `422` empty/duplicate/too many IDs, future timestamp beyond 5 minutes; `404` if any material unknown, with no partial update; `401`.
- **Side effects/audit/inventory:** Atomically increments counters once per ID and sets `lastSearchedAt` to max(existing, supplied/server time). Analytics event only, not business audit; no stock effect.
- **Idempotency/retry:** Required to avoid double-counting; exact replay returns original counters.

#### `GET /inventory/{materialId}`

- **Purpose:** Get one depot/main material by URL-encoded canonical PL ID.
- **Auth/roles:** Any authenticated role.
- **Parameters/headers/body:** Path may contain spaces/slashes and MUST be percent-encoded; no body/query.
- **Success:** `200 OK` complete Inventory Material and ETag.

```json
{
  "data": {
    "id":"T-6902","name":"Improved SEJ -60 Kg (with 80 mm max: gap) B.G.60 kg (UIC) on PSC sleepers",
    "quantity":120,"biIssued":20,"available":100,"uom":"Pieces","status":"AVAILABLE","section":"DEPOT",
    "searchFrequency":8,"lastSearchedAt":"2026-08-27T10:15:00.000Z","lastEditedAt":"2026-08-26T11:00:00.000Z",
    "incomingQuantity":40,"expectedAvailabilityDate":"2026-09-03","purchaseOrderStatus":"ORDERED",
    "createdAt":"2026-08-01T00:00:00.000Z","updatedAt":"2026-08-26T11:00:00.000Z","version":3
  },
  "meta": {"requestId":"8995e46e-32b1-4aa4-9740-8cd25966c877"}
}
```
- **Errors/validation/auth:** `404 NOT_FOUND`; `401`.
- **Side effects/audit/inventory:** None; does not count as a search hit.
- **Idempotency/retry:** Safe/idempotent.

#### `PATCH /inventory/{materialId}`

- **Purpose:** Edit material metadata and absolute administrative balances/status planning fields.
- **Auth/roles:** `ADMIN`, `SUPERADMIN`.
- **Parameters/headers/body:** URL-encoded path; `If-Match` and `Idempotency-Key` required. Any nonempty subset:

```json
{
  "id": "T-6902",
  "name": "Improved SEJ 60 Kg on PSC sleepers",
  "quantity": 125,
  "biIssued": 20,
  "uom": "Pieces",
  "section": "DEPOT",
  "incomingQuantity": 0,
  "expectedAvailabilityDate": null,
  "purchaseOrderStatus": "NONE",
  "reason": "Physical stock reconciliation"
}
```

- **Success:** `200 OK` complete updated material, incremented version/ETag.

```json
{
  "data": {
    "id":"T-6902","name":"Improved SEJ 60 Kg on PSC sleepers",
    "quantity":125,"biIssued":20,"available":105,"uom":"Pieces","status":"AVAILABLE","section":"DEPOT",
    "searchFrequency":8,"lastSearchedAt":"2026-08-27T10:15:00.000Z","lastEditedAt":"2026-08-27T10:30:00.000Z",
    "incomingQuantity":0,"expectedAvailabilityDate":null,"purchaseOrderStatus":"NONE",
    "createdAt":"2026-08-01T00:00:00.000Z","updatedAt":"2026-08-27T10:30:00.000Z","version":4
  },
  "meta": {"requestId":"8995e46e-32b1-4aa4-9740-8cd25966c877"}
}
```
- **Errors/validation/auth:** `404`; `409 DUPLICATE_ID` on rename; `412`; `422` empty patch, invalid quantity, `biIssued > quantity`, invalid PO fields, or missing reason when balances/ID change; `401/403`.
- **Side effects/audit/inventory:** Atomic material update; stock/BI change creates `MATERIAL_BALANCE_ADJUSTED` with before/after and reason. Renaming updates references by stable internal key while historical snapshots remain unchanged.
- **Idempotency/retry:** Required key and ETag; safe replay.

#### `GET /material-serial-mappings`

- **Purpose:** Read-only canonical mapping seeded from `assets/material_serial_mappings.csv` for picker/import reconciliation.
- **Auth/roles:** Any authenticated role.
- **Parameters/headers/body:** `q` over materialId/name; `sort=materialId|name`; pagination. No mutations or import body.
- **Success:** `200 OK` collection:

```json
{
  "data": [
    {"materialId":"T-5836","name":"Switch for trap - 52 kg","source":"material_serial_mappings.csv"},
    {"materialId":"T-6902","name":"Improved SEJ -60 Kg (with 80 mm max: gap) B.G.60 kg (UIC) on PSC sleepers","source":"material_serial_mappings.csv"}
  ],
  "page": {"limit":50,"nextCursor":null,"hasMore":false},
  "meta": {"requestId":"8995e46e-32b1-4aa4-9740-8cd25966c877"}
}
```

- **Errors/validation/auth:** `400` query errors; `401`.
- **Side effects/audit/inventory:** None.
- **Idempotency/retry:** Safe/idempotent.

**Seed/import behavior:** this is a read-only endpoint, not a CSV upload endpoint. A deployment migration SHOULD parse the repository CSV with a standards-compliant multiline CSV parser, trim line breaks around identifiers such as `T-5836/ 6068`, preserve meaningful punctuation, normalize duplicate whitespace for display, and upsert mappings deterministically. Inventory creation from mappings is a separate explicit administrative action; no random quantities are generated. Bulk import is outside v1 and, if added, needs dry-run/error-report semantics.

### 9.5 Factories and Factory Materials

#### `GET /factories`

- **Purpose:** List factories without embedding all materials.
- **Auth/roles:** Any authenticated role.
- **Parameters/headers/body:** `q` over name/location; `sort=name|-updatedAt|location`; pagination. No body.
- **Success:** `200 OK` collection of complete Factory objects.

```json
{
  "data": [{
    "id":"740d19ed-dbe1-40c0-82f1-cf258ac93f53","name":"Bengaluru Sleeper Plant","location":"Bangalore",
    "materialCount":1,"createdAt":"2026-08-01T00:00:00.000Z","updatedAt":"2026-08-27T08:00:00.000Z","version":2
  }],
  "page": {"limit":50,"nextCursor":null,"hasMore":false},
  "meta": {"requestId":"8995e46e-32b1-4aa4-9740-8cd25966c877"}
}
```
- **Errors/validation/auth:** `400`; `401`.
- **Side effects/audit/inventory:** None.
- **Idempotency/retry:** Safe/idempotent.

#### `POST /factories`

- **Purpose:** Create an empty factory. Materials are added through the nested endpoint.
- **Auth/roles:** `ADMIN`, `SUPERADMIN`.
- **Parameters/headers/body:** `Idempotency-Key`; JSON:

```json
{"name":"Bengaluru Sleeper Plant","location":"Bangalore"}
```

- **Success:** `201 Created`, Location, complete Factory with `materialCount: 0`.

```json
{
  "data": {
    "id":"740d19ed-dbe1-40c0-82f1-cf258ac93f53","name":"Bengaluru Sleeper Plant","location":"Bangalore",
    "materialCount":0,"createdAt":"2026-08-27T10:15:30.123Z","updatedAt":"2026-08-27T10:15:30.123Z","version":1
  },
  "meta": {"requestId":"8995e46e-32b1-4aa4-9740-8cd25966c877"}
}
```
- **Errors/validation/auth:** name/location `1..200`; factory name unique case-insensitively recommended; `409 DUPLICATE_ID`; `422`; `401/403`.
- **Side effects/audit/inventory:** Creates factory, records `FACTORY_CREATED`; no stock.
- **Idempotency/retry:** Required key; replay safe.

#### `GET /factories/{factoryId}`

- **Purpose:** Get factory detail without embedded paginated materials.
- **Auth/roles:** Any authenticated role.
- **Parameters/headers/body:** UUID path; no body/query.
- **Success:** `200 OK` complete Factory and ETag.

```json
{
  "data": {
    "id":"740d19ed-dbe1-40c0-82f1-cf258ac93f53","name":"Bengaluru Sleeper Plant","location":"Bangalore",
    "materialCount":1,"createdAt":"2026-08-01T00:00:00.000Z","updatedAt":"2026-08-27T08:00:00.000Z","version":2
  },
  "meta": {"requestId":"8995e46e-32b1-4aa4-9740-8cd25966c877"}
}
```
- **Errors/validation/auth:** `404`; `401`.
- **Side effects/audit/inventory:** None.
- **Idempotency/retry:** Safe/idempotent.

#### `PATCH /factories/{factoryId}`

- **Purpose:** Edit factory name/location.
- **Auth/roles:** `ADMIN`, `SUPERADMIN`.
- **Parameters/headers/body:** UUID; `If-Match`, `Idempotency-Key`; nonempty subset:

```json
{"name":"Bengaluru Sleeper Plant - North","location":"Bangalore North"}
```

- **Success:** `200 OK` complete updated Factory and ETag.

```json
{
  "data": {
    "id":"740d19ed-dbe1-40c0-82f1-cf258ac93f53","name":"Bengaluru Sleeper Plant - North","location":"Bangalore North",
    "materialCount":1,"createdAt":"2026-08-01T00:00:00.000Z","updatedAt":"2026-08-27T10:30:00.000Z","version":3
  },
  "meta": {"requestId":"8995e46e-32b1-4aa4-9740-8cd25966c877"}
}
```
- **Errors/validation/auth:** `404`; `409` name collision; `412`; `422`; `401/403`.
- **Side effects/audit/inventory:** Writes `FACTORY_UPDATED`; prior transaction `factoryNameSnapshot` remains unchanged; no stock.
- **Idempotency/retry:** Required key/version; safe replay.

#### `GET /factories/{factoryId}/materials`

- **Purpose:** List/search/filter factory's authoritative material ledger.
- **Auth/roles:** Any authenticated role.
- **Parameters/headers/body:** UUID path; `q`, `status`, `purchaseOrderStatus`, `sort=name|-updatedAt|-available|id`, pagination. No body.
- **Success:** `200 OK` collection of complete Factory Material objects.

```json
{
  "data": [{
    "id":"T-5836","name":"Switch for trap - 52 kg","total":300,"biIssued":60,"available":240,"status":"AVAILABLE",
    "incomingQuantity":50,"expectedAvailabilityDate":"2026-09-03","purchaseOrderStatus":"PENDING",
    "createdAt":"2026-08-01T00:00:00.000Z","updatedAt":"2026-08-27T08:00:00.000Z","version":2
  }],
  "page": {"limit":50,"nextCursor":null,"hasMore":false},
  "meta": {"requestId":"8995e46e-32b1-4aa4-9740-8cd25966c877"}
}
```
- **Errors/validation/auth:** `404` factory; `400`; `401`.
- **Side effects/audit/inventory:** None.
- **Idempotency/retry:** Safe/idempotent.

#### `POST /factories/{factoryId}/materials`

- **Purpose:** Add a material to a factory ledger.
- **Auth/roles:** `ADMIN`, `SUPERADMIN`.
- **Parameters/headers/body:** UUID path; `Idempotency-Key`; JSON:

```json
{
  "id": "T-5836",
  "name": "Switch for trap - 52 kg",
  "total": 300,
  "biIssued": 60,
  "incomingQuantity": 50,
  "expectedAvailabilityDate": "2026-09-03",
  "purchaseOrderStatus": "PENDING"
}
```

- **Success:** `201 Created`, nested Location, complete Factory Material.

```json
{
  "data": {
    "id":"T-5836","name":"Switch for trap - 52 kg","total":300,"biIssued":60,"available":240,"status":"AVAILABLE",
    "incomingQuantity":50,"expectedAvailabilityDate":"2026-09-03","purchaseOrderStatus":"PENDING",
    "createdAt":"2026-08-27T10:15:30.123Z","updatedAt":"2026-08-27T10:15:30.123Z","version":1
  },
  "meta": {"requestId":"8995e46e-32b1-4aa4-9740-8cd25966c877"}
}
```
- **Errors/validation/auth:** `404` factory; unique material ID within factory; no generated fallback PL in production; nonnegative integer totals and `biIssued <= total`; PO rules; `409`; `422`; `401/403`.
- **Side effects/audit/inventory:** Creates factory balance and `FACTORY_MATERIAL_CREATED`; does not create/mutate depot inventory.
- **Idempotency/retry:** Required; replay safe.

#### `GET /factories/{factoryId}/materials/{materialId}`

- **Purpose:** Get one factory material.
- **Auth/roles:** Any authenticated role.
- **Parameters/headers/body:** UUID factory path and URL-encoded PL material path; no body.
- **Success:** `200 OK` complete Factory Material and ETag.

```json
{
  "data": {
    "id":"T-5836","name":"Switch for trap - 52 kg","total":300,"biIssued":60,"available":240,"status":"AVAILABLE",
    "incomingQuantity":50,"expectedAvailabilityDate":"2026-09-03","purchaseOrderStatus":"PENDING",
    "createdAt":"2026-08-01T00:00:00.000Z","updatedAt":"2026-08-27T08:00:00.000Z","version":2
  },
  "meta": {"requestId":"8995e46e-32b1-4aa4-9740-8cd25966c877"}
}
```
- **Errors/validation/auth:** `404` factory/material; `401`.
- **Side effects/audit/inventory:** None.
- **Idempotency/retry:** Safe/idempotent.

#### `PATCH /factories/{factoryId}/materials/{materialId}`

- **Purpose:** Edit factory material metadata and absolute balances/planning fields.
- **Auth/roles:** `ADMIN`, `SUPERADMIN`.
- **Parameters/headers/body:** paths; `If-Match`, `Idempotency-Key`; nonempty subset of `id`, `name`, `total`, `biIssued`, `incomingQuantity`, `expectedAvailabilityDate`, `purchaseOrderStatus`, plus `reason` for ID/balance change.

```json
{"total":320,"biIssued":60,"reason":"Verified factory stock count"}
```

- **Success:** `200 OK` complete Factory Material with incremented version.

```json
{
  "data": {
    "id":"T-5836","name":"Switch for trap - 52 kg","total":320,"biIssued":60,"available":260,"status":"AVAILABLE",
    "incomingQuantity":50,"expectedAvailabilityDate":"2026-09-03","purchaseOrderStatus":"PENDING",
    "createdAt":"2026-08-01T00:00:00.000Z","updatedAt":"2026-08-27T10:30:00.000Z","version":3
  },
  "meta": {"requestId":"8995e46e-32b1-4aa4-9740-8cd25966c877"}
}
```
- **Errors/validation/auth:** `404`; `409` nested ID collision; `412`; `422` negative values, `biIssued > total`, invalid PO state, absent reason; `401/403`.
- **Side effects/audit/inventory:** Updates only factory ledger; records `FACTORY_MATERIAL_BALANCE_ADJUSTED` or metadata update with before/after; no main inventory dual-write.
- **Idempotency/retry:** Required key/version; safe replay.

### 9.6 Material Requests

#### `GET /requests`

- **Purpose:** List material requests/history.
- **Auth/roles:** `VIEWER` own only; `ADMIN` and `SUPERADMIN` all.
- **Parameters/headers/body:** `status=PENDING|ACCEPTED|REJECTED`; `viewerId` only honored for admin+; `itemId`; `dateFrom/dateTo` RFC 3339; `q` over material/viewer snapshots; `sort=-createdAt|createdAt|status`; pagination. No body.
- **Success:** `200 OK` collection of complete Material Request objects. Viewer scope is forcibly current user regardless of query.

```json
{
  "data": [{
    "id":"f29552b0-f075-4c20-943a-23c8e02b8047","viewerId":"f49b7b8c-ddf4-4eec-b3fc-25cb2ad938a9",
    "viewerAccountId":"VW-2048","viewerName":"Depot Viewer","itemId":"T-5836","itemName":"Switch for trap - 52 kg",
    "quantity":5,"section":"DEPOT","status":"PENDING","decisionBy":null,"decisionAt":null,"history":[],
    "createdAt":"2026-08-27T10:15:30.123Z","updatedAt":"2026-08-27T10:15:30.123Z","version":1
  }],
  "page": {"limit":50,"nextCursor":null,"hasMore":false},
  "meta": {"requestId":"8995e46e-32b1-4aa4-9740-8cd25966c877"}
}
```
- **Errors/validation/auth:** `400`; `401`; a viewer supplying another `viewerId` gets `403`.
- **Side effects/audit/inventory:** None.
- **Idempotency/retry:** Safe/idempotent.

#### `POST /requests`

- **Purpose:** Create a depot material request.
- **Auth/roles:** `VIEWER` only, matching current UI.
- **Parameters/headers/body:** `Idempotency-Key`; JSON:

```json
{"itemId":"T-5836","quantity":5}
```

- **Success:** `201 Created`, Location, complete Material Request with server-derived viewer snapshots, `DEPOT`, `PENDING`, empty history.

```json
{
  "data": {
    "id":"f29552b0-f075-4c20-943a-23c8e02b8047","viewerId":"f49b7b8c-ddf4-4eec-b3fc-25cb2ad938a9",
    "viewerAccountId":"VW-2048","viewerName":"Depot Viewer","itemId":"T-5836","itemName":"Switch for trap - 52 kg",
    "quantity":5,"section":"DEPOT","status":"PENDING","decisionBy":null,"decisionAt":null,"history":[],
    "createdAt":"2026-08-27T10:15:30.123Z","updatedAt":"2026-08-27T10:15:30.123Z","version":1
  },
  "meta": {"requestId":"8995e46e-32b1-4aa4-9740-8cd25966c877"}
}
```
- **Errors/validation/auth:** positive integer; known depot item; quantity cannot exceed current available at submission; `409 INSUFFICIENT_STOCK`; `422`; `401/403`.
- **Side effects/audit/inventory:** Creates request and `MATERIAL_REQUEST_CREATED`; does not reserve or change stock. Availability is rechecked on accept.
- **Idempotency/retry:** Required; replay safe.

#### `GET /requests/{requestId}`

- **Purpose:** Retrieve a request and full append-only transition history.
- **Auth/roles:** Viewer only if owner; admin/superadmin all.
- **Parameters/headers/body:** UUID path; no body/query.
- **Success:** `200 OK` complete Material Request and ETag.

```json
{
  "data": {
    "id":"f29552b0-f075-4c20-943a-23c8e02b8047","viewerId":"f49b7b8c-ddf4-4eec-b3fc-25cb2ad938a9",
    "viewerAccountId":"VW-2048","viewerName":"Depot Viewer","itemId":"T-5836","itemName":"Switch for trap - 52 kg",
    "quantity":5,"section":"DEPOT","status":"PENDING","decisionBy":null,"decisionAt":null,"history":[],
    "createdAt":"2026-08-27T10:15:30.123Z","updatedAt":"2026-08-27T10:15:30.123Z","version":1
  },
  "meta": {"requestId":"8995e46e-32b1-4aa4-9740-8cd25966c877"}
}
```
- **Errors/validation/auth:** `404` for unknown or viewer non-owned resource to avoid disclosure; `401`.
- **Side effects/audit/inventory:** None.
- **Idempotency/retry:** Safe/idempotent.

#### `POST /requests/{requestId}/accept`

- **Purpose:** Accept a pending request and issue depot BI quantity.
- **Auth/roles:** `ADMIN`, `SUPERADMIN`.
- **Parameters/headers/body:** UUID; `Idempotency-Key`, `If-Match`; body `{}`.
- **Success:** `200 OK` complete request with `ACCEPTED`, actor UUID, timestamp, history entry `{status:"ACCEPTED", actor:{...}, at:...}`, new version.

```json
{
  "data": {
    "id":"f29552b0-f075-4c20-943a-23c8e02b8047","viewerId":"f49b7b8c-ddf4-4eec-b3fc-25cb2ad938a9",
    "viewerAccountId":"VW-2048","viewerName":"Depot Viewer","itemId":"T-5836","itemName":"Switch for trap - 52 kg",
    "quantity":5,"section":"DEPOT","status":"ACCEPTED","decisionBy":"f105dcb5-216c-4ff7-a589-9fef95eca25f",
    "decisionAt":"2026-08-27T10:20:00.000Z",
    "history":[{"status":"ACCEPTED","actor":{"id":"f105dcb5-216c-4ff7-a589-9fef95eca25f","accountId":"AD-2050","name":"Regional Administrator","role":"ADMIN"},"at":"2026-08-27T10:20:00.000Z"}],
    "createdAt":"2026-08-27T10:15:30.123Z","updatedAt":"2026-08-27T10:20:00.000Z","version":2
  },
  "meta": {"requestId":"8995e46e-32b1-4aa4-9740-8cd25966c877"}
}
```
- **Errors/validation/auth:** `404`; `409 INVALID_TRANSITION`; `409 INSUFFICIENT_STOCK` if availability changed; `412`; `401/403`.
- **Side effects/audit/inventory:** In one DB transaction with request/material row locks: verify pending and stock, increase depot `biIssued` by request quantity, update request/history, write `REQUEST_ACCEPTED` with before/after. Total quantity unchanged.
- **Idempotency/retry:** Required; replay returns original acceptance. Different key after acceptance returns `409`.

#### `POST /requests/{requestId}/reject`

- **Purpose:** Reject a pending request without stock change.
- **Auth/roles:** `ADMIN`, `SUPERADMIN`.
- **Parameters/headers/body:** UUID; `Idempotency-Key`, `If-Match`; optional reason:

```json
{"reason":"Request requires revised quantity."}
```

- **Success:** `200 OK` complete `REJECTED` request/history/version.

```json
{
  "data": {
    "id":"f29552b0-f075-4c20-943a-23c8e02b8047","viewerId":"f49b7b8c-ddf4-4eec-b3fc-25cb2ad938a9",
    "viewerAccountId":"VW-2048","viewerName":"Depot Viewer","itemId":"T-5836","itemName":"Switch for trap - 52 kg",
    "quantity":5,"section":"DEPOT","status":"REJECTED","decisionBy":"f105dcb5-216c-4ff7-a589-9fef95eca25f",
    "decisionAt":"2026-08-27T10:20:00.000Z",
    "history":[{"status":"REJECTED","actor":{"id":"f105dcb5-216c-4ff7-a589-9fef95eca25f","accountId":"AD-2050","name":"Regional Administrator","role":"ADMIN"},"at":"2026-08-27T10:20:00.000Z","reason":"Request requires revised quantity."}],
    "createdAt":"2026-08-27T10:15:30.123Z","updatedAt":"2026-08-27T10:20:00.000Z","version":2
  },
  "meta": {"requestId":"8995e46e-32b1-4aa4-9740-8cd25966c877"}
}
```
- **Errors/validation/auth:** reason max 500; `404`; `409 INVALID_TRANSITION`; `412`; `401/403`.
- **Side effects/audit/inventory:** Atomic state/history and `REQUEST_REJECTED`; no inventory effect.
- **Idempotency/retry:** Required; replay safe.

#### `POST /requests/{requestId}/undo`

- **Purpose:** Superadmin returns an accepted/rejected request to pending while retaining history.
- **Auth/roles:** `SUPERADMIN` only.
- **Parameters/headers/body:** UUID; `Idempotency-Key`, `If-Match`; reason required:

```json
{"reason":"Decision made against the wrong request."}
```

- **Success:** `200 OK` complete request with `PENDING`, null current decision fields, appended `UNDONE` history, incremented version.

```json
{
  "data": {
    "id":"f29552b0-f075-4c20-943a-23c8e02b8047","viewerId":"f49b7b8c-ddf4-4eec-b3fc-25cb2ad938a9",
    "viewerAccountId":"VW-2048","viewerName":"Depot Viewer","itemId":"T-5836","itemName":"Switch for trap - 52 kg",
    "quantity":5,"section":"DEPOT","status":"PENDING","decisionBy":null,"decisionAt":null,
    "history":[
      {"status":"ACCEPTED","actor":{"id":"f105dcb5-216c-4ff7-a589-9fef95eca25f","accountId":"AD-2050","name":"Regional Administrator","role":"ADMIN"},"at":"2026-08-27T10:20:00.000Z"},
      {"status":"UNDONE","actor":{"id":"9fae4a41-2b26-4b61-afd0-89dc358fab1d","accountId":"SA-2051","name":"Warehouse Superadmin","role":"SUPERADMIN"},"at":"2026-08-27T10:25:00.000Z","reason":"Decision made against the wrong request."}
    ],
    "createdAt":"2026-08-27T10:15:30.123Z","updatedAt":"2026-08-27T10:25:00.000Z","version":3
  },
  "meta": {"requestId":"8995e46e-32b1-4aa4-9740-8cd25966c877"}
}
```
- **Errors/validation/auth:** `404`; `409 INVALID_TRANSITION` if pending; `409 CONSISTENCY_CONFLICT` if accepted effect cannot be exactly reversed; `412`; reason `1..500`; `401/403`.
- **Side effects/audit/inventory:** Under locks, an accepted request decreases `biIssued` by exactly quantity; rejected request changes no stock. No clamp is allowed. Writes `REQUEST_UNDONE`, reason, previous decision.
- **Idempotency/retry:** Required; same key replay safe.

### 9.7 Files

#### File Contract Decisions

- `billFileId` and `proofFileId` are **always separate, independent fields**.
- There is no generic transaction `fileId`.
- `POST /files` accepts exactly multipart fields `file` and `purpose` where purpose is `BILL|PROOF`.
- Create/correct transaction requests are JSON and reference both pre-uploaded IDs.
- Accepted types: JPEG (`image/jpeg`), PNG (`image/png`), WebP (`image/webp`), PDF (`application/pdf`). MIME sniffing and extension validation must agree.
- **Assumption/recommendation:** configurable maximum 10 MiB (`10 * 1024 * 1024` bytes) per file.
- Files are private. The API streams through authorization checks or uses very short-lived signed redirects only after authorization.
- `photo`/`photoData` from legacy local records maps **only** to `proofFileId`, never Bill.
- No OCR endpoint is confirmed. OCR/document extraction is optional future work and must not block file or transaction creation.

#### `POST /files`

- **Purpose:** Upload one Bill or one Proof before transaction creation.
- **Auth/roles:** `ADMIN`, `SUPERADMIN`.
- **Parameters/headers/body:** `Idempotency-Key`; `multipart/form-data` with exactly `purpose` text and `file` binary. No JSON body/query.
- **Success:** `201 Created`, Location `/files/{fileId}`, complete File Metadata.

```json
{
  "data": {
    "id":"0ddbf6af-89db-49bf-a528-c8785622768d","purpose":"BILL","fileName":"supplier-bill.pdf",
    "contentType":"application/pdf","sizeBytes":482193,
    "sha256":"b5cfc9a6f04d28f339e5d5417bd649a7ed0ff02bf65d12c74f32e41f87d2b2ec","status":"READY",
    "createdBy":{"id":"f49b7b8c-ddf4-4eec-b3fc-25cb2ad938a9","accountId":"AD-2048","name":"Depot Operator"},
    "createdAt":"2026-08-27T10:10:00.000Z","referenced":false,"version":1
  },
  "meta": {"requestId":"8995e46e-32b1-4aa4-9740-8cd25966c877"}
}
```
- **Errors/validation/auth:** `400` malformed/missing duplicate fields; `413 FILE_TOO_LARGE`; `415` unsupported/sniff mismatch; `422` invalid purpose/empty file/unsafe filename; `401/403`; `503` scanner/storage unavailable. Server sanitizes filename and computes SHA-256.
- **Side effects/audit/inventory:** Stores private object and metadata owned by uploader; optional synchronous malware scan must reach `READY` before response, otherwise asynchronous status requires transaction rejection until ready. Writes `FILE_UPLOADED`; no inventory.
- **Idempotency/retry:** Required. Same key/content/purpose returns original metadata; changed content returns `409 IDEMPOTENCY_CONFLICT`.

Separate uploads are required:

```bash
curl --request POST "$BASE/api/v1/files" \
  --header "Authorization: Bearer $TOKEN" \
  --header "Idempotency-Key: 6184cb8f-a9ac-4cd0-ad0b-68e7382b38fd" \
  --form "purpose=BILL" \
  --form "file=@bill.pdf;type=application/pdf"

curl --request POST "$BASE/api/v1/files" \
  --header "Authorization: Bearer $TOKEN" \
  --header "Idempotency-Key: de67e7df-e42a-47ce-8660-c054fd39ec05" \
  --form "purpose=PROOF" \
  --form "file=@proof.jpg;type=image/jpeg"
```

#### `GET /files/{fileId}`

- **Purpose:** Retrieve file metadata, not bytes.
- **Auth/roles:** `ADMIN`, `SUPERADMIN`; uploader may inspect an unreferenced own upload. No viewer access.
- **Parameters/headers/body:** UUID path; no body/query.
- **Success:** `200 OK` complete File Metadata and ETag.

```json
{
  "data": {
    "id":"0ddbf6af-89db-49bf-a528-c8785622768d","purpose":"BILL","fileName":"supplier-bill.pdf",
    "contentType":"application/pdf","sizeBytes":482193,
    "sha256":"b5cfc9a6f04d28f339e5d5417bd649a7ed0ff02bf65d12c74f32e41f87d2b2ec","status":"READY",
    "createdBy":{"id":"f49b7b8c-ddf4-4eec-b3fc-25cb2ad938a9","accountId":"AD-2048","name":"Depot Operator"},
    "createdAt":"2026-08-27T10:10:00.000Z","referenced":true,"version":2
  },
  "meta": {"requestId":"8995e46e-32b1-4aa4-9740-8cd25966c877"}
}
```
- **Errors/validation/auth:** `404` unknown or unauthorized; `401`; `403` may be used for known role denial.
- **Side effects/audit/inventory:** Access log only.
- **Idempotency/retry:** Safe/idempotent.

#### `GET /files/{fileId}/content`

- **Purpose:** Download/preview original bytes.
- **Auth/roles:** `ADMIN`, `SUPERADMIN`, subject to same metadata access.
- **Parameters/headers/body:** UUID; optional standard `Range`; `Accept` compatible with content. No body.
- **Success:** `200 OK` bytes or `206 Partial Content`; headers include validated `Content-Type`, `Content-Length`, safe `Content-Disposition`, `ETag`, `X-Content-Type-Options: nosniff`, private no-store caching.

```http
HTTP/1.1 200 OK
Content-Type: application/pdf
Content-Length: 482193
Content-Disposition: inline; filename="supplier-bill.pdf"
ETag: "b5cfc9a6f04d28f339e5d5417bd649a7ed0ff02bf65d12c74f32e41f87d2b2ec"
Cache-Control: private, no-store
X-Content-Type-Options: nosniff
X-Request-Id: 8995e46e-32b1-4aa4-9740-8cd25966c877

<binary bytes>
```
- **Errors/validation/auth:** `404`; `401/403`; `416` invalid range; `503` storage unavailable.
- **Side effects/audit/inventory:** Records file access security event where policy requires; no stock.
- **Idempotency/retry:** Safe/idempotent; ranges may resume.

#### `DELETE /files/{fileId}`

- **Purpose:** Remove an uploaded file only while unreferenced.
- **Auth/roles:** Uploader if `ADMIN`/`SUPERADMIN`; superadmin may remove any unreferenced file.
- **Parameters/headers/body:** UUID; `If-Match` required; no body/query.
- **Success:** `204 No Content`. The response has no body.
- **Errors/validation/auth:** `404`; `409 FILE_IN_USE` if referenced by any transaction/audit retention record; `412`; `401/403`.
- **Side effects/audit/inventory:** Tombstones metadata, schedules object deletion, records `FILE_DELETED`; no inventory. Audit may retain filename/hash metadata but not downloadable content according to retention policy.
- **Idempotency/retry:** Repeated authorized delete SHOULD return `204` during tombstone retention; safe retry.

**Replacement/removal behavior:** Before transaction creation, upload replacement and delete the old unreferenced file. After creation, IDs are immutable through ordinary file APIs. A superadmin transaction correction may replace `billFileId` and/or `proofFileId` with newly pre-uploaded correctly purposed IDs, preserving old file metadata in audit and retention. Neither attachment may be set to null on an active transaction. Reversal does not delete files.

### 9.8 Incoming and Dispatch Transactions

#### Stock Direction

| Type | Scope | Authoritative effect for each positive `quantityChange` |
| --- | --- | --- |
| `INCOMING` | `DEPOT` | Depot `quantity += magnitude`; `biIssued` unchanged. |
| `DISPATCH` | `DEPOT` | Depot `biIssued += magnitude`; `quantity` unchanged, preserving current UI semantics. |
| `INCOMING` | `FACTORY` | Factory material `total += magnitude`; `biIssued` unchanged. |
| `DISPATCH` | `FACTORY` | Factory material `total -= magnitude`; `biIssued` unchanged. |

**Assumption/recommendation:** production replaces ambiguous `Sleeper` scope with `FACTORY`, and `factoryId` is mandatory. `factoryNameSnapshot` is response/audit-only. Generic Sleeper transactions without a factory are rejected. Factory operations never mutate depot/main inventory, even when a PL matches.

#### `GET /transactions`

- **Purpose:** List operational incoming/dispatch records and their correction/reversal state.
- **Auth/roles:** `ADMIN`, `SUPERADMIN`.
- **Parameters/headers/body:** `type=INCOMING|DISPATCH`; `scope=DEPOT|FACTORY`; `factoryId`; `materialId`; `createdBy`; `dateFrom/dateTo`; `reversed=true|false`; `q` over notes/person/truck/material snapshots; `sort=-createdAt|createdAt`; pagination. `factoryId` requires `scope=FACTORY`. No body.
- **Success:** `200 OK` collection of complete Transaction resources, newest first.

```json
{
  "data": [{
    "id":"71fa206b-bf16-469a-bf4f-5386851dd66e","type":"INCOMING","scope":"DEPOT","factoryId":null,"factoryNameSnapshot":null,
    "items":[{"materialId":"T-6902","materialNameSnapshot":"Improved SEJ -60 Kg (with 80 mm max: gap) B.G.60 kg (UIC) on PSC sleepers","quantityChange":25}],
    "notes":"Delivery against scheduled supply","person":"North Zone Supplier","comingFrom":"Delhi","dateOfArrival":"2026-08-27",
    "dateRequested":null,"dateLeaving":null,"truckNumber":"KA01AB1234",
    "billFileId":"0ddbf6af-89db-49bf-a528-c8785622768d","proofFileId":"467253ce-eb95-4347-b050-9f446f03f9dd",
    "billFile":{"id":"0ddbf6af-89db-49bf-a528-c8785622768d","purpose":"BILL","fileName":"supplier-bill.pdf","contentType":"application/pdf","sizeBytes":482193},
    "proofFile":{"id":"467253ce-eb95-4347-b050-9f446f03f9dd","purpose":"PROOF","fileName":"delivery.webp","contentType":"image/webp","sizeBytes":318200},
    "createdBy":{"id":"f49b7b8c-ddf4-4eec-b3fc-25cb2ad938a9","accountId":"AD-2048","name":"Depot Operator"},
    "createdAt":"2026-08-27T10:15:30.123Z","updatedAt":"2026-08-27T10:15:30.123Z","correctedAt":null,"reversedAt":null,"version":1
  }],
  "page": {"limit":50,"nextCursor":null,"hasMore":false},
  "meta": {"requestId":"8995e46e-32b1-4aa4-9740-8cd25966c877"}
}
```
- **Errors/validation/auth:** `400`; `401/403`.
- **Side effects/audit/inventory:** None.
- **Idempotency/retry:** Safe/idempotent.

#### `POST /transactions`

- **Purpose:** Create incoming or dispatch with two pre-uploaded independent files and apply stock atomically.
- **Auth/roles:** `ADMIN`, `SUPERADMIN`.
- **Parameters/headers/body:** `Idempotency-Key` required; JSON, never multipart. Common body:

```json
{
  "type": "INCOMING",
  "scope": "DEPOT",
  "factoryId": null,
  "items": [
    {"materialId":"T-6902","quantityChange":25}
  ],
  "notes": "Delivery against scheduled supply",
  "person": "North Zone Supplier",
  "comingFrom": "Delhi",
  "dateOfArrival": "2026-08-27",
  "dateRequested": null,
  "dateLeaving": null,
  "truckNumber": "KA01AB1234",
  "billFileId": "0ddbf6af-89db-49bf-a528-c8785622768d",
  "proofFileId": "467253ce-eb95-4347-b050-9f446f03f9dd"
}
```

- **Success:** `201 Created`, Location, complete Transaction including separate `billFile` and `proofFile` metadata. On creation, `createdAt` and `updatedAt` are the same server timestamp.

```json
{
  "data": {
    "id":"71fa206b-bf16-469a-bf4f-5386851dd66e","type":"INCOMING","scope":"DEPOT","factoryId":null,"factoryNameSnapshot":null,
    "items":[{"materialId":"T-6902","materialNameSnapshot":"Improved SEJ -60 Kg (with 80 mm max: gap) B.G.60 kg (UIC) on PSC sleepers","quantityChange":25}],
    "notes":"Delivery against scheduled supply","person":"North Zone Supplier","comingFrom":"Delhi","dateOfArrival":"2026-08-27",
    "dateRequested":null,"dateLeaving":null,"truckNumber":"KA01AB1234",
    "billFileId":"0ddbf6af-89db-49bf-a528-c8785622768d","proofFileId":"467253ce-eb95-4347-b050-9f446f03f9dd",
    "billFile":{"id":"0ddbf6af-89db-49bf-a528-c8785622768d","purpose":"BILL","fileName":"supplier-bill.pdf","contentType":"application/pdf","sizeBytes":482193},
    "proofFile":{"id":"467253ce-eb95-4347-b050-9f446f03f9dd","purpose":"PROOF","fileName":"delivery.webp","contentType":"image/webp","sizeBytes":318200},
    "createdBy":{"id":"f49b7b8c-ddf4-4eec-b3fc-25cb2ad938a9","accountId":"AD-2048","name":"Depot Operator"},
    "createdAt":"2026-08-27T10:15:30.123Z","updatedAt":"2026-08-27T10:15:30.123Z","correctedAt":null,"reversedAt":null,"version":1
  },
  "meta": {"requestId":"8995e46e-32b1-4aa4-9740-8cd25966c877"}
}
```
- **Errors/validation/auth:** `422` field rules below; `404` factory/material/file; `409 INSUFFICIENT_STOCK`; `409 FILE_IN_USE`; `409` duplicate material ID in items; `401/403`; `503` dependency failure. Both file IDs required, distinct, `READY`, owned by actor, unreferenced, and purpose-matched (`BILL` vs `PROOF`).
- **Side effects/audit/inventory:** Row-lock all materials in stable order; validate all; apply all balances, create transaction and immutable item/name/factory snapshots, attach both files, write `TRANSACTION_CREATED` with separate metadata, commit once. Any failure rolls back everything.
- **Idempotency/retry:** Required. Unknown network result must be retried with same key. Replay returns original transaction and does not reapply stock.

Incoming-specific validation:

- `person`, `comingFrom`, `dateOfArrival`, `truckNumber` required.
- `dateRequested` and `dateLeaving` MUST be null/omitted.
- `dateOfArrival` is date-only; allowed operational range is configurable, recommended one year past through five years future.

Dispatch JSON example:

```json
{
  "type": "DISPATCH",
  "scope": "FACTORY",
  "factoryId": "740d19ed-dbe1-40c0-82f1-cf258ac93f53",
  "items": [
    {"materialId":"T-5836","quantityChange":10}
  ],
  "notes": "Dispatch to track renewal site",
  "person": "South Section Engineering Team",
  "comingFrom": null,
  "dateOfArrival": null,
  "dateRequested": "2026-08-26",
  "dateLeaving": "2026-08-27",
  "truckNumber": "KA02CD5678",
  "billFileId": "53a7795e-c2ca-41fb-993f-c81f2308b2df",
  "proofFileId": "a914e8a2-58aa-44df-80a3-83d66c1a8978"
}
```

Dispatch-specific validation:

- `person` means **requested by** and is required.
- `dateRequested`, `dateLeaving`, and `truckNumber` required; `dateLeaving >= dateRequested`.
- `comingFrom` and `dateOfArrival` MUST be null/omitted.
- Every material must have sufficient authoritative `available` at lock time. Negative balances are rejected, never clamped.

Common validation:

- `items` has `1..100` unique materials; each magnitude integer `1..2147483647`.
- `scope=DEPOT` requires `factoryId: null`; `scope=FACTORY` requires an existing `factoryId`.
- Material must belong to the selected authoritative ledger.
- `notes` optional max 2000; logistics text fields trimmed `1..200`; truck number `1..32`, canonical uppercase while allowing letters, digits, spaces, and `-`.
- `createdBy`, `createdAt`, and `updatedAt` are server generated; clients MUST NOT send `user`, actor, `timestamp`, creation/update timestamps, names, signed quantities, or status. Creation sets `updatedAt = createdAt`; correction or reversal advances `updatedAt` to that operation's server timestamp.

#### `GET /transactions/{transactionId}`

- **Purpose:** Get one transaction with files and correction/reversal links.
- **Auth/roles:** `ADMIN`, `SUPERADMIN`.
- **Parameters/headers/body:** UUID; no body/query.
- **Success:** `200 OK` complete Transaction, including `corrections` summary and `reversal` summary when present, ETag.

```json
{
  "data": {
    "id":"71fa206b-bf16-469a-bf4f-5386851dd66e","type":"INCOMING","scope":"DEPOT","factoryId":null,"factoryNameSnapshot":null,
    "items":[{"materialId":"T-6902","materialNameSnapshot":"Improved SEJ -60 Kg (with 80 mm max: gap) B.G.60 kg (UIC) on PSC sleepers","quantityChange":25}],
    "notes":"Delivery against scheduled supply","person":"North Zone Supplier","comingFrom":"Delhi","dateOfArrival":"2026-08-27",
    "dateRequested":null,"dateLeaving":null,"truckNumber":"KA01AB1234",
    "billFileId":"0ddbf6af-89db-49bf-a528-c8785622768d","proofFileId":"467253ce-eb95-4347-b050-9f446f03f9dd",
    "billFile":{"id":"0ddbf6af-89db-49bf-a528-c8785622768d","purpose":"BILL","fileName":"supplier-bill.pdf","contentType":"application/pdf","sizeBytes":482193},
    "proofFile":{"id":"467253ce-eb95-4347-b050-9f446f03f9dd","purpose":"PROOF","fileName":"delivery.webp","contentType":"image/webp","sizeBytes":318200},
    "createdBy":{"id":"f49b7b8c-ddf4-4eec-b3fc-25cb2ad938a9","accountId":"AD-2048","name":"Depot Operator"},
    "createdAt":"2026-08-27T10:15:30.123Z","updatedAt":"2026-08-27T10:15:30.123Z","correctedAt":null,"reversedAt":null,
    "corrections":[],"reversal":null,"version":1
  },
  "meta": {"requestId":"8995e46e-32b1-4aa4-9740-8cd25966c877"}
}
```
- **Errors/validation/auth:** `404`; `401/403`.
- **Side effects/audit/inventory:** None.
- **Idempotency/retry:** Safe/idempotent.

#### `PATCH /transactions/{transactionId}`

- **Purpose:** Superadmin correction by reversing the current effective values and applying corrected values atomically; original record remains auditable.
- **Auth/roles:** `SUPERADMIN` only.
- **Parameters/headers/body:** UUID; `If-Match`, `Idempotency-Key`. Full replacement of correctable fields is recommended to avoid ambiguity:

```json
{
  "items": [{"materialId":"T-6902","quantityChange":30}],
  "notes": "Corrected quantity after bill verification",
  "person": "North Zone Supplier",
  "comingFrom": "Delhi",
  "dateOfArrival": "2026-08-27",
  "dateRequested": null,
  "dateLeaving": null,
  "truckNumber": "KA01AB1234",
  "billFileId": "59dafaa6-1b86-48fd-a274-c8bf72a9e7cb",
  "proofFileId": "467253ce-eb95-4347-b050-9f446f03f9dd",
  "reason": "Bill confirms 30 pieces rather than 25."
}
```

- **Success:** `200 OK` complete updated Transaction, incremented version, `correctedAt`, advanced `updatedAt`, and correction audit reference.

```json
{
  "data": {
    "id":"71fa206b-bf16-469a-bf4f-5386851dd66e","type":"INCOMING","scope":"DEPOT","factoryId":null,"factoryNameSnapshot":null,
    "items":[{"materialId":"T-6902","materialNameSnapshot":"Improved SEJ -60 Kg (with 80 mm max: gap) B.G.60 kg (UIC) on PSC sleepers","quantityChange":30}],
    "notes":"Corrected quantity after bill verification","person":"North Zone Supplier","comingFrom":"Delhi","dateOfArrival":"2026-08-27",
    "dateRequested":null,"dateLeaving":null,"truckNumber":"KA01AB1234",
    "billFileId":"59dafaa6-1b86-48fd-a274-c8bf72a9e7cb","proofFileId":"467253ce-eb95-4347-b050-9f446f03f9dd",
    "billFile":{"id":"59dafaa6-1b86-48fd-a274-c8bf72a9e7cb","purpose":"BILL","fileName":"corrected-bill.pdf","contentType":"application/pdf","sizeBytes":490100},
    "proofFile":{"id":"467253ce-eb95-4347-b050-9f446f03f9dd","purpose":"PROOF","fileName":"delivery.webp","contentType":"image/webp","sizeBytes":318200},
    "createdBy":{"id":"f49b7b8c-ddf4-4eec-b3fc-25cb2ad938a9","accountId":"AD-2048","name":"Depot Operator"},
    "createdAt":"2026-08-27T10:15:30.123Z","updatedAt":"2026-08-27T11:00:00.000Z","correctedAt":"2026-08-27T11:00:00.000Z","reversedAt":null,
    "corrections":[{"auditLogId":"ce144591-049b-4586-b69a-ee95ee0bc558","correctedAt":"2026-08-27T11:00:00.000Z","correctedBy":"9fae4a41-2b26-4b61-afd0-89dc358fab1d","reason":"Bill confirms 30 pieces rather than 25."}],
    "reversal":null,"version":2
  },
  "meta": {"requestId":"8995e46e-32b1-4aa4-9740-8cd25966c877"}
}
```
- **Errors/validation/auth:** `404`; `409` reversed transaction; `409 INSUFFICIENT_STOCK` or consistency conflict after reverse/reapply simulation; `409 FILE_IN_USE/purpose mismatch`; `412`; `422` transaction/logistics/file/reason rules; `401/403`.
- **Side effects/audit/inventory:** Lock transaction/materials/files; compute exact delta between old effective and corrected values; reject any negative result; update balances and transaction; attach replacements; preserve old values/file metadata in immutable `TRANSACTION_CORRECTED` audit. Scope/type/factory/created actor/time are immutable in v1.
- **Idempotency/retry:** Required key/version; replay safe. Concurrent correction gets `412`.

#### `POST /transactions/{transactionId}/reverse`

- **Purpose:** **Proposed safer superadmin alternative** to hard deletion: neutralize the transaction while preserving history.
- **Auth/roles:** `SUPERADMIN` only.
- **Parameters/headers/body:** UUID; `If-Match`, `Idempotency-Key`; reason required:

```json
{"reason":"Duplicate transaction entered after a network retry."}
```

- **Success:** `200 OK` complete Transaction with `reversedAt`, advanced `updatedAt`, `reversedBy`, `reversalReason`, and incremented version; original item/file data remains.

```json
{
  "data": {
    "id":"71fa206b-bf16-469a-bf4f-5386851dd66e","type":"INCOMING","scope":"DEPOT","factoryId":null,"factoryNameSnapshot":null,
    "items":[{"materialId":"T-6902","materialNameSnapshot":"Improved SEJ -60 Kg (with 80 mm max: gap) B.G.60 kg (UIC) on PSC sleepers","quantityChange":25}],
    "notes":"Delivery against scheduled supply","person":"North Zone Supplier","comingFrom":"Delhi","dateOfArrival":"2026-08-27",
    "dateRequested":null,"dateLeaving":null,"truckNumber":"KA01AB1234",
    "billFileId":"0ddbf6af-89db-49bf-a528-c8785622768d","proofFileId":"467253ce-eb95-4347-b050-9f446f03f9dd",
    "billFile":{"id":"0ddbf6af-89db-49bf-a528-c8785622768d","purpose":"BILL","fileName":"supplier-bill.pdf","contentType":"application/pdf","sizeBytes":482193},
    "proofFile":{"id":"467253ce-eb95-4347-b050-9f446f03f9dd","purpose":"PROOF","fileName":"delivery.webp","contentType":"image/webp","sizeBytes":318200},
    "createdBy":{"id":"f49b7b8c-ddf4-4eec-b3fc-25cb2ad938a9","accountId":"AD-2048","name":"Depot Operator"},
    "createdAt":"2026-08-27T10:15:30.123Z","updatedAt":"2026-08-27T11:10:00.000Z","correctedAt":null,"reversedAt":"2026-08-27T11:10:00.000Z",
    "reversedBy":{"id":"9fae4a41-2b26-4b61-afd0-89dc358fab1d","accountId":"SA-2051","name":"Warehouse Superadmin"},
    "reversalReason":"Duplicate transaction entered after a network retry.","corrections":[],
    "reversal":{"auditLogId":"281ddfb4-b2ea-467f-8dc0-5811e86ebfe1","reversedAt":"2026-08-27T11:10:00.000Z"},"version":2
  },
  "meta": {"requestId":"8995e46e-32b1-4aa4-9740-8cd25966c877"}
}
```
- **Errors/validation/auth:** `404`; `409 INVALID_TRANSITION` if already reversed; `409 CONSISTENCY_CONFLICT` if reversal would make any authoritative balance invalid, including undoing incoming stock that has since been consumed; `412`; `422` reason; `401/403`.
- **Side effects/audit/inventory:** Under locks, exactly invert current corrected effect; reject rather than clamp; mark reversed and write `TRANSACTION_REVERSED` with before/after and separate Bill/Proof metadata. Files remain referenced under retention policy.
- **Idempotency/retry:** Required; exact replay safe. There is deliberately no hard `DELETE /transactions/{id}` endpoint.

### 9.9 Audit Logs

#### `GET /logs`

- **Purpose:** Query immutable business audit events, including request, account, inventory, factory, file, and transaction changes.
- **Auth/roles:** `ADMIN` sees operational inventory/request/transaction/file events but not account/user/security events; `SUPERADMIN` sees all business events. `VIEWER` denied.
- **Parameters/headers/body:** `eventType`; `entityType`; `entityId`; `actorId`; `scope`; `factoryId`; `materialId`; `dateFrom/dateTo`; `q` over reason/snapshots; `sort=-occurredAt|occurredAt`; pagination. No body.
- **Success:** `200 OK` collection of complete Audit Log resources. Unauthorized event categories are excluded server-side, never client-filtered.

```json
{
  "data": [{
    "id":"255bb70b-1159-4d80-8314-6d65f4dff475","eventType":"TRANSACTION_CORRECTED","entityType":"TRANSACTION",
    "entityId":"71fa206b-bf16-469a-bf4f-5386851dd66e",
    "actor":{"id":"9fae4a41-2b26-4b61-afd0-89dc358fab1d","accountId":"SA-2051","name":"Warehouse Superadmin","role":"SUPERADMIN"},
    "occurredAt":"2026-08-27T11:00:00.000Z","requestId":"8995e46e-32b1-4aa4-9740-8cd25966c877",
    "reason":"Bill confirms 30 pieces rather than 25.",
    "before":{"quantityChange":25,"billFileId":"0ddbf6af-89db-49bf-a528-c8785622768d","proofFileId":"467253ce-eb95-4347-b050-9f446f03f9dd"},
    "after":{"quantityChange":30,"billFileId":"59dafaa6-1b86-48fd-a274-c8bf72a9e7cb","proofFileId":"467253ce-eb95-4347-b050-9f446f03f9dd"},
    "billFile":{"id":"59dafaa6-1b86-48fd-a274-c8bf72a9e7cb","purpose":"BILL","fileName":"corrected-bill.pdf"},
    "proofFile":{"id":"467253ce-eb95-4347-b050-9f446f03f9dd","purpose":"PROOF","fileName":"delivery.webp"}
  }],
  "page": {"limit":50,"nextCursor":null,"hasMore":false},
  "meta": {"requestId":"8995e46e-32b1-4aa4-9740-8cd25966c877"}
}
```
- **Errors/validation/auth:** `400`; `401/403`.
- **Side effects/audit/inventory:** No business mutation; administrative audit reads SHOULD produce separate security access logs to avoid recursive business records.
- **Idempotency/retry:** Safe/idempotent.

#### `GET /logs/{logId}`

- **Purpose:** Retrieve one immutable audit event with complete permitted before/after and file metadata.
- **Auth/roles:** `ADMIN` if event category is operational; `SUPERADMIN` all business events; viewer denied.
- **Parameters/headers/body:** UUID; no body/query.
- **Success:** `200 OK` complete Audit Log.

```json
{
  "data": {
    "id":"255bb70b-1159-4d80-8314-6d65f4dff475","eventType":"TRANSACTION_CREATED","entityType":"TRANSACTION",
    "entityId":"71fa206b-bf16-469a-bf4f-5386851dd66e",
    "actor":{"id":"f49b7b8c-ddf4-4eec-b3fc-25cb2ad938a9","accountId":"AD-2048","name":"Depot Operator","role":"ADMIN"},
    "occurredAt":"2026-08-27T10:15:30.123Z","requestId":"8995e46e-32b1-4aa4-9740-8cd25966c877","reason":null,
    "before":null,
    "after":{"type":"INCOMING","scope":"DEPOT","billFileId":"0ddbf6af-89db-49bf-a528-c8785622768d","proofFileId":"467253ce-eb95-4347-b050-9f446f03f9dd"},
    "billFile":{"id":"0ddbf6af-89db-49bf-a528-c8785622768d","purpose":"BILL","fileName":"supplier-bill.pdf"},
    "proofFile":{"id":"467253ce-eb95-4347-b050-9f446f03f9dd","purpose":"PROOF","fileName":"delivery.webp"}
  },
  "meta": {"requestId":"8995e46e-32b1-4aa4-9740-8cd25966c877"}
}
```
- **Errors/validation/auth:** `404` unknown or category concealed from admin; `401/403`.
- **Side effects/audit/inventory:** Security access log only.
- **Idempotency/retry:** Safe/idempotent.

## 10. Validation and Business Rules

### 10.1 Numeric and Stock Rules

- All quantities are integers; decimals, numeric strings, booleans, NaN, and signed transaction magnitudes are rejected.
- Inventory `quantity`, factory `total`, `biIssued`, and incoming quantities are nonnegative.
- Production MUST enforce `biIssued <= quantity` and `biIssued <= total`.
- **Current local Flutter conflict:** manual editing permits `biIssued > total`, then derives available with `max(..., 0)`. Production recommends disallowing this inconsistent state.
- Negative inventory is rejected atomically. Production MUST NOT clamp to zero.
- Derived `available` and `status` are never accepted in mutation bodies.
- Request creation does not reserve stock. Request acceptance and dispatch revalidate under lock.
- Depot dispatch follows current semantics by increasing `biIssued`, not decreasing total on hand. This should be confirmed against accounting terminology.

### 10.2 Purchase Order Rules

| `purchaseOrderStatus` | Required state |
| --- | --- |
| `NONE` | `incomingQuantity = 0`, `expectedAvailabilityDate = null`. |
| `PENDING` | `incomingQuantity > 0`; expected date MAY be null if unknown. |
| `ORDERED` | `incomingQuantity > 0`; expected date required. |

Flutter display labels map as follows:

| Flutter label/name | API enum |
| --- | --- |
| `No Incoming Order` / `none` | `NONE` |
| `Purchase Order Pending` / `pending` | `PENDING` |
| `Ordered / Awaiting Delivery` / `ordered` | `ORDERED` |

### 10.3 Account Rules

- Account request approval, duplicate check, and user creation are server-side and atomic.
- Passwords never appear in account request list/detail/decision responses, user resources, audit, traces, or logs.
- Public duplicate errors should not reveal whether an account already exists.
- Recommended production password policy is stronger than current four-character client minimum and requires product confirmation before frontend rollout.
- Requested role may only be `VIEWER` or `ADMIN`; anonymous users can never request `SUPERADMIN`.

### 10.4 Transaction Logistics

| Type | `person` contextual meaning | Required fields | Forbidden fields |
| --- | --- | --- | --- |
| `INCOMING` | Person/vendor who sent the order. | `person`, `comingFrom`, `dateOfArrival`, `truckNumber`, both file IDs. | `dateRequested`, `dateLeaving`. |
| `DISPATCH` | Person/team that requested the goods. | `person`, `dateRequested`, `dateLeaving`, `truckNumber`, both file IDs. | `comingFrom`, `dateOfArrival`. |

Both new `INCOMING` and `DISPATCH` require Bill **and** Proof, matching current Flutter behavior.

## 11. Consistency and Transactions

- Every mutation that changes inventory and another resource MUST execute in one PostgreSQL transaction.
- Material rows are locked in canonical `(ledger type, factoryId, material internal key)` order to reduce deadlocks.
- Request accept/undo locks request then material. Account approval locks request and uniqueness key. Transaction correction/reversal locks transaction then all affected materials/files.
- Unique indexes enforce normalized material/account/factory identifiers.
- Audit rows are inserted in the same database commit as business changes. Object upload occurs before reference; transaction creation only references `READY` metadata.
- If audit insertion fails, the business mutation fails.
- No partial item batch succeeds. An error on one item rolls back all items/files references.
- Database retries for serialization/deadlock must remain within the idempotency boundary.
- Outbox events MAY be written atomically for future notifications, but no WebSocket endpoint is contracted because the client has no support.

## 12. Audit and Retention

- Business audit is append-only. Application roles cannot update/delete audit records.
- Events include actor, actor role, request correlation ID, entity, timestamp, reason, before/after, scope, and relevant snapshots.
- Transaction events include distinct `billFile` and `proofFile` metadata.
- Sensitive values such as passwords, tokens, authorization headers, raw file bytes, and object-store signed URLs MUST be redacted.
- Recommended retention requiring confirmation: business audit and transaction metadata seven years; security logs one year; rejected account request PII one year; unreferenced files seven days; referenced files aligned to transaction retention.
- Database-level restricted permissions and optional cryptographic hash chaining/WORM export are recommended for tamper evidence.
- Clock synchronization via NTP is required; server timestamps are authoritative.

## 13. Security

- TLS 1.2 minimum, TLS 1.3 preferred; HSTS in production.
- Explicit CORS allowlist; never wildcard origins with credentials.
- JWT signing keys managed by KMS/secret manager and rotated by `kid`.
- Refresh tokens stored hashed; access JWTs never persisted in application logs.
- Argon2id password hashing and constant-time verification.
- Login/account-request rate limits by IP and normalized account key; progressive delay and monitoring.
- Authorization enforced at controller/service and query scope, not only routes/UI.
- MIME sniffing, malware scanning, filename sanitization, object encryption, private buckets, and download authorization for files.
- SQL parameterization and strict schema validation.
- Generic public auth/account errors prevent user enumeration.
- Security headers include `X-Content-Type-Options: nosniff`, appropriate CSP for any browser host, and `Cache-Control: no-store` for tokens/files.
- Backups encrypted and restore-tested. Database and object-store retention must remain consistent.
- Service logs MUST not contain transaction file content or password/token fields.
- No confirmed OCR endpoint exists; future OCR must be isolated, access-controlled, audited, and opt-in.

## 14. Concurrency and Optimistic Locking

- Every mutable aggregate exposes integer `version` and ETag.
- `PATCH` and state-transition actions require `If-Match` to prevent lost updates.
- Missing `If-Match` on those endpoints returns `428 PRECONDITION_REQUIRED` with code `PRECONDITION_REQUIRED` (an additional global error status).
- Stale ETag returns `412 VERSION_CONFLICT` and current ETag where disclosure is allowed.
- Stock checks and updates use database row locks; ETags alone are insufficient for balances.
- Idempotency prevents duplicated side effects; optimistic locking prevents overwriting another legitimate change. Both are required where specified.
- Clients receiving `412` must reload, show current state, and require deliberate resubmission rather than silently retrying.
- Deadlock/serialization exhaustion returns retryable `503`; use same idempotency key.

## 15. Flutter to API Field Mapping

| Flutter/local field | Proposed API field | Mapping/notes |
| --- | --- | --- |
| `TransactionLog.timestamp` | `createdAt` | Server timestamp; client does not submit it. |
| `TransactionLog.user` | `createdBy` | Server derives actor object from token. |
| `person` on incoming | `person` | Sender/vendor/person who sent order. |
| `person` on dispatch | `person` | Requested-by person/team. |
| `bill` / `billData` | `billFileId` | Upload separately with purpose `BILL`; no base64 JSON. |
| `proof` / `proofData` | `proofFileId` | Upload separately with purpose `PROOF`. |
| legacy `photo` / `photoData` | `proofFileId` only | Never infer or populate Bill. Migration may create a PROOF file object. |
| `factoryName` request | `factoryId` | Required input for factory scope. |
| `factoryName` response | `factoryNameSnapshot` | Server snapshot for historical display only. |
| `FactoryMaterial.total` | `total` | Stays `total`; do not map to depot `quantity`. |
| `CartItem.id` | `items[].materialId` | Material name is server snapshot, not accepted input. |
| `CartItem.name` | `items[].materialNameSnapshot` | Server-resolved response/audit field. |
| `quantityChange` | `quantityChange` | Positive magnitude only; type/scope defines direction. |
| `InventorySection.depot` | `DEPOT` | Depot ledger/scope. |
| `InventorySection.sleeper` transaction | `FACTORY` + `factoryId` | Generic Sleeper without factory rejected. |
| `InventorySection.both` | `BOTH` | Inventory catalog membership only, not transaction scope. |
| PO label `No Incoming Order` | `NONE` | Enum normalization. |
| PO label `Purchase Order Pending` | `PENDING` | Enum normalization. |
| PO label `Ordered / Awaiting Delivery` | `ORDERED` | Enum normalization. |
| request `Pending/Accepted/Rejected` | `PENDING/ACCEPTED/REJECTED` | API enum case normalization. |
| decision role string | `decisionBy` actor UUID plus history actor snapshot | Do not trust client role. |

## 16. Dart Flutter Examples

These are illustrative snippets. They use conceptual `package:http/http.dart` and secure-storage interfaces and do not modify or assert the repository's dependencies.

### 16.1 Shared Helpers and Error Parsing

```dart
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

class ApiException implements Exception {
  ApiException(this.status, this.code, this.message, this.details,
      {required this.retryable});
  final int status;
  final String code;
  final String message;
  final List<dynamic> details;
  final bool retryable;

  factory ApiException.fromResponse(http.Response response) {
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final error = body['error'] as Map<String, dynamic>? ?? const {};
    return ApiException(
      response.statusCode,
      error['code'] as String? ?? 'UNKNOWN_ERROR',
      error['message'] as String? ?? 'Request failed.',
      error['details'] as List<dynamic>? ?? const [],
      retryable: error['retryable'] as bool? ?? false,
    );
  }

  @override
  String toString() => '$code: $message';
}

Map<String, dynamic> decodeData(http.Response response) {
  if (response.statusCode < 200 || response.statusCode >= 300) {
    throw ApiException.fromResponse(response);
  }
  return (jsonDecode(response.body) as Map<String, dynamic>)['data']
      as Map<String, dynamic>;
}
```

### 16.2 Login

```dart
Future<Map<String, dynamic>> login(
  http.Client client,
  Uri baseUrl,
  String username,
  String password,
) async {
  final response = await client.post(
    baseUrl.resolve('auth/login'),
    headers: const {
      'Accept': 'application/json',
      'Content-Type': 'application/json',
    },
    body: jsonEncode({'username': username, 'password': password}),
  );
  final data = decodeData(response);
  // Store refreshToken in OS-backed secure storage; keep accessToken in memory.
  return data;
}
```

### 16.3 Illustrative Automatic Refresh

```dart
abstract interface class TokenStore {
  Future<String?> readRefreshToken();
  Future<void> writeRefreshToken(String value);
  Future<void> clear();
}

class RefreshingApiClient {
  RefreshingApiClient(this.httpClient, this.baseUrl, this.tokenStore);

  final http.Client httpClient;
  final Uri baseUrl;
  final TokenStore tokenStore;
  String? accessToken;
  Future<void>? _refreshInFlight;

  Future<http.Response> get(Uri uri) => _send('GET', uri);

  Future<http.Response> _send(String method, Uri uri) async {
    Future<http.Response> attempt() {
      final request = http.Request(method, uri)
        ..headers['Accept'] = 'application/json';
      if (accessToken != null) {
        request.headers['Authorization'] = 'Bearer $accessToken';
      }
      return httpClient.send(request).then(http.Response.fromStream);
    }

    var response = await attempt();
    if (response.statusCode != 401 || !_isExpired(response)) return response;
    await _refreshOnce();
    response = await attempt(); // Retry at most once.
    return response;
  }

  bool _isExpired(http.Response response) {
    try {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      return (body['error'] as Map<String, dynamic>)['code'] == 'TOKEN_EXPIRED';
    } catch (_) {
      return false;
    }
  }

  Future<void> _refreshOnce() async {
    final existing = _refreshInFlight;
    if (existing != null) return existing;
    final future = _refresh();
    _refreshInFlight = future;
    try {
      await future;
    } finally {
      _refreshInFlight = null;
    }
  }

  Future<void> _refresh() async {
    final refreshToken = await tokenStore.readRefreshToken();
    if (refreshToken == null) throw StateError('Login required.');
    final response = await httpClient.post(
      baseUrl.resolve('auth/refresh'),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({'refreshToken': refreshToken}),
    );
    if (response.statusCode != 200) {
      await tokenStore.clear();
      throw ApiException.fromResponse(response);
    }
    final data = decodeData(response);
    accessToken = data['accessToken'] as String;
    await tokenStore.writeRefreshToken(data['refreshToken'] as String);
  }
}
```

Production code should use a tested request abstraction, coordinate concurrent refreshes, avoid retrying streamed bodies automatically, and retain the same idempotency key for mutation retries.

### 16.4 Inventory Search

```dart
Future<List<dynamic>> searchInventory(
  http.Client client,
  Uri baseUrl,
  String token,
  String query,
) async {
  final uri = baseUrl.resolve('inventory').replace(queryParameters: {
    'q': query,
    'status': 'AVAILABLE',
    'sort': 'name',
    'limit': '20',
  });
  final response = await client.get(uri, headers: {
    'Accept': 'application/json',
    'Authorization': 'Bearer $token',
  });
  if (response.statusCode != 200) throw ApiException.fromResponse(response);
  return (jsonDecode(response.body) as Map<String, dynamic>)['data'] as List;
}
```

### 16.5 Create Material Request

```dart
Future<Map<String, dynamic>> createMaterialRequest(
  http.Client client,
  Uri baseUrl,
  String token,
  String idempotencyKey,
) async {
  final response = await client.post(
    baseUrl.resolve('requests'),
    headers: {
      'Accept': 'application/json',
      'Authorization': 'Bearer $token',
      'Content-Type': 'application/json',
      'Idempotency-Key': idempotencyKey,
    },
    body: jsonEncode({'itemId': 'T-5836', 'quantity': 5}),
  );
  return decodeData(response);
}
```

### 16.6 Approve Material Request

```dart
Future<Map<String, dynamic>> acceptMaterialRequest(
  http.Client client,
  Uri baseUrl,
  String token,
  String requestId,
  int version,
  String idempotencyKey,
) async {
  final response = await client.post(
    baseUrl.resolve('requests/$requestId/accept'),
    headers: {
      'Accept': 'application/json',
      'Authorization': 'Bearer $token',
      'Content-Type': 'application/json',
      'Idempotency-Key': idempotencyKey,
      'If-Match': '"$version"',
    },
    body: '{}',
  );
  return decodeData(response);
}
```

### 16.7 Upload Bill and Proof Separately

```dart
Future<Map<String, dynamic>> uploadFile(
  http.Client client,
  Uri baseUrl,
  String token, {
  required String purpose, // BILL or PROOF
  required File file,
  required String idempotencyKey,
}) async {
  final request = http.MultipartRequest('POST', baseUrl.resolve('files'))
    ..headers['Accept'] = 'application/json'
    ..headers['Authorization'] = 'Bearer $token'
    ..headers['Idempotency-Key'] = idempotencyKey
    ..fields['purpose'] = purpose
    ..files.add(await http.MultipartFile.fromPath('file', file.path));
  final streamed = await client.send(request);
  final response = await http.Response.fromStream(streamed);
  return decodeData(response);
}

Future<({String billFileId, String proofFileId})> uploadAttachments(
  http.Client client,
  Uri baseUrl,
  String token,
  File bill,
  File proof,
) async {
  final billData = await uploadFile(
    client,
    baseUrl,
    token,
    purpose: 'BILL',
    file: bill,
    idempotencyKey: '<new-uuid-for-bill>',
  );
  final proofData = await uploadFile(
    client,
    baseUrl,
    token,
    purpose: 'PROOF',
    file: proof,
    idempotencyKey: '<new-uuid-for-proof>',
  );
  return (
    billFileId: billData['id'] as String,
    proofFileId: proofData['id'] as String,
  );
}
```

### 16.8 Create Incoming with Both IDs

```dart
Future<Map<String, dynamic>> createIncoming(
  http.Client client,
  Uri baseUrl,
  String token, {
  required String billFileId,
  required String proofFileId,
  required String idempotencyKey,
}) async {
  final response = await client.post(
    baseUrl.resolve('transactions'),
    headers: {
      'Accept': 'application/json',
      'Authorization': 'Bearer $token',
      'Content-Type': 'application/json',
      'Idempotency-Key': idempotencyKey,
    },
    body: jsonEncode({
      'type': 'INCOMING',
      'scope': 'DEPOT',
      'factoryId': null,
      'items': [
        {'materialId': 'T-6902', 'quantityChange': 25}
      ],
      'notes': 'Delivery against scheduled supply',
      'person': 'North Zone Supplier',
      'comingFrom': 'Delhi',
      'dateOfArrival': '2026-08-27',
      'dateRequested': null,
      'dateLeaving': null,
      'truckNumber': 'KA01AB1234',
      'billFileId': billFileId,
      'proofFileId': proofFileId,
    }),
  );
  return decodeData(response);
}
```

### 16.9 Create Dispatch with Both IDs

```dart
Future<Map<String, dynamic>> createDispatch(
  http.Client client,
  Uri baseUrl,
  String token, {
  required String factoryId,
  required String billFileId,
  required String proofFileId,
  required String idempotencyKey,
}) async {
  final response = await client.post(
    baseUrl.resolve('transactions'),
    headers: {
      'Accept': 'application/json',
      'Authorization': 'Bearer $token',
      'Content-Type': 'application/json',
      'Idempotency-Key': idempotencyKey,
    },
    body: jsonEncode({
      'type': 'DISPATCH',
      'scope': 'FACTORY',
      'factoryId': factoryId,
      'items': [
        {'materialId': 'T-5836', 'quantityChange': 10}
      ],
      'notes': 'Dispatch to track renewal site',
      'person': 'South Section Engineering Team',
      'comingFrom': null,
      'dateOfArrival': null,
      'dateRequested': '2026-08-26',
      'dateLeaving': '2026-08-27',
      'truckNumber': 'KA02CD5678',
      'billFileId': billFileId,
      'proofFileId': proofFileId,
    }),
  );
  return decodeData(response);
}
```

## 17. Complete Endpoint Permission Matrix

Legend: `Public`, `Own`, `Allow`, `Deny`. Every endpoint contracted in this specification appears exactly once.

| Method | Path | Public | VIEWER | ADMIN | SUPERADMIN | Notes |
| --- | --- | --- | --- | --- | --- | --- |
| GET | `/health` | Public | Public | Public | Public | No business data. |
| POST | `/auth/login` | Public | Public | Public | Public | Active accounts. |
| POST | `/auth/refresh` | Token | Token | Token | Token | Refresh-token possession. |
| POST | `/auth/logout` | Deny | Allow | Allow | Allow | Access + matching refresh session. |
| GET | `/auth/me` | Deny | Allow | Allow | Allow | Current profile. |
| POST | `/account-requests` | Public | Public | Public | Public | Anonymous workflow; requested role VIEWER/ADMIN only. |
| GET | `/account-requests` | Deny | Deny | Deny | Allow | Password never returned. |
| POST | `/account-requests/{accountRequestId}/approve` | Deny | Deny | Deny | Allow | Creates user atomically. |
| POST | `/account-requests/{accountRequestId}/reject` | Deny | Deny | Deny | Allow | Deletes retained password hash. |
| GET | `/users` | Deny | Deny | Deny | Allow | All users. |
| POST | `/users/admins` | Deny | Deny | Deny | Allow | Direct admin creation. |
| PATCH | `/users/{userId}` | Deny | Deny | Deny | Allow | Constraints protect self/last superadmin. |
| GET | `/inventory` | Deny | Allow | Allow | Allow | Depot/main list. |
| POST | `/inventory` | Deny | Deny | Allow | Allow | Create material. |
| POST | `/inventory/search-hits` | Deny | Allow | Allow | Allow | Idempotent analytics mutation. |
| GET | `/inventory/{materialId}` | Deny | Allow | Allow | Allow | URL-encode PL ID. |
| PATCH | `/inventory/{materialId}` | Deny | Deny | Allow | Allow | Absolute administrative edit. |
| GET | `/material-serial-mappings` | Deny | Allow | Allow | Allow | Read-only seeded mapping. |
| GET | `/factories` | Deny | Allow | Allow | Allow | Factory summaries. |
| POST | `/factories` | Deny | Deny | Allow | Allow | Creates empty factory. |
| GET | `/factories/{factoryId}` | Deny | Allow | Allow | Allow | Detail. |
| PATCH | `/factories/{factoryId}` | Deny | Deny | Allow | Allow | Metadata edit. |
| GET | `/factories/{factoryId}/materials` | Deny | Allow | Allow | Allow | Factory ledger. |
| POST | `/factories/{factoryId}/materials` | Deny | Deny | Allow | Allow | Add factory material. |
| GET | `/factories/{factoryId}/materials/{materialId}` | Deny | Allow | Allow | Allow | Material detail. |
| PATCH | `/factories/{factoryId}/materials/{materialId}` | Deny | Deny | Allow | Allow | Factory-only mutation. |
| GET | `/requests` | Deny | Own | Allow | Allow | Viewer list forcibly owner-scoped. |
| POST | `/requests` | Deny | Allow | Deny | Deny | Matches viewer-only UI. |
| GET | `/requests/{requestId}` | Deny | Own | Allow | Allow | Non-owned appears 404. |
| POST | `/requests/{requestId}/accept` | Deny | Deny | Allow | Allow | Stock effect. |
| POST | `/requests/{requestId}/reject` | Deny | Deny | Allow | Allow | No stock effect. |
| POST | `/requests/{requestId}/undo` | Deny | Deny | Deny | Allow | Exact reversal, no clamp. |
| POST | `/files` | Deny | Deny | Allow | Allow | Multipart `file` + `purpose`. |
| GET | `/files/{fileId}` | Deny | Deny | Allow | Allow | Metadata only, resource policy applies. |
| GET | `/files/{fileId}/content` | Deny | Deny | Allow | Allow | Private bytes. |
| DELETE | `/files/{fileId}` | Deny | Deny | Own | Allow | Unreferenced only; admin own upload. |
| GET | `/transactions` | Deny | Deny | Allow | Allow | Operational records. |
| POST | `/transactions` | Deny | Deny | Allow | Allow | Both file IDs required. |
| GET | `/transactions/{transactionId}` | Deny | Deny | Allow | Allow | Complete detail. |
| PATCH | `/transactions/{transactionId}` | Deny | Deny | Deny | Allow | Correction, no deletion. |
| POST | `/transactions/{transactionId}/reverse` | Deny | Deny | Deny | Allow | Proposed safer alternative. |
| GET | `/logs` | Deny | Deny | Allow* | Allow | `*` Admin excludes account/user/security categories. |
| GET | `/logs/{logId}` | Deny | Deny | Allow* | Allow | `*` Operational categories only. |

No `/transactions/{id}` hard DELETE, generic transaction file endpoint, OCR endpoint, password-reset endpoint, CSV upload endpoint, or WebSocket endpoint is part of v1.

## 18. Assumptions, Conflicts, and Caveats

### 18.1 Conflict Table

| Topic | Current local Flutter / prior draft | Proposed production decision | Confirmation needed |
| --- | --- | --- | --- |
| Backend status | No network implementation. | This document is planned only. | Backend ownership/timeline. |
| Framework | No backend. | FastAPI recommended; REST contract framework-neutral. | Select framework/team standards. |
| Database | SharedPreferences. | PostgreSQL. | Hosting/version/HA. |
| Generated IDs | Microsecond strings. | UUIDv7/UUIDv4 opaque IDs; PL material IDs preserved. | UUID version. |
| Depot CSV quantity | Random `0..20` on first run. | Deterministic seed with explicit configured balances. | Initial quantities and seed environments. |
| CSV endpoint | Local asset only. | Read-only `/material-serial-mappings`; migration handles seed. | Need future bulk import UI? |
| Attachments | Flutter now has separate Bill and Proof; legacy combined `photo`. | Separate mandatory `billFileId` and `proofFileId`; legacy photo maps only to Proof. | Confirm retention/scanning. |
| File types/size | Image picker, base64 retained only at <=1 MiB. | JPEG/PNG/WebP/PDF, configurable max 10 MiB each. | Confirm 10 MiB and PDFs. |
| OCR | None. | Not contracted; optional future only. | Whether OCR is desired. |
| Sleeper generic scope | UI can select Sleeper before selecting a factory and can search main inventory in generic scope. | `FACTORY` scope requires `factoryId`; generic Sleeper transaction rejected. | Confirm every Sleeper movement belongs to factory. |
| Factory selector | Flutter submits `factoryName`. | Submit immutable `factoryId`; return `factoryNameSnapshot`. | Migration mapping for existing names. |
| Factory mutation | Controller can update matching main inventory and factory ledger. | Factory ledger authoritative; no depot dual-write. | Confirm accounting ownership. |
| Factory material field | `total`. | Remains `total`. | None unless domain terminology changes. |
| Negative inventory | Controller clamps to zero. | Reject whole operation. | Confirm no emergency override; use audited correction instead. |
| `biIssued > total` | Manual UI can persist it; available clamps to zero. | Disallow. | Confirm BI accounting exceptions. |
| `status` | Stored field may become stale. | Derived from available, read-only. | Confirm only two statuses. |
| Transaction magnitude | Local values are usually positive; prior draft mentioned signed factory dispatch logs. | Always positive; type/scope defines direction. | Confirm reporting consumers. |
| Depot dispatch | Increases `biIssued`, does not reduce total. | Preserve current behavior. | Confirm meaning of dispatch vs issue. |
| Material request creators | UI exposes to viewers only; prior draft considered all roles. | `VIEWER` only. | Confirm admins never request stock. |
| Request undo | Local clamps `biIssued` to zero. | Exact reversal or conflict; no clamp. | Confirm remediation workflow for inconsistent migrated data. |
| Transaction correction | Local creates an EDIT log and clamps. | Update effective transaction under lock, append immutable correction event, reject invalid result. | Confirm whether corrected transaction view or event-only model is preferred. |
| Transaction deletion | None in UI; prior draft left TBD. | No hard delete. Proposed superadmin reversal endpoint. | Approve reversal feature and policy. |
| User management | Current UI only approves requests. | `/users/{userId}` proposed for rename/role/status with safeguards. | Confirm management UI/superadmin promotion policy. |
| Password policy | Current minimum four characters and local plaintext. | Recommended minimum 12, Argon2id, never returned/logged. | Final organization password/SSO policy. |
| Password reset | No repository support. | Optional future, no v1 endpoint. | Recovery channel and identity proof. |
| Token durations | No tokens. | Access 15 min, refresh 30-day idle/90-day absolute, rotation. | Confirm risk posture. |
| Pagination | Flutter loads all local data. | Cursor, default 50, max 100. | Confirm UI infinite-scroll adaptation. |
| Real-time | No client support. | REST only; outbox-ready, WebSocket optional future. | Need polling/notifications later? |
| Audit visibility | Viewer has no audit tab; admin has operational audit. | Viewer denied; admin operational only; superadmin all business audit. | Confirm compliance access. |

### 18.2 Migration Caveats

- Existing local records live separately on devices; there is no automatic server migration path in current Flutter.
- Local plaintext account-request/custom-account passwords must not be bulk-copied into logs or generic exports. A controlled migration should force credential reset or hash within a trusted one-time process.
- Existing base64 Bill and Proof values can become separate object records. Legacy `photo`/`photoData` becomes Proof only; a missing Bill means the migrated transaction is historical/legacy and cannot satisfy new-create validation retroactively.
- Historical local records may contain clamped or inconsistent balances. Import should report these for reconciliation rather than silently normalize them.
- Material IDs contain spaces, slashes, ampersands, parentheses, and multiline CSV values. Clients must URL-encode path IDs; backend routing must support encoded slashes or prefer internal lookup parameters during implementation if infrastructure decodes them unsafely. The specified path remains canonical.
- The CSV contains potentially equivalent identifiers with differing spelling, such as `BNC/T2019 2020` and `BNC/T-2019 & 2020`; seed migration must not merge them without domain approval.
- Current random CSV seed quantities are unsuitable for authoritative migration. Physical opening balances require approval and audit.

### 18.3 Unresolved Decisions Requiring Confirmation

1. Confirm FastAPI versus another REST framework and PostgreSQL hosting model.
2. Confirm object-storage provider, malware scanner, file retention, PDF support, and 10 MiB maximum.
3. Confirm JWT issuer/audience, 15-minute access lifetime, refresh lifetimes, and key management.
4. Confirm password policy or whether enterprise SSO should replace local passwords.
5. Confirm that all Sleeper transactions require a factory and that factory ledgers never dual-write depot inventory.
6. Confirm depot dispatch accounting (`biIssued += quantity` while total remains unchanged).
7. Confirm deterministic opening balances and which CSV/factory seeds are production data versus demo data.
8. Confirm superadmin reversal endpoint and correction/reconciliation governance.
9. Confirm user deactivation/role-management UI and how additional superadmins are appointed.
10. Confirm audit and file retention periods and whether tamper-evident/WORM archival is mandatory.
11. Confirm cursor pagination adoption in Flutter and whether total counts are needed.
12. Confirm whether search-hit analytics should be retained, sampled, or removed for privacy/scale.

## 19. Sources

This proposed contract was derived from repository state inspected on 2026-08-27. It does not claim a backend implementation or test verification.

- `backend.md`: earlier draft behavior, roles, resources, and open questions.
- `lib/controllers/inventory_controller.dart`: transaction effects, corrections, search hits, material/factory operations, request transitions, and local clamping behavior.
- `lib/services/auth_service.dart`: current local sessions/accounts and approval-created login behavior.
- `lib/services/account_request_service.dart`: local account request persistence.
- `lib/services/inventory_service.dart`: local persistence, CSV seed, and factory demo seed.
- `lib/services/request_service.dart`: local material request creation/history.
- `lib/models/inventory_item.dart`: inventory fields, available derivation, sections, and CSV parsing.
- `lib/models/factory.dart`: factory and factory-material fields and available derivation.
- `lib/models/transaction_log.dart`: Bill/Proof fields, legacy photo mapping, logistics, and audit types.
- `lib/models/viewer_request.dart`: request status, decision fields, and append-only history.
- `lib/models/account_request.dart`: current account-request shape and local password carriage risk.
- `lib/models/purchase_order_status.dart`: current PO labels.
- `lib/views/transactions_view.dart`: separate mandatory Bill/Proof controls, incoming/dispatch required fields, date validation, factory selection, and 1 MiB base64 behavior.
- `lib/views/inventory_view.dart`: inventory/factory editing, search, sort, and filter behavior.
- `lib/views/new_user_request_view.dart`: current account ID/role/password validation.
- `lib/views/superadmin_permission_view.dart`: current approval/rejection and account creation flow.
- `assets/material_serial_mappings.csv`: actual material identifiers/descriptions, including `T-6902` and `T-5836`.
- `pubspec.yaml`: current dependencies and absence of an HTTP/secure-storage/real-time client.

---

This is a documentation-only planned production specification. Backend implementation, deployment, client integration, migration, and verification remain pending.
