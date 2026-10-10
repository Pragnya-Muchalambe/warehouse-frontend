# File Attachments (Bills & Proofs)

## Upload Flow

1. **Upload first** — `POST /files` (multipart: `purpose` = `BILL` or `PROOF`, `file` binary)
2. **Receive file ID** — server returns `id`, `sha256`, `status: "READY"`
3. **Reference in transaction** — `billFileId` (required) + `proofFileIds[]` (0–10, ordered, unique)

## Constraints

| Constraint | Enforcement |
|------------|-------------|
| Bill mandatory | Backend rejects transaction without valid `billFileId` |
| Proof optional | Omit `proofFileIds` to preserve; send `[]` to remove all |
| Max 10 proofs | Backend rejects >10 with `422` |
| File ownership | `billFileId`/`proofFileIds` must belong to authenticated caller |
| Content validation | Server inspects MIME + binary signature (PDF, JPEG, PNG, WebP ≤ 10 MiB) |

## Supported Content Types

- `application/pdf`
- `image/jpeg`
- `image/png`
- `image/webp`

**Max size:** 10 MiB (10 × 1024 × 1024 bytes)

Bills are no longer PDF-only and Proofs are no longer image-only — both accept all four types after server-side byte inspection.

## Retrieval

- `GET /files/{id}/content` — binary bytes with `Authorization: Bearer`
- **Viewer:** Only Bills linked to own accepted requests
- **Admin/Superadmin:** Authorized Bills and Proofs
- Never expose access tokens in URLs

## Duplicate-Content Handling

- Same `Idempotency-Key` replay → returns original response and file ID
- Different key, identical bytes, same purpose, same uploader → returns existing accessible record (`200`)
- Same bytes, different purpose → `422` (a `BILL` never becomes a `PROOF`)
- Bytes matching another user's file → creates isolated new record; no foreign metadata disclosed

## Attachment Rule

`billFileId` and every `proofFileIds` entry must name a file uploaded by the authenticated caller; foreign IDs fail exactly like missing files (`404`) without revealing existence.

## File Metadata Endpoints

| Endpoint | Visibility |
|----------|------------|
| `GET /files` | ADMIN/SUPERADMIN, cursor-paginated, deleted excluded |
| `GET /files/{fileId}` | ADMIN/SUPERADMIN, same visibility rules |
| `DELETE /files/{fileId}` | ADMIN/SUPERADMIN, `Idempotency-Key` + `If-Match` required; referenced files return `409 FILE_IN_USE` |

## Source References

- `lib/services/transaction_file_picker.dart` — File selection and upload orchestration
- `lib/services/transaction_file_picker_types.dart` — File picker types
- `lib/widgets/attachment_preview.dart` — Preview UI
- `lib/controllers/inventory_controller.dart:122-185` — Transaction creation with file refs
- `api.md` sections 5.2, 5.3, 5.4 — Upload, Bill/Proof references, Authenticated retrieval