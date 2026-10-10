# Inventory & Transaction Model

## Two Independent Ledgers

| Ledger | Scope | Stock Fields | Availability |
|--------|-------|--------------|--------------|
| **Depot** | `DEPOT` | `quantity`, `biIssued` | `available = quantity - biIssued` |
| **Factory** | `FACTORY` | `total`, `biIssued` | `available = total - biIssued` |

**They never dual-write.** A `DISPATCH` from Depot reduces Depot `biIssued`; a `DISPATCH` to Factory increases Factory `biIssued` (provisional issue ledger pending product confirmation). `INCOMING` increases `quantity` (Depot) or `total` (Factory).

## Stock Transition Rules

| Operation | Depot Effect | Factory Effect |
|-----------|--------------|----------------|
| `INCOMING` | `quantity += qty` | `total += qty` |
| `DISPATCH` | `biIssued += qty` | `biIssued += qty` (provisional) |
| `Accept Request` | `biIssued += qty` | `biIssued += qty` |
| `Undo Accepted` | `biIssued -= qty` | `biIssued -= qty` |
| `Reject Request` | No change | No change |
| `Undo Rejected` | No change | No change |

These rules are **enforced atomically by the backend** in a single database transaction. The frontend never calculates stock locally for mutations — it reloads authoritative state after each decision (`_refreshInventoryAfterRequestDecision()`).

## Material Identity

- **Authoritative ID:** Material ID (e.g., `"T-6902"`) — opaque, case-insensitively unique domain string
- **Never** use names, list indexes, or display labels as identities
- Factory materials are scoped to a `factoryId`; Depot materials have no factory

## Purchase Order Status

Three states drive validation:
- `NONE` → `incomingQuantity == 0`, no expected date
- `PENDING` → `incomingQuantity > 0`
- `ORDERED` → `incomingQuantity > 0` **and** `expectedAvailabilityDate` set

Frontend validates this in `InventoryController._validMaterial()` before sending mutations.

## Transaction Types & Scopes

| Type | Scope | Required Fields |
|------|-------|-----------------|
| `INCOMING` | `DEPOT` | `billFileId`, `proofFileIds[]`, `person`, `truckNumber`, `comingFrom`, `dateOfArrival` |
| `INCOMING` | `FACTORY` | `billFileId`, `proofFileIds[]`, `person`, `truckNumber`, `comingFrom`, `dateOfArrival`, `factoryId` |
| `DISPATCH` | `DEPOT` | `billFileId`, `proofFileIds[]`, `person`, `truckNumber`, `dateRequested`, `dateLeaving` |
| `DISPATCH` | `FACTORY` | `billFileId`, `proofFileIds[]`, `person`, `truckNumber`, `dateRequested`, `dateLeaving`, `factoryId` |

- `billFileId` mandatory for both types
- `proofFileIds` optional (0–10 unique IDs, ordered)
- Omit `proofFileIds` to preserve existing; send `[]` to remove all

## Source References

- `lib/controllers/inventory_controller.dart:122-185` — `addTransaction()` with scope logic
- `lib/controllers/inventory_controller.dart:721-743` — `_validMaterial()` purchase order validation
- `lib/controllers/inventory_controller.dart:745-790` — Material body builders (Depot vs Factory)
- `lib/models/inventory_item.dart` — Depot material model
- `lib/models/factory.dart` — Factory material model
- `api.md` sections 3.1, 3.2, 5.1 — Inventory, Factories, Transactions contract