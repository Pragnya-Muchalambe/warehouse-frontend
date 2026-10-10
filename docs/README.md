# Documentation Index

This directory contains the Explanation documents for the Warehouse Frontend, organized by topic.

## Document Map

| # | Document | Audience | Purpose |
|---|----------|----------|---------|
| 01 | [System Overview](01-system-overview.md) | All | High-level architecture, repository structure, component diagram |
| 02 | [Authentication & Session Management](02-authentication.md) | Backend, Mobile, Security | Cookie-only refresh, platform-specific transport, concurrent deduplication, bootstrap |
| 03 | [Role-Based Access Control](03-rbac.md) | All | Wire roles, module/factory scoping, frontend vs backend authorization boundary, permission matrix |
| 04 | [Inventory & Transaction Model](04-inventory-model.md) | Domain, Backend | Dual ledgers, stock transition rules, material identity, purchase order states, transaction types |
| 05 | [Request Workflow](05-request-workflow.md) | Domain, Frontend | Viewer creation, Admin accept/reject, Superadmin undo, pending counts |
| 06 | [File Attachments](06-file-attachments.md) | Frontend, Backend | Bill/Proof upload flow, constraints, retrieval, duplicate handling, metadata endpoints |
| 07 | [Testing & Test Architecture](07-testing.md) | QA, Frontend | `AppDependencies` production/testing, `InventoryController` test seam, validation commands |
| 08 | [Platform-Specific Concerns](08-platform-concerns.md) | Mobile, DevOps | Build config, Android release blockers, CORS, platform support matrix, cookie transport |
| 09 | [Design Decisions](09-design-decisions.md) | Architects, Leads | Rationale table, resolved contract decisions, compatibility notes |
| 10 | [Common Pitfalls](10-common-pitfalls.md) | Contributors | 15 things to avoid when contributing |

## Quick Start

New contributors should read in order:
1. **01-system-overview.md** — Understand the big picture
2. **03-rbac.md** — Understand who can do what
3. **02-authentication.md** — Understand the session model
4. **04-inventory-model.md** — Understand the domain model
5. **05-request-workflow.md** — Understand the core user flow
6. **10-common-pitfalls.md** — Avoid common mistakes

## Related Files

- [`../api.md`](../api.md) — Complete backend contract (endpoints, payloads, errors, permissions)
- [`../README.md`](../README.md) — Setup, validation commands, deployment notes
- [`../lib/main.dart`](../lib/main.dart) — App bootstrap and role-based shell routing
- [`../lib/app_dependencies.dart`](../lib/app_dependencies.dart) — Dependency graph and test seam
- [`../lib/controllers/inventory_controller.dart`](../lib/controllers/inventory_controller.dart) — Central state orchestration
- [`../lib/services/auth_service.dart`](../lib/services/auth_service.dart) — Session lifecycle and refresh deduplication
- [`../lib/services/api_client.dart`](../lib/services/api_client.dart) — HTTP client, idempotency, error envelopes
- [`../test/`](../test/) — Unit/widget tests and deterministic local service implementations