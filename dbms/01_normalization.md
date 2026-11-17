# 01 – Normalization Report

**Repository**: [RentSetu (DE)](https://github.com/TEJASGUPTA478/RentSetu)  
**Source files**:  
- [`backend/prisma/schema.prisma`](https://github.com/TEJASGUPTA478/RentSetu/blob/main/backend/prisma/schema.prisma)  
- [`backend/prisma/migrations/20261116000000_init/migration.sql`](https://github.com/TEJASGUPTA478/RentSetu/blob/main/backend/prisma/migrations/20261116000000_init/migration.sql)  
- [`backend/README.md`](https://github.com/TEJASGUPTA478/RentSetu/blob/main/backend/README.md)  
- Root `README.md`

---

## 1. Purpose and Scope

The RentSetu platform manages residential‑ and commercial‑rental operations.  The data model captures **users and roles**, **properties and their units**, **tenant profiles**, **leases**, **payments**, and **maintenance requests**.  This report analyses **only the persisted relational schema** defined in the Prisma model and the accompanying PostgreSQL migration.  It does **not** consider any checkpoint documents that are missing from the repository, nor does it infer tables that are not present in the schema.

The backend README documents that the Prisma schema is the source of truth for the database; all business‑logic views displayed in the UI are derived from these tables (e.g., formatted addresses, payment status flags, or joined tenant/property/unit/lease display fields are computed at runtime and are **not** stored columns).

---

## 2. Relations and Key Attributes

| Table (Prisma model) | Primary Key | Notable Attributes | Unique / Indexes | Foreign Keys |
|----------------------|-------------|--------------------|------------------|--------------|
| **User** | `id` (UUID) | `email`, `password?`, `role`, `status`, `authProvider`, social‑id fields (`googleId`, `facebookId`, `twitterId`), timestamps | `email` `@unique`, social‑ids `@unique` (when present) | – |
| **TenantProfile** | `id` (UUID) | `firstName`, `lastName`, `phone`, `dob?`, `userId` | `userId` `@unique` (one‑to‑one with `User`) | `userId` → `User.id` |
| **Property** | `id` (UUID) | `name`, `address`, `city`, `state`, `zipCode`, `type` (enum), `verificationStatus` (enum), timestamps | – | – |
| **Unit** | `id` (UUID) | `unitNumber`, `floor?`, `status` (enum), `rentAmount`, `depositAmount`, `propertyId` | Composite unique: `(propertyId, unitNumber)` ensures a property cannot have duplicate unit numbers | `propertyId` → `Property.id` |
| **Lease** | `id` (UUID) | `startDate`, `endDate`, `monthlyRent`, `depositHeld`, `status` (enum), `dueDay`, `unitId`, `tenantProfileId` | – | `unitId` → `Unit.id`; `tenantProfileId` → `TenantProfile.id` |
| **Payment** | `id` (UUID) | `amount`, `billingMonth` (Date, first of month), `paidAt?`, `status` (enum), `leaseId` | Composite unique: `(leaseId, billingMonth)` prevents duplicate billing for the same month | `leaseId` → `Lease.id` |
| **MaintenanceRequest** | `id` (UUID) | `title`, `description`, `priority` (enum), `status` (enum), `createdAt`, `updatedAt`, `unitId`, `tenantProfileId`, `assignedTo?` | – | `unitId` → `Unit.id`; `tenantProfileId` → `TenantProfile.id` |

**Additional constraints observed in the migration**
- A **partial unique index** `one_active_lease_per_unit` (enforced in raw SQL) guarantees that at any time only one lease with `status = 'ACTIVE'` can exist for a given `unitId`.
- Check constraints on `Lease.dueDay` (1‑28) and `Payment.billingMonth` (must be the first day of a month) are defined in `migration.sql`.

---

## 3. Functional Dependencies and Keys

| Dependency | Explanation |
|------------|-------------|
| `User.id →` all other User columns | Primary‑key dependency.
| `User.email → User.id` (and vice‑versa) | `email` is declared `@unique`; therefore it is an alternate candidate key.
| `TenantProfile.userId → TenantProfile.*` | One‑to‑one relationship; `userId` is unique, so it functions as a candidate key for the profile.
| `(Unit.propertyId, Unit.unitNumber) → Unit.*` | Composite unique constraint makes the pair a candidate key for a unit within a property.
| `(Payment.leaseId, Payment.billingMonth) → Payment.*` | Composite unique constraint restricts a lease to a single payment record per billing month.
| `Lease.id → Lease.*` | PK dependency.
| `MaintenanceRequest.id → MaintenanceRequest.*` | PK dependency.

Foreign‑key columns (`propertyId`, `unitId`, `tenantProfileId`, `leaseId`) express *referential integrity* but do **not** themselves constitute functional dependencies from the referenced table to the referencing table.

---

## 4. Normalization Analysis

### 4.1 First Normal Form (1NF)
All tables store atomic values; repeated collections (e.g., a property’s many units) are represented as separate rows in the `Unit` table rather than repeating columns.  Composite primary/unique keys are stored as separate columns, satisfying 1NF.

### 4.2 Second Normal Form (2NF)
All non‑key attributes in each table depend on the **entire** primary key.
- For tables with a single‑column PK (`User`, `Property`, `Unit`, `Lease`, `Payment`, `MaintenanceRequest`) this is trivial.
- The composite unique keys are *not* primary keys; they serve as alternate identifiers.  No non‑key attribute is partially dependent on a subset of a composite primary key because there is no such composite PK.
- The unique constraints `(propertyId, unitNumber)` and `(leaseId, billingMonth)` prevent duplicate identifiers without introducing partial dependencies.

### 4.3 Third Normal Form (3NF)
Each table’s non‑key attributes are **non‑transitively** dependent on the primary key.
- `User` stores only authentication‑related data; profile‑specific fields (name, phone) live in `TenantProfile`.
- `Unit` stores physical/unit‑level data; property‑level data lives in `Property`.
- `Lease` records rent terms and status; monetary snapshots such as `monthlyRent` are stored here because they belong to the lease period, not the unit.
- `Payment` stores billing information; it does not repeat lease or tenant attributes.
- `MaintenanceRequest` captures request details and links to the unit and tenant but does not duplicate lease or property fields.

Because the schema does not encode additional derived attributes (e.g., computed payment status, formatted address), no transitive dependencies are introduced by the stored columns.

### 4.4 Boyce‑Codd Normal Form (BCNF)
BCNF holds for tables where **every determinant is a candidate key**.
- `User`, `Property`, `Unit`, `Lease`, `Payment`, `MaintenanceRequest` satisfy BCNF because their only determinants are their primary keys (or unique alternate keys).
- `TenantProfile` also meets BCNF because `userId` is a unique key that determines the profile.
- The partial unique index `one_active_lease_per_unit` enforces a business rule **outside** the relational normal form; it does not affect BCNF status of the `Lease` table.

---

## 5. Anomalies and Design Rationale

| Anomaly | How the design mitigates it |
|---------|-----------------------------|
| **Insert anomaly** – adding a new unit without a property | `Unit.propertyId` is a non‑nullable foreign key; a unit cannot be inserted unless the referenced `Property` exists.
| **Update anomaly** – changing a tenant’s email | The email is stored only in `User`; updating `User.email` automatically reflects the change for all related profiles, avoiding redundant copies.
| **Delete anomaly** – removing a property that still has units | The foreign‑key `ON DELETE CASCADE` (as defined in the migration) automatically deletes dependent `Unit` rows, preventing orphaned records.
| **Duplicate lease payments** | The composite unique constraint `(leaseId, billingMonth)` guarantees at most one payment per month per lease, eliminating duplicate billing rows.
| **Multiple active leases for a unit** | The partial unique index `one_active_lease_per_unit` (enforced by raw SQL) ensures only one lease with `status = 'ACTIVE'` can reference a given `unitId` at any time.

**Snapshot semantics** – `Lease.monthlyRent` is stored separately from `Unit.rentAmount`.  The schema alone does not specify whether this is a historical snapshot; the design allows the rent amount to be captured at lease inception while the unit’s default rent may change later.  Consequently, the separation is **not** a normalization defect but a deliberate choice to preserve lease‑specific contract terms.

**Maintenance requests** keep their own `status`, timestamps, and optional `assignedTo` fields.  This separation lets multiple requests be recorded for the same unit without altering the `Unit` table, preventing column proliferation and keeping the request lifecycle independent.

---

## 6. Integrity Rules and Limitations

| Rule / Constraint | Defined In |
|-------------------|------------|
| Enum types (`UserRole`, `UserStatus`, `AuthProvider`, `FieldType`, etc.) | `schema.prisma` |
| Primary keys (`@id`) and `@default(uuid())` | `schema.prisma` |
| Unique constraints (`email`, social‑ids, `(propertyId, unitNumber)`, `(leaseId, billingMonth)`) | `schema.prisma` |
| Foreign keys with referential actions (`ON DELETE CASCADE`, `ON DELETE RESTRICT`) | `migration.sql` (generated by Prisma) |
| Partial unique index `one_active_lease_per_unit` | Raw SQL in `migration.sql` |
| Check constraint `Lease.dueDay` between 1 and 28 | `migration.sql` |
| Check constraint `Payment.billingMonth` must be first day of month | `migration.sql` |

The schema does **not** enforce cross‑row consistency such as “a maintenance request’s lease must belong to the same tenant as the unit.”  Such business rules must be upheld by application‑level logic.

Indexes (e.g., on `city`, `verificationStatus`) are present for query performance; they are not part of normalization theory and therefore are not discussed as normal‑form constraints.

---

## 7. Conclusion and Source References

The current RentSetu relational design adheres to 1NF, 2NF, and 3NF, and for the tables examined it satisfies BCNF.  By separating authentication (`User`), tenant‑specific data (`TenantProfile`), property/unit hierarchy, lease agreements, payment records, and maintenance workflows, the schema eliminates unnecessary redundancy while preserving historical information (e.g., lease‑specific rent).  Integrity is reinforced through primary/unique keys, foreign‑key relationships, and explicit database constraints (check constraints, partial unique index).

**Sources** (directly inspected):
- [`backend/prisma/schema.prisma`](https://github.com/TEJASGUPTA478/RentSetu/blob/main/backend/prisma/schema.prisma)
- [`backend/prisma/migrations/20261116000000_init/migration.sql`](https://github.com/TEJASGUPTA478/RentSetu/blob/main/backend/prisma/migrations/20261116000000_init/migration.sql)
- [`backend/README.md`](https://github.com/TEJASGUPTA478/RentSetu/blob/main/backend/README.md)
- Root `README.md`

*The AP repository (`RentSetu_AP_2026`) currently contains only a top‑level README and does not provide the CP1 academic artifacts; this normalization report fulfills the CP1 deliverable for the DBMS component.*