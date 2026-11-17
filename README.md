# RentSetu_AP_2026
RentSetu is a rent and property management backend built with Node.js, Express, and PostgreSQL. It lets landlords manage properties, units, tenants, leases, and rent payments, while tenants view leases, check payment history, and raise maintenance requests. Includes role-based access.

## CP1 Deliverables

- **DBMS Normalization**: `dbms/01_normalization.md` – normalization report for the seven-table PostgreSQL schema.

## CP2 Deliverables

- **ER Diagram (PNG)**: `dbms/02_er_diagram.png` – visual entity‑relationship diagram of the database schema.
- **ER Diagram (Mermaid source)**: `dbms/02_er_diagram.md` – Mermaid representation and data dictionary for the same schema.
- **PostgreSQL Schema**: `dbms/03_schema.sql` – full `CREATE TABLE` statements, enums, constraints, and indexes matching the Prisma model.

## CP3 Deliverables

- **Application SQL Queries**: `dbms/04_queries.sql` – complete catalog of all application queries across auth, properties, units, tenants, leases, payments, maintenance, and dashboard analytics, utilizing JOINs where possible and marked with `-- READ` or `-- WRITE`.
