# System Overview

## Purpose

The application is a **Flutter port of a React/Vite proof-of-concept** for railway warehouse inventory management across two operational scopes:

- **Depot** — central warehouse operations
- **Sleeper / Factory** — distributed factory operations (mapped to `FACTORY` scope in the API)

It connects to an HTTP API defined in [`api.md`](../api.md) and implements three user roles with distinct workflows.

## High-Level Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                        WarehouseApp                          │
│  (main.dart — bootstrap, session, role-based shell routing) │
└─────────────────────────────────────────────────────────────┘
                              │
              ┌───────────────┼───────────────┐
              ▼               ▼               ▼
       ┌────────────┐ ┌──────────────┐ ┌───────────────┐
       │ ViewerShell│ │ AdminShell   │ │SuperadminShell│
       │ (read-only)│ │ (write scope)│ │ (full control)│
       └────────────┘ └──────────────┘ └───────────────┘
              │               │               │
              └───────────────┼───────────────┘
                              ▼
                   ┌───────────────────────┐
                   │   InventoryController │
                   │  (ChangeNotifier,     │
                   │   orchestrates loads) │
                   └───────────────────────┘
                              │
          ┌───────────────────┼───────────────────┐
          ▼                   ▼                   ▼
┌─────────────────┐ ┌─────────────────┐ ┌─────────────────┐
│ InventoryService│ │ RequestService  │ │  AuthService    │
│ (materials,     │ │ (viewer        │ │ (login, refresh,│
│  factories,     │ │  requests,     │ │  logout, session)│
│  transactions)  │ │  decisions)    │ │                 │
└─────────────────┘ └─────────────────┘ └─────────────────┘
          │                   │                   │
          └───────────────────┼───────────────────┘
                              ▼
                   ┌───────────────────────┐
                   │      ApiClient        │
                   │  (singleton HTTP,     │
                   │   idempotency,        │
                   │   refresh orchestration)│
                   └───────────────────────┘
```

**Key principle:** The frontend enforces *presentation and workflow boundaries* only. **Server-side authorization remains authoritative.** Role restrictions in Dart are UX guardrails, not security boundaries.

## Repository Structure

```
android/   Android host integration and persistent cookie transport
assets/    Bundled frontend assets
lib/       Production Flutter source
test/      Unit/widget tests and explicit test-only local services
api.md     Final frontend/backend API contract
```

See [`README.md`](../README.md#repository-structure) for details.