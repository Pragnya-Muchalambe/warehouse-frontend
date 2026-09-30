# Railway Warehouse Frontend API Contract

This document is the authoritative integration contract for the Flutter
frontend. It records verified backend behavior only. The frontend must not
invent endpoints, fields, atomicity, or local substitutes for server mutations.

## Base URL

Configure the API origin at build time with `WAREHOUSE_API_BASE_URL`. The
client appends `/api/v1` unless the configured URL already ends with that
prefix. Production builds require HTTPS; HTTP is allowed only for local
development.

```text
flutter build web --dart-define=WAREHOUSE_API_BASE_URL=https://api.example.com
```

## Authentication

### Login

```http
POST /api/v1/auth/login
Content-Type: application/json
```

```json
{"username":"user-id","password":"password"}
```

The frontend label is `User ID`; the wire field remains `username`.

```json
{
  "data": {
    "accessToken": "access-token",
    "accessTokenExpiresAt": "UTC timestamp",
    "tokenType": "Bearer",
    "user": {
      "id": "internal-user-id",
      "accountId": "human-facing-user-id",
      "username": "login-id",
      "name": "Display Name",
      "role": "VIEWER | ADMIN | SUPERADMIN",
      "status": "ACTIVE",
      "version": 1
    }
  },
  "meta": {"requestId":"request-id"}
}
```

Unknown roles and inactive or incomplete users fail closed.

### Refresh

```http
POST /api/v1/auth/refresh
```

An empty body is accepted. The refresh token exists only in a Secure HttpOnly
cookie and is never returned in JSON, exposed to Dart application code, stored
in client-readable storage, or logged. The HTTP transport must support
credentialed cookies.

### Logout

```http
POST /api/v1/auth/logout
Authorization: Bearer <access-token>
```

An empty body is accepted. Success returns `204 No Content` and revokes/clears
the refresh session. Local access credentials and protected state are cleared
even when remote logout fails.

### Current user

```http
GET /api/v1/auth/me
Authorization: Bearer <access-token>
```

## Envelopes

Single resource:

```json
{"data":{},"meta":{"requestId":"request-id"}}
```

Collection:

```json
{
  "data": [],
  "page": {"limit":100,"nextCursor":null,"hasMore":false},
  "meta": {"requestId":"request-id"}
}
```

Error:

```json
{
  "error": {
    "code": "MACHINE_READABLE_CODE",
    "message": "Safe user-facing message",
    "details": [],
    "retryable": false
  },
  "meta": {"requestId":"request-id"}
}
```

Collection consumers follow every non-repeating cursor while `hasMore` is
true. A missing or repeated cursor is malformed server data, not an empty page.

## Mutation Headers

Business mutations require:

```http
Idempotency-Key: <uuid>
```

Versioned state changes also require:

```http
If-Match: "<version>"
```

The frontend retains and reuses an operation key after retryable network,
timeout, `502`, `503`, or `504` failures, including across access-token refresh.
It removes the key after success or a definitive non-retryable failure. A new
operation receives a new key. Operation identity includes method, path,
version, and stable request body. Unsafe mutations are never retried in a
hidden automatic loop. A `412 VERSION_CONFLICT` triggers authoritative reload.

## Files

### Upload

```http
POST /api/v1/files
Authorization: Bearer <access-token>
Idempotency-Key: <uuid>
Content-Type: multipart/form-data
```

Multipart fields are `purpose = BILL | PROOF` and `file = uploaded bytes`.
Supported content types are:

- `application/pdf`
- `image/jpeg`
- `image/png`
- `image/webp`

The frontend validates extension and byte signature consistently. It does not
classify unknown bytes as an image.

### Content

```http
GET /api/v1/files/{fileId}/content
Authorization: Bearer <access-token>
```

Image and PDF previews use authenticated bytes. Access tokens never appear in
URLs. The UI handles `401`, `403`, `404`, unsupported content, malformed bytes,
and transport failure. Viewers may access only authorized Bills; Proof access
remains role-restricted.

## Transactions

### Create

```http
POST /api/v1/transactions
Authorization: Bearer <access-token>
Idempotency-Key: <uuid>
```

```json
{
  "type": "INCOMING | DISPATCH",
  "scope": "DEPOT | FACTORY",
  "factoryId": "required only for FACTORY",
  "items": [{"materialId":"material-id","quantityChange":1}],
  "notes": "optional",
  "person": "required",
  "comingFrom": "required for INCOMING",
  "dateOfArrival": "YYYY-MM-DD for INCOMING",
  "dateRequested": "YYYY-MM-DD for DISPATCH",
  "dateLeaving": "YYYY-MM-DD for DISPATCH",
  "truckNumber": "required",
  "billFileId": "required",
  "proofFileIds": [],
  "sourceRequestIds": []
}
```

Rules:

- Bill is required; Proof is optional.
- `proofFileIds` contains zero to ten unique IDs. New requests never use the
  legacy singular `proofFileId`.
- Bill and Proof IDs are distinct.
- Transactions contain one to 100 unique materials.
- Sleeper uses `scope = FACTORY` and requires `factoryId`.
- Depot uses `scope = DEPOT` and omits `factoryId`.
- Incoming and Dispatch date fields are not mixed.
- Dispatch leaving date is not before requested date.
- Stock remains server-authoritative.

### Correction

```http
PATCH /api/v1/transactions/{transactionId}
Authorization: Bearer <access-token>
Idempotency-Key: <uuid>
If-Match: "<version>"
```

Corrections use canonical `billFileId` and `proofFileIds`.

### Retrieval

```http
GET /api/v1/transactions
GET /api/v1/transactions/{transactionId}
```

Responses include `billFileId`, `billFile`, `proofFileIds`, `proofFiles`,
`createdAt`, `updatedAt`, `correctedAt`, and `version`.

## Material Requests

### List

```http
GET /api/v1/requests
```

Supported filters include `status`, `module`, `factoryId`, `viewerId`,
`itemId`, `sort`, `cursor`, and `limit`. Module values are `DEPOT` and
`SLEEPER`.

### Create one line

```http
POST /api/v1/requests
Authorization: Bearer <access-token>
Idempotency-Key: <uuid>
```

```json
{
  "module": "DEPOT | SLEEPER",
  "factoryId": "required for SLEEPER; absent/null for DEPOT",
  "itemId": "material-id",
  "quantity": 1
}
```

The backend creates exactly one request per call. A multi-item frontend cart
submits one call per material line with one stable idempotency key per line.
This is not an atomic backend batch. The frontend tracks each result, removes
successful lines, preserves failed lines for retry, and never automatically
resubmits successful lines.

### Decisions

```http
POST /api/v1/requests/{requestId}/accept
Idempotency-Key: <uuid>
If-Match: "<version>"
```

```http
POST /api/v1/requests/{requestId}/reject
Idempotency-Key: <uuid>
If-Match: "<version>"
```

Reject accepts optional `{"reason":"optional"}`.

```http
POST /api/v1/requests/{requestId}/undo
Idempotency-Key: <uuid>
If-Match: "<version>"
```

Undo is Superadmin-only and accepts the same optional reason body.

### Pending counts

```http
GET /api/v1/requests/pending-counts
```

Optional query parameters are `module=DEPOT|SLEEPER` and `factoryId`.

```json
{
  "data": {
    "total": 2,
    "byModule": {"DEPOT":1,"SLEEPER":1},
    "byFactory": {"factory-id":1}
  },
  "meta": {"requestId":"request-id"}
}
```

Counts are already role- and scope-filtered. Missing or malformed required
count fields are response errors, not zero.

## Stock Semantics

| Operation | Total | BI Issued | Available |
| --- | --- | --- | --- |
| Create Pending | unchanged | unchanged | unchanged |
| Accept | unchanged | increases | `Total - BI Issued` |
| Reject | unchanged | unchanged | unchanged |
| Undo Accepted | unchanged | decreases | `Total - BI Issued` |

The frontend never mutates stock optimistically. It reloads authoritative Depot
inventory and factory materials after Accept or Undo.

## Factory Archive

```http
DELETE /api/v1/factories/{factoryId}
Authorization: Bearer <access-token>
Idempotency-Key: <uuid>
If-Match: "<version>"
```

This Superadmin-only operation soft-archives by authoritative factory ID.
Historical materials, requests, transactions, and Audit data remain. Archived
factories leave active workflows; pending requests can block archival. The
frontend reloads authoritative factories after success.

## Account Deactivation

```http
DELETE /api/v1/users/{userId}
Authorization: Bearer <access-token>
Idempotency-Key: <uuid>
If-Match: "<version>"
```

This Superadmin-only operation deactivates rather than erases. The current
Superadmin and the last active Superadmin cannot be deactivated. Active refresh
sessions are revoked, historical actor references remain, and the frontend
reloads authoritative users after success.

## Time Rules

- Server timestamps are timezone-aware UTC ISO-8601 values.
- A missing or invalid required timestamp is a malformed response and throws
  `FormatException`.
- An absent optional timestamp remains null; an invalid non-null optional
  timestamp throws `FormatException`.
- The frontend never fabricates server event time.
- Conversion to local time occurs only for display.
- `createdAt`, `updatedAt`, `decisionAt`, `correctedAt`, and other event times
  remain semantically distinct.
- Ordering uses parsed timestamps and a stable ID tie-breaker.

## Role and Module Boundaries

- Viewer creates requests and views only authorized request/Bill data.
- Admin accepts/rejects requests and creates transactions.
- Superadmin additionally undoes decisions, archives factories, deactivates
  accounts, and performs other explicitly exposed privileged operations.
- Depot and Sleeper data and navigation remain separated. Sleeper request
  operations use module `SLEEPER`; Sleeper transactions use scope `FACTORY`
  with an authoritative factory ID.
