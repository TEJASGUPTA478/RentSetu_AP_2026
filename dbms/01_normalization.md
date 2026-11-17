# 01 – Normalization Report

**Repository**: [RentSetu (DE)](https://github.com/TEJASGUPTA478/RentSetu)
**Source files**:

- [`backend/prisma/schema.prisma`](https://github.com/TEJASGUPTA478/RentSetu/blob/main/backend/prisma/schema.prisma)
- All migration SQL files under `backend/prisma/migrations/` (e.g., `20261116000000_init/migration.sql`, `20261116001000_one_active_lease_per_unit/migration.sql`, `20261116002000_monthly_rent_date_checks/migration.sql`)
- [`backend/README.md`](https://github.com/TEJASGUPTA478/RentSetu/blob/main/backend/README.md)

---

## 1. purpose and scope

The backend uses a PostgreSQL database driven by a Prisma schema. This report analyses the **relational schema** (tables, columns, keys, constraints, indexes) that the migrations create. It does **not** assume any UI‑level data that is not stored in the database, and it does not claim that the UI is wired to these tables (the README notes that the frontend currently uses mock data).

---

## 2. relations and key attributes (actual models)

| Model                  | Primary key                       | Notable attributes                                                                                                                                                                                  | Unique / indexes                                                                                                                                                                                                                                      | Foreign keys                                                                                                                                       |
| ---------------------- | --------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------- |
| **User**               | `id` (String, `@default(uuid())`) | `name`, `email`, `passwordHash`, `role` (enum `Role`), `isActive`, timestamps                                                                                                                       | `email` `@unique`; index on `(role, isActive)`                                                                                                                                                                                                        | –                                                                                                                                                  |
| **Property**           | `id`                              | `ownerId`, optional `managerId`, `name`, `address`, `city`, `state`, `pincode`, `type`, timestamps                                                                                                  | index on `ownerId`; index on `managerId`; composite index on `(ownerId, city)`                                                                                                                                                                        | `ownerId` → `User.id` (`ON DELETE RESTRICT`); `managerId` → `User.id` (`ON DELETE RESTRICT`)                                                       |
| **Unit**               | `id`                              | `propertyId`, `unitNumber`, `rent`, `bedrooms`, `status` (enum `UnitStatus`), timestamps                                                                                                            | unique index on `(propertyId, unitNumber)`; indexes on `propertyId`, `status`, `(propertyId, status)`                                                                                                                                                 | `propertyId` → `Property.id` (`ON DELETE RESTRICT`)                                                                                                |
| **TenantProfile**      | `id`                              | `userId`, `createdByLandlordId`, `phone`, optional emergency‑contact fields, optional ID‑proof fields, timestamps                                                                                   | `userId` `@unique`; index on `createdByLandlordId`                                                                                                                                                                                                    | `userId` → `User.id` (`ON DELETE RESTRICT`); `createdByLandlordId` → `User.id` (`ON DELETE RESTRICT`)                                              |
| **Lease**              | `id`                              | `unitId`, `tenantId` (points to `TenantProfile.id`), `startDate`, `endDate`, `monthlyRent`, `securityDeposit`, `dueDay` (check 1‑28), `status` (enum `LeaseStatus`), timestamps                     | index on `unitId`; index on `tenantId`; index on `status`; index on `(status, startDate, endDate)`; **partial** unique index `one_active_lease_per_unit` on `unitId` where `status = 'ACTIVE'` (migration `20261116001000_one_active_lease_per_unit`) | `unitId` → `Unit.id` (`ON DELETE RESTRICT`); `tenantId` → `TenantProfile.id` (`ON DELETE RESTRICT`)                                                |
| **Payment**            | `id`                              | `leaseId`, `billingMonth` (first day of month – enforced by migration `20261116002000_monthly_rent_date_checks`), `amount`, `method` (enum `PaymentMethod`), `paidOn`, optional `notes`, timestamps | unique index on `(leaseId, billingMonth)`; indexes on `leaseId`, `billingMonth`, `paidOn`                                                                                                                                                             | `leaseId` → `Lease.id` (`ON DELETE RESTRICT`)                                                                                                      |
| **MaintenanceRequest** | `id`                              | `unitId`, optional `leaseId`, `tenantId`, `title`, `description`, `priority` (enum `Priority`), `status` (enum `MaintenanceStatus`), optional `resolvedAt`, timestamps                              | indexes on `unitId`, `leaseId`, `tenantId`, `status`, composite index `(unitId, status)`                                                                                                                                                              | `unitId` → `Unit.id` (`ON DELETE RESTRICT`); `leaseId` → `Lease.id` (`ON DELETE RESTRICT`); `tenantId` → `TenantProfile.id` (`ON DELETE RESTRICT`) |

All foreign‑key actions are `ON DELETE RESTRICT` (the migrations never define `CASCADE`).

---

## 3. functional dependencies and candidate keys

- **User**: `id →` all other User columns (primary‑key dependency). Alternate key: `email → id` (unique).
- **Property**: `id →` all other Property columns. No alternate candidate keys.
- **Unit**: `id →` all other Unit columns. Alternate composite key: `(propertyId, unitNumber) → Unit.*` (unique index).
- **TenantProfile**: `id →` all other TenantProfile columns. Alternate key: `userId → TenantProfile.*` (unique one‑to‑one).
- **Lease**: `id →` all other Lease columns. No alternate keys beyond the partial unique index `one_active_lease_per_unit` (business rule, not a functional dependency).
- **Payment**: `id →` all other Payment columns. Alternate composite key: `(leaseId, billingMonth) → Payment.*` (unique index guarantees at most one payment per lease per month).
- **MaintenanceRequest**: `id →` all other MaintenanceRequest columns. No alternate keys.

Foreign‑key columns enforce referential integrity but do **not** create functional dependencies from the referenced side to the referencing side.

---

## 4. normalisation analysis

### 4.1 First Normal Form (1NF)

A teaching example: imagine a single logical rental record that repeats the property address, unit number, lease dates, and multiple payment rows. In 1NF each repeating piece of information must be atomised into its own row. The schema achieves this by separating **Property**, **Unit**, **Lease**, **Payment**, and **MaintenanceRequest** into distinct tables, each with atomic columns.

### 4.2 Second Normal Form (2NF)

2NF requires that every non‑key attribute be fully dependent on **the whole** of any candidate key.

- **Unit**: The candidate key `(propertyId, unitNumber)` uniquely identifies a unit. Neither `propertyId` alone nor `unitNumber` alone determines any non‑key attribute (e.g., `rent` or `bedrooms`). Therefore all non‑key attributes (`rent`, `bedrooms`, `status`, timestamps) depend on the **entire** composite key, satisfying 2NF.
- **Payment**: The candidate key `(leaseId, billingMonth)` uniquely identifies a payment. `leaseId` alone does not determine `amount` or `paidOn`; `billingMonth` alone does not determine those either. Thus `amount`, `method`, `paidOn`, `notes`, and timestamps depend on the full composite key, meeting 2NF.

All other tables have a single‑column primary key, so 2NF holds trivially for them.

### 4.3 Third Normal Form (3NF)

3NF demands that non‑key attributes be non‑transitively dependent on any candidate key.

- In **User**, `email`, `name`, etc. depend directly on `id`; there is no attribute that depends on another non‑key attribute.
- In **Property**, `ownerId` and `managerId` are foreign keys, but attributes such as `name` or `address` do not depend on them; they depend directly on `id`.
- In **Unit**, `rent` and `bedrooms` depend on the unit identified by `(propertyId, unitNumber)` (or `id`) and not on `status`.
- In **Lease**, `monthlyRent`, `securityDeposit`, `dueDay` depend on the lease identified by `id`; they are not derived from `unitId` or `tenantId`.
- In **Payment**, `amount`, `method`, `paidOn` depend on the payment identified by `(leaseId, billingMonth)`; they are not derived from the lease’s `monthlyRent`.
- In **TenantProfile**, both `id` and the unique `userId` serve as candidate keys. All other attributes (`createdByLandlordId`, `phone`, etc.) depend directly on either of these keys and there are no transitive dependencies.
- In **MaintenanceRequest**, `title`, `description`, `priority`, `status` depend on the request’s `id`.

No transitive dependencies are present within any relation. Where business rules exist (e.g., a unit should have at most one active lease), the schema enforces them via a partial unique index rather than via derived columns, so they do not violate 3NF.

---

## 5. design rationale and anomaly mitigation

| Anomaly                                                                  | Mitigation in the schema                                                                                                                                                                                   |
| ------------------------------------------------------------------------ | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Insert anomaly** – creating a `Unit` without a `Property`              | `Unit.propertyId` is NOT NULL with a foreign‑key (`ON DELETE RESTRICT`).                                                                                                                                   |
| **Update anomaly** – changing a tenant’s e‑mail                          | The e‑mail lives only in `User`; updating `User.email` automatically affects any join that reads the tenant’s email. No copy exists in `TenantProfile`.                                                    |
| **Delete anomaly** – deleting a `Property` that still has dependent rows | `Unit.propertyId` with `ON DELETE RESTRICT` prevents deleting a Property referenced by Units. `Property.ownerId` and `managerId` point to User and do not protect Units or `TenantProfile` from orphaning. |
| **Duplicate payment rows**                                               | Unique index `(leaseId, billingMonth)` guarantees at most one payment per lease per month.                                                                                                                 |
| **Multiple active leases for the same unit**                             | Partial unique index `one_active_lease_per_unit` (migration `20261116001000_one_active_lease_per_unit`) enforces a single `Lease` with `status = 'ACTIVE'` per `unitId`.                                   |

By normalising the data into these distinct tables we avoid the classic insertion, update, and deletion anomalies that arise when repeating groups or derived attributes are stored together.

---

## 6. integrity rules and limitations

- **Enums** (`Role`, `UnitStatus`, `LeaseStatus`, `PaymentMethod`, `MaintenanceStatus`, `Priority`) are declared in the initial migration.
- **Primary keys** are all UUIDs (`@default(uuid())`).
- **Unique constraints**: `User.email`, `Unit(propertyId, unitNumber)`, `TenantProfile.userId`, `Payment(leaseId, billingMonth)`, plus the partial index `one_active_lease_per_unit`.
- **Check constraints**: `Lease.dueDay` is limited to 1‑28; `Payment.billingMonth` must be the first day of a month (both enforced by `20261116002000_monthly_rent_date_checks/migration.sql`).
- **Foreign‑key actions** are `ON DELETE RESTRICT` (or `ON UPDATE CASCADE` where the migration specifies it). No cascade deletes are defined.

---

## 7. conclusion and source references

The schema stores both `Unit.rent` and `Lease.monthlyRent`, but the schema does not define a business relationship between these two fields.

**Sources (examined on the remote `origin/main`):**

- `backend/prisma/schema.prisma`
- All migration SQL files under `backend/prisma/migrations/`
- `backend/README.md`
- Root `README.md`
