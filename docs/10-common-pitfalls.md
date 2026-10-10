# Common Pitfalls for Contributors

1. **Don't add local stock calculations for mutations** — always reload from API after decisions (`_refreshInventoryAfterRequestDecision()`)

2. **Don't expose refresh tokens to Dart** — the cookie contract is non-negotiable; refresh tokens never appear in JSON, logs, or client storage

3. **Don't assume `factoryId` for Depot** — it must be `null`/absent for `DEPOT` scope; only `FACTORY` scope requires a factory

4. **Don't skip `Idempotency-Key`** — every business mutation requires one (except auth endpoints: login, refresh, logout)

5. **Don't use `accountId`/`username` as identity** — only server-generated UUIDs are authoritative; usernames are stored lowercase, `accountId` preserves submitted case

6. **Don't add platform-specific code outside `credentialed_http_client_*.dart`** — cookie transport is the only platform split; all other code must be platform-agnostic

7. **Don't commit unsigned Android releases** — release builds are explicitly blocked until unique application ID and production signing credentials are supplied

8. **Don't treat frontend role checks as security** — they are UX boundaries only; backend returns `403` if unauthorized

9. **Don't merge on `412 VERSION_CONFLICT`** — always reload the resource (`_reloadInventoryAfterConflict()`, `_reloadFactoriesAfterConflict()`)

10. **Don't hardcode `section` values** — `section` mirrors `module` for compatibility; use `InventorySection` enum

11. **Don't assume `proofFileIds` is always present** — omit to preserve existing proofs; send `[]` to remove all

12. **Don't exceed 10 proofs** — backend rejects with `422`; validate in UI before submit

13. **Don't use names/indexes as material identifiers** — only the material ID string (e.g., `"T-6902"`) is authoritative

14. **Don't bypass `AppDependencies.forTesting()`** — all testable services must be injectable; no global singletons in production code paths

15. **Don't forget `If-Match` on PATCH/DELETE** — required for optimistic locking; stale version returns `412`