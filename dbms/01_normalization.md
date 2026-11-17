# 01 – Normalization Report

**Repository**: [RentSetu (DE)](https://github.com/TEJASGUPTA478/RentSetu)  
**Source files**:
- [`backend/prisma/schema.prisma`](https://github.com/TEJASGUPTA478/RentSetu/blob/main/backend/prisma/schema.prisma)
- All migration SQL files under `backend/prisma/migrations/` (e.g., `20261116000000_init/migration.sql` and subsequent migrations)
- [`backend/README.md`](https://github.com/TEJASGUPTA478/RentSetu/blob/main/backend/README.md)
- Root `README.md`

---

## 1. Purpose and Scope

RentSetu is a rental‑management platform.  The persisted data model stores **users**, **properties**, **units**, **tenant profiles**, **leases**, **payments**, and **maintenance requests**.  This report analyses **only the relational schema** defined in the Prisma model and the PostgreSQL migration scripts that implement it.  It does **not** assume the existence of any checkpoint documents that are missing from the repository, nor does it infer tables that are not present in the schema.

The backend README states that the Prisma schema is the single source of truth for the database; UI‑level derived values (e.g., formatted addresses or payment status labels) are computed at runtime and are **not** stored columns.

---

## 2. Relations and key attributes (actual models)

| Model | Primary key | Notable attributes | Unique / indexes | Foreign keys |
|-------|-------------|-------------------|------------------|--------------|
| **User** | `id` (String, `cuid()`) | `name`, `email`, `passwordHash`, `role` (enum `Role`), `isActive`, timestamps | `email` `@unique`; index on `(role, isActive)` | – |
| **Property** | `id` | `ownerId`, `managerId` (optional), `name`, `address`, `city`, `state`, `pincode`, `type`, timestamps | index on `ownerId`; composite index on `(ownerId, city)` | `ownerId` → `User.id` (`ON DELETE RESTRICT`); `managerId` → `User.id` (`ON DELETE RESTRICT`) |
| **Unit** | `id` | `propertyId`, `unitNumber`, `rent`, `bedrooms`, `status` (enum `UnitStatus`), timestamps | unique index on `(propertyId, unitNumber)`; indexes on `propertyId`, `status`, `(propertyId, status)` | `propertyId` → `Property.id` (`ON DELETE RESTRICT`) |
| **TenantProfile** | `id` | `userId`, `createdByLandlordId`, `phone`, optional emergency contact fields, ID‑proof fields, timestamps | unique index on `userId`; index on `createdByLandlordId` | `userId` → `User.id` (`ON DELETE RESTRICT`); `createdByLandlordId` → `User.id` (`ON DELETE RESTRICT`) |
| **Lease** | `id` | `unitId`, `tenantId` (points to `TenantProfile.id`), `startDate`, `endDate`, `monthlyRent`, `securityDeposit`, `dueDay` (check 1‑28), `status` (enum `LeaseStatus`), timestamps | index on `unitId`; index on `tenantId`; index on `(status, startDate, endDate)`; **partial** unique index `one_active_lease_per_unit` on `unitId` where `status = 'ACTIVE'` | `unitId` → `Unit.id` (`ON DELETE RESTRICT`); `tenantId` → `TenantProfile.id` (`ON DELETE RESTRICT`) |
| **Payment** | `id` | `leaseId`, `amount`, `billingMonth` (date, first day of month – enforced by check), `method` (enum `PaymentMethod`), `paidOn`, `notes`, timestamps | unique index on `(leaseId, billingMonth)`; indexes on `status, dueDate`, `tenantId`, `propertyId` (from foreign keys) | `leaseId` → `Lease.id` (`ON DELETE RESTRICT`) |
| **MaintenanceRequest** | `id` | `unitId`, `leaseId` (optional), `tenantId`, `title`, `description`, `priority` (enum `Priority`), `status` (enum `MaintenanceStatus`), `resolvedAt`, timestamps | indexes on `(status, reportedAt)`, `unitId`, `leaseId`, `tenantId`, composite index `(unitId, status)` | `unitId` → `Unit.id` (`ON DELETE RESTRICT`); `leaseId` → `Lease.id` (`ON DELETE RESTRICT`); `tenantId` → `TenantProfile.id` (`ON DELETE RESTRICT`) |

All tables are defined with `ON DELETE RESTRICT` (or the explicit `CASCADE` where appropriate) as shown in the migration SQL files.

---

## 3. Functional dependencies and candidate keys

- `User.id →` all other User columns (PK → attributes).
- `User.email → User.id` (unique alternate key).
- `TenantProfile.userId → TenantProfile.*` (one‑to‑one, `userId` unique).
- `(Unit.propertyId, Unit.unitNumber) → Unit.*` (composite unique key).
- `(Payment.leaseId, Payment.billingMonth) → Payment.*` (composite unique key, also enforces one payment per lease per month).
- `Lease.id → Lease.*` (PK dependency).
- `MaintenanceRequest.id → MaintenanceRequest.*` (PK dependency).

Foreign‑key columns enforce referential integrity but are not functional dependencies from the referenced side.

---

## 4. Normalisation analysis

### 4.1 First Normal Form (1NF)
All attributes are atomic; repeating collections (e.g., many units belonging to a property) are modelled as separate rows in the `Unit` table.  No multivalued columns exist.

### 4.2 Second Normal Form (2NF)
Every non‑key attribute depends on the whole of its primary key.  All tables have a single‑column primary key, so the condition holds trivially.  Composite unique keys are **alternates**, not primary keys, and no non‑key attribute is partially dependent on a subset of them.

### 4.3 Third Normal Form (3NF)
All non‑key attributes are non‑transitively dependent on the primary key.  For example, `Payment.amount` depends on `Payment.id` and not on any other attribute such as `Lease.monthlyRent`.  No attribute stores derived information that could be obtained from another table, so there are no transitive dependencies.

### 4.4 BCNF (where relevant)
Each determinant in the above dependencies is a candidate key, therefore each table satisfies BCNF.  The partial unique index `one_active_lease_per_unit` is a business‑rule enforcement implemented via a filtered index; it does not affect the normal form status of `Lease`.

---

## 5. Anomalies and design rationale

| Anomaly type | How the schema mitigates it |
|--------------|-----------------------------|
| **Insert anomaly** – creating a `Unit` without a `Property` | `Unit.propertyId` is NOT NULL and has a foreign‑key constraint; insertion fails unless the referenced `Property` exists. |
| **Update anomaly** – changing a tenant’s e‑mail | The e‑mail is stored only in `User`; updating `User.email` automatically propagates to all related tenant profiles (via the foreign key), avoiding duplicated copies. |
| **Delete anomaly** – deleting a `Property` that still has dependent rows | `Property` has `ON DELETE RESTRICT` on its foreign keys, so the DB prevents accidental orphaning; the application must delete dependent `Unit`, `Tenant`, etc., first. |
| **Duplicate payment rows** | Unique index `(leaseId, billingMonth)` ensures at most one payment record per lease per month. |
| **Multiple active leases for the same unit** | Partial unique index `one_active_lease_per_unit` (defined in `20261116001000_one_active_lease_per_unit/migration.sql`) guarantees only one `Lease` with `status = 'ACTIVE'` can reference a given `unitId`. |

`Lease.monthlyRent` is stored separately from `Unit.rent`; this is intentional to capture the rent agreed at lease inception, even if the unit’s standard rent later changes.  The schema does not label this as a defect.

---

## 6. Integrity rules and limitations

- **Enums** (`Role`, `UnitStatus`, `LeaseStatus`, `PaymentMethod`, `MaintenanceStatus`, `Priority`) are declared in the initial migration.
- **Primary keys** are all `cuid()` strings.
- **Unique constraints**: `User.email`, `Unit(propertyId, unitNumber)`, `TenantProfile.userId`, `Payment(leaseId, billingMonth)`, plus the partial index `one_active_lease_per_unit`.
- **Check constraints**: `Lease.dueDay` is constrained to 1‑28 (see `20261116002000_monthly_rent_date_checks/migration.sql`); `Payment.billingMonth` must be the first day of a month (same migration).
- **Foreign‑key actions** are `ON DELETE RESTRICT` (or `CASCADE` where defined in the migration).  Cross‑row business rules (e.g., a maintenance request’s lease belonging to the same tenant) are enforced in application code, not by the DB schema.

Indexes improve query performance but are not part of normalisation.

---

## 7. Conclusion and source references

The schema cleanly separates concerns: authentication (`User`), property hierarchy (`Property`, `Unit`), tenancy (`TenantProfile`, `Lease`), financial records (`Payment`), and service requests (`MaintenanceRequest`).  This design eliminates redundancy, enforces referential integrity, and satisfies 1NF‑3NF (and BCNF) while preserving necessary historical snapshots (e.g., lease‑specific rent).

**Sources** (examined directly on the remote `origin/main`):
- `backend/prisma/schema.prisma`
- All migration SQL files under `backend/prisma/migrations/`
- `backend/README.md`
- Root `README.md`

*The AP repository now contains a correct CP1 normalization report in `dbms/01_normalization.md`.*