# Key Design Decisions & Rationale

| Decision | Rationale |
|----------|-----------|
| **In-memory access tokens** | Prevents token persistence across sessions; reduces attack surface |
| **Cookie-only refresh** | `HttpOnly` cookies immune to XSS; platform handles secure storage |
| **No atomic batch requests** | Backend contract: one idempotent call per material line; partial success is explicit |
| **Optimistic locking via `If-Match`** | Client reloads on `412` rather than merging; avoids silent data loss |
| **Frontend role checks = UX only** | Backend is sole authorization authority; frontend boundaries are presentation |
| **Separate Depot/Factory ledgers** | Domain requirement: distinct stock accounting, no cross-ledger transfers |
| **`InventoryController` as single source** | Centralizes loading, caching, and refresh; widgets consume via `ChangeNotifier` |
| **Test doubles via `AppDependencies.forTesting()`** | Explicit injection avoids global state; deterministic local services in `test/support/` |
| **Idempotency keys on every mutation** | Prevents duplicate side effects on retry; required by backend contract |
| **UUIDv4 for all identities** | Opaque, globally unique, no semantic meaning; prevents guessing |
| **Server-authored timestamps** | ISO-8601 UTC with explicit `Z`; no naive datetimes; single source of truth |
| **Cursor pagination (no total count)** | Scales to large datasets; composite `(timestamp, id)` cursors prevent skip/repeat |
| **`proofFileIds` plural canonical form** | Supports 0–10 ordered proofs; singular `proofFileId` retained for migration only |
| **Soft delete for factories/users** | Archival preserves audit, transaction, and request attribution; no data loss |
| **File upload before transaction** | Decouples attachment handling from business transaction; enables preview/validation |
| **No real-time/WebSocket** | Contract explicitly excludes; polling via cursor pagination sufficient for current scope |

## Resolved Contract Decisions (from api.md)

1. **Factory Dispatch accounting:** `DISPATCH`/`FACTORY` keeps `total` unchanged and applies `biIssued += quantityChange` (provisional issue ledger pending product confirmation)
2. **Identifier normalization:** trim + case-insensitive compare; usernames stored lowercase; `accountId` preserves submitted uppercase
3. **Compatibility fields:** response `section` mirrors `module`; singular `proofFileId` input remains accepted with `proofFileIds` canonical; request `itemId` and `billAttachment.fileId` aliases retained
4. **Retention:** unreferenced uploads swept after `ORPHAN_RETENTION_DAYS` (default 7); soft-deleted file rows stay for audit; archived users and factories stay readable; transactions and audits immutable
5. **Uploaded images keep original media type**; response metadata always describes actual stored bytes
6. **No atomic multi-line request endpoint**; one non-atomic, idempotent request per material line remains the contract

## Compatibility Notes

- Current Flutter response parsers retain several legacy fields and defaults
- Backend responses provide complete required fields rather than relying on frontend defaults
- Compatibility fields include request `itemId`, singular transaction `proofFileId`/`proofFile` for response rendering, and audit `id`, nested `actor`, and `occurredAt`
- Cannot be replaced until a coordinated Flutter release
- Access tokens appear only in login and refresh responses
- Refresh tokens never appear in JSON responses
- No response exposes plaintext passwords, password hashes, internal storage paths, raw stack traces, or unredacted audit payloads