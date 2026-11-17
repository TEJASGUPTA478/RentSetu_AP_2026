# 01 – Normalization Report

**Repository**: [RentSetu (DE)](https://github.com/TEJASGUPTA478/RentSetu)
**Source files**:
- [`backend/prisma/schema.prisma`](https://github.com/TEJASGUPTA478/RentSetu/blob/main/backend/prisma/schema.prisma)
- All migration SQL files under `backend/prisma/migrations/` (e.g., `20261116000000_init/migration.sql`, `20261116001000_one_active_lease_per_unit/migration.sql`, `20261116002000_monthly_rent_date_checks/migration.sql`)
- [`backend/README.md`](https://github.com/TEJASGUPTA478/RentSetu/blob/main/backend/README.md)

---

## 1. Purpose and scope

The backend uses a PostgreSQL database defined by a Prisma schema.  This report analyses the **relational schema** (tables, columns, keys, constraints, and indexes) created by the migration scripts.  It does **not** assume any UI‑level data that is not persisted in the database, and it does not claim that the frontend is wired to these tables (the README notes that the UI uses mock data).

---

## 2. Relations and key attributes (actual models)

| Model | Primary key | Notable attributes | Unique / indexes | Foreign keys |
|-------|-------------|-------------------|------------------|--------------|
| **User** | `id` (String, `@default(uuid())`) | `name`, `email`, `passwordHash`, `role` (enum `Role`), `isActive`, timestamps | `email` `@unique`; index on `(role, isActive)` | – |
| **Property** | `id` | `ownerId`, optional `managerId`, `name`, `address`, `city`, `state`, `pincode`, `type`, timestamps | index on `ownerId`; composite index on `(ownerId, city)` | `ownerId` → `User.id` (`ON DELETE RESTRICT`); `managerId` → `User.id` (`ON DELETE RESTRICT`) |
| **Unit** | `id` | `propertyId`, `unitNumber`, `rent`, `bedrooms`, `status` (enum `UnitStatus`), timestamps | unique index on `(propertyId, unitNumber)`; indexes on `propertyId`, `status`, `(propertyId, status)` | `propertyId` → `Property.id` (`ON DELETE RESTRICT`) |
| **TenantProfile** | `id` | `userId`, `createdByLandlordId`, `phone`, optional emergency‑contact fields, optional ID‑proof fields, timestamps | `userId` `@unique`; index on `createdByLandlordId` | `userId` → `User.id` (`ON DELETE RESTRICT`); `createdByLandlordId` → `User.id` (`ON DELETE RESTRICT`) |
| **Lease** | `id` | `unitId`, `tenantId` (points to `TenantProfile.id`), `startDate`, `endDate`, `monthlyRent`, `securityDeposit`, `dueDay` (check 1‑28), `status` (enum `LeaseStatus`), timestamps | index on `unitId`; index on `tenantId`; index on `status`; index on `(status, startDate, endDate)`; **partial** unique index `one_active_lease_per_unit` on `unitId` where `status = 'ACTIVE'` (migration `20261116001000_one_active_lease_per_unit`) | `unitId` → `Unit.id` (`ON DELETE RESTRICT`); `tenantId` → `TenantProfile.id` (`ON DELETE RESTRICT`) |
| **Payment** | `id` | `leaseId`, `billingMonth` (first day of month – enforced by migration `20261116002000_monthly_rent_date_checks`), `amount`, `method` (enum `PaymentMethod`), `paidOn`, optional `notes`, timestamps | unique index on `(leaseId, billingMonth)`; indexes on `leaseId`, `billingMonth`, `paidOn` | `leaseId` → `Lease.id` (`ON DELETE RESTRICT`) |
| **MaintenanceRequest** | `id` | `unitId`, optional `leaseId`, `tenantId`, `title`, `description`, `priority` (enum `Priority`), `status` (enum `MaintenanceStatus`), optional `resolvedAt`, timestamps | indexes on `unitId`, `leaseId`, `tenantId`, `status`, composite index `(unitId, status)` | `unitId` → `Unit.id` (`ON DELETE RESTRICT`); `leaseId` → `Lease.id` (`ON DELETE RESTRICT`); `tenantId` → `TenantProfile.id` (`ON DELETE RESTRICT`) |

All foreign‑key actions are `ON DELETE RESTRICT` (the migrations never define `CASCADE`).

---

## 3. Functional dependencies and candidate keys

- **User**: `id →` all other User columns (primary‑key dependency).  Alternate key: `email → id` (unique). 
- **Property**: `id →` all other Property columns.  No alternate candidate keys.
- **Unit**: `id →` all other Unit columns.  Alternate composite key: `(propertyId, unitNumber) → Unit.*` (unique index). 
- **TenantProfile**: `id →` all other TenantProfile columns.  Alternate key: `userId → TenantProfile.*` (unique one‑to‑one).
- **Lease**: `id →` all other Lease columns.  No alternate keys beyond the partial unique index `one_active_lease_per_unit` which enforces a business rule but is not a functional dependency.
- **Payment**: `id →` all other Payment columns.  Alternate composite key: `(leaseId, billingMonth) → Payment.*` (unique index ensures at most one payment per lease per month).
- **MaintenanceRequest**: `id →` all other MaintenanceRequest columns.  No alternate keys.

Foreign‑key columns enforce referential integrity but do **not** create functional dependencies from the referenced side to the referencing side.

---

## 4. Normalisation analysis

### 4.1 First Normal Form (1NF)
All attributes are atomic; there are no repeating groups or multivalued columns.  Relationships (e.g., many `Unit`s belonging to a `Property`) are modelled as separate rows in their own tables.

### 4.2 Second Normal Form (2NF)
Every non‑key attribute depends on the **entire** primary key.  All tables use a single‑column primary key, so 2NF holds trivially.  Composite unique keys are alternates, not primary keys, and no non‑key attribute is partially dependent on a subset of them.

### 4.3 Third Normal Form (3NF)
All non‑key attributes are non‑transitively dependent on the primary key.  Examples:
- `Payment.amount` depends on `Payment.id` and not on any other attribute such as `Lease.monthlyRent`.
- `Unit.rent` depends solely on `Unit.id`.
- `TenantProfile.phone` depends solely on `TenantProfile.id`.
No table stores derived data that could be computed from another table, so there are no transitive dependencies.

---

## 5. Design rationale and anomaly mitigation

| Anomaly | Mitigation in the schema |
|---------|---------------------------|
| **Insert anomaly** – creating a `Unit` without a `Property` | `Unit.propertyId` is NOT NULL with a foreign‑key (`ON DELETE RESTRICT`). |
| **Update anomaly** – changing a tenant’s e‑mail | The e‑mail lives only in `User`; updating `User.email` automatically affects any join that reads the tenant’s email. No copy exists in `TenantProfile`. |
| **Delete anomaly** – deleting a `Property` that still has dependent rows | `ON DELETE RESTRICT` prevents orphaned `Unit`, `TenantProfile`, etc.; dependents must be removed first. |
| **Duplicate payment rows** | Unique index `(leaseId, billingMonth)` guarantees at most one payment per lease per month. |
| **Multiple active leases for the same unit** | Partial unique index `one_active_lease_per_unit` (migration `20261116001000_one_active_lease_per_unit`) enforces a single `Lease` with `status = 'ACTIVE'` per `unitId`. |

The separation of **User**, **TenantProfile**, **Property**, **Unit**, **Lease**, **Payment**, and **MaintenanceRequest** isolates concerns, eliminates redundant storage, and reduces insertion, update, and deletion anomalies.

---

## 6. Integrity rules and limitations

- **Enums** (`Role`, `UnitStatus`, `LeaseStatus`, `PaymentMethod`, `MaintenanceStatus`, `Priority`) are declared in the initial migration.
- **Primary keys** are all UUIDs (`@default(uuid())`).
- **Unique constraints**: `User.email`, `Unit(propertyId, unitNumber)`, `TenantProfile.userId`, `Payment(leaseId, billingMonth)`, plus the partial index `one_active_lease_per_unit`.
- **Check constraints**: `Lease.dueDay` is limited to 1‑28; `Payment.billingMonth` must be the first day of a month (both enforced by `20261116002000_monthly_rent_date_checks/migration.sql`).
- **Foreign‑key actions** are `ON DELETE RESTRICT` (or `ON UPDATE CASCADE` where the migration specifies it). No cascade deletes are defined.

---

## 7. Conclusion and source references

The schema cleanly separates authentication (`User`), property hierarchy (`Property`, `Unit`), tenancy (`TenantProfile`, `Lease`), financial records (`Payment`), and service requests (`MaintenanceRequest`).  This design eliminates redundancy, enforces referential integrity, and satisfies 1NF‑3NF while preserving necessary historical data (e.g., lease‑specific rent) without making unwarranted assumptions.

**Sources (examined on the remote `origin/main`):**
- `backend/prisma/schema.prisma`
- All migration SQL files under `backend/prisma/migrations/`
- `backend/README.md`
- Root `README.md`
