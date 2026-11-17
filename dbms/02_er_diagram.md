# RENTSETU RELATIONAL DATABASE ARCHITECTURE

## 1. Overview & Architectural Domains

The RentSetu relational database schema is structured into 4 interconnected domains comprising 7 core tables:

1. **Identity & Access**: `users`, `tenant_profiles`
2. **Property Portfolio**: `properties`, `units`
3. **Lease & Rentals**: `leases`, `payments`
4. **Maintenance & Service**: `maintenance_requests`

---

## 2. Mermaid Entity-Relationship Diagram

```mermaid
erDiagram
    users ||--|| tenant_profiles : "has profile"
    users ||--o{ properties : "owns / manages"
    properties ||--o{ units : "contains"
    units ||--o{ leases : "leases"
    tenant_profiles ||--o{ leases : "leases"
    leases ||--o{ payments : "has"
    units ||--o{ maintenance_requests : "receives"
    leases ||--o{ maintenance_requests : "may have"
    tenant_profiles ||--o{ maintenance_requests : "files"

    users {
        string id PK
        string name
        string email
        string passwordHash
        Role role
        boolean isActive
    }

    tenant_profiles {
        string id PK
        string userId FK
        string createdByLandlordId FK
        string phone
    }

    properties {
        string id PK
        string ownerId FK
        string managerId FK
        string name
        string address
        string city
        string state
        string pincode
        string type
    }

    units {
        string id PK
        string propertyId FK
        string unitNumber
        decimal rent
        int bedrooms
        UnitStatus status
    }

    leases {
        string id PK
        string unitId FK
        string tenantId FK
        date startDate
        date endDate
        decimal monthlyRent
        decimal securityDeposit
        int dueDay
        LeaseStatus status
    }

    payments {
        string id PK
        string leaseId FK
        date billingMonth
        decimal amount
        PaymentMethod method
        date paidOn
    }

    maintenance_requests {
        string id PK
        string unitId FK
        string leaseId FK
        string tenantId FK
        string title
        string description
        Priority priority
        MaintenanceStatus status
    }
```

---

## 3. Domain Grouping

### Identity & Access
- `users`
- `tenant_profiles`

### Property Portfolio
- `properties`
- `units`

### Lease & Rentals
- `leases`
- `payments`

### Maintenance & Service
- `maintenance_requests`

---

## 4. Detailed Data Dictionary

### users
| Column | Type | Constraints | Description |
|---|---|---|---|
| id | string | PK | Unique user identifier |
| name | string | NOT NULL | Full name of the user |
| email | string | UNIQUE, NOT NULL | Email address used for login |
| passwordHash | string | NOT NULL | Hashed password for authentication |
| role | Role | NOT NULL | User role such as landlord or tenant |
| isActive | boolean | DEFAULT true | Whether the user account is active |

### tenant_profiles
| Column | Type | Constraints | Description |
|---|---|---|---|
| id | string | PK | Tenant profile identifier |
| userId | string | FK -> users.id | Link to the user account |
| createdByLandlordId | string | FK -> users.id | Landlord or manager who created the profile |
| phone | string | NULL | Tenant contact number |

### properties
| Column | Type | Constraints | Description |
|---|---|---|---|
| id | string | PK | Unique property identifier |
| ownerId | string | FK -> users.id | Property owner |
| managerId | string | FK -> users.id | Property manager assigned to this property |
| name | string | NOT NULL | Property or building name |
| address | string | NOT NULL | Street address |
| city | string | NOT NULL | City |
| state | string | NOT NULL | State |
| pincode | string | NOT NULL | Postal code |
| type | string | NOT NULL | Property category such as apartment or villa |

### units
| Column | Type | Constraints | Description |
|---|---|---|---|
| id | string | PK | Unit identifier |
| propertyId | string | FK -> properties.id | Parent property |
| unitNumber | string | NOT NULL | Unit number or suite name |
| rent | decimal | NOT NULL | Monthly rent |
| bedrooms | int | NOT NULL | Number of bedrooms |
| status | UnitStatus | NOT NULL | Unit availability status |

### leases
| Column | Type | Constraints | Description |
|---|---|---|---|
| id | string | PK | Lease identifier |
| unitId | string | FK -> units.id | Rented unit |
| tenantId | string | FK -> tenant_profiles.id | Tenant on this lease |
| startDate | date | NOT NULL | Lease start date |
| endDate | date | NOT NULL | Lease end date |
| monthlyRent | decimal | NOT NULL | Monthly rent for the lease |
| securityDeposit | decimal | NOT NULL | Security deposit charged |
| dueDay | int | NOT NULL | Rent due day of the month |
| status | LeaseStatus | NOT NULL | Lease state such as active or expired |

### payments
| Column | Type | Constraints | Description |
|---|---|---|---|
| id | string | PK | Payment identifier |
| leaseId | string | FK -> leases.id | Lease associated with the payment |
| billingMonth | date | NOT NULL | The month for which payment is made |
| amount | decimal | NOT NULL | Amount paid |
| method | PaymentMethod | NOT NULL | Payment method such as UPI or bank transfer |
| paidOn | date | NOT NULL | Payment date |

### maintenance_requests
| Column | Type | Constraints | Description |
|---|---|---|---|
| id | string | PK | Maintenance request identifier |
| unitId | string | FK -> units.id | Affected unit |
| leaseId | string | FK -> leases.id | Related lease |
| tenantId | string | FK -> tenant_profiles.id | Tenant who submitted the request |
| title | string | NOT NULL | Short request title |
| description | text | NOT NULL | Detailed issue description |
| priority | Priority | NOT NULL | Request urgency |
| status | MaintenanceStatus | NOT NULL | Current request stage |

---

## 5. Relationship Notes

- A user can own or manage many properties.
- Each property contains multiple units.
- A unit can be linked to multiple leases over time.
- A tenant profile can hold multiple leases.
- A lease may have multiple payment records.
- A unit or lease can generate multiple maintenance requests.

This structure supports the complete rent lifecycle: onboarding, property management, lease assignment, rent tracking, and maintenance resolution.
