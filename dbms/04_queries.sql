-- ============================================================================
-- RentSetu Database Queries
-- File: dbms/04_queries.sql
-- Description: Complete set of SQL queries used by the RentSetu application,
--              covering authentication, property management, units, tenants,
--              leases, payments, maintenance requests, and dashboard analytics.
--              Every query utilizes JOINs where possible to eliminate N+1 roundtrips.
--              Each query is explicitly designated as -- READ or -- WRITE.
-- ============================================================================

-- ============================================================================
-- SECTION 1: AUTHENTICATION & USER MANAGEMENT
-- ============================================================================

-- 1.1 Check if an account already exists with the given email during registration
-- READ
SELECT 
    u."id",
    u."name",
    u."email",
    u."role",
    u."isActive"
FROM "User" u
WHERE LOWER(TRIM(u."email")) = LOWER(TRIM($1));

-- 1.2 Register a new landlord user account
-- WRITE
INSERT INTO "User" (
    "id",
    "name",
    "email",
    "passwordHash",
    "role",
    "isActive",
    "createdAt",
    "updatedAt"
) VALUES (
    $1,                -- id (UUID text)
    TRIM($2),          -- name
    LOWER(TRIM($3)),   -- email
    $4,                -- passwordHash (bcrypt)
    'LANDLORD',        -- default role for public registration
    TRUE,
    CURRENT_TIMESTAMP,
    CURRENT_TIMESTAMP
)
RETURNING "id", "name", "email", "role", "isActive", "createdAt";

-- 1.3 Authenticate/login: find user by email with associated tenant profile if any
-- READ
SELECT 
    u."id" AS "userId",
    u."name",
    u."email",
    u."passwordHash",
    u."role",
    u."isActive",
    tp."id" AS "tenantProfileId",
    tp."phone",
    tp."idProofType",
    tp."idProofNumber"
FROM "User" u
LEFT JOIN "TenantProfile" tp ON tp."userId" = u."id"
WHERE LOWER(TRIM(u."email")) = LOWER(TRIM($1));

-- 1.4 Get current authenticated user profile (`getMe`) with active lease, unit, and property
-- READ
SELECT 
    u."id" AS "userId",
    u."name",
    u."email",
    u."role",
    u."isActive",
    u."createdAt",
    tp."id" AS "tenantProfileId",
    tp."phone",
    tp."emergencyContactName",
    tp."emergencyContactPhone",
    l."id" AS "activeLeaseId",
    l."startDate" AS "leaseStartDate",
    l."endDate" AS "leaseEndDate",
    l."monthlyRent" AS "leaseMonthlyRent",
    l."dueDay" AS "leaseDueDay",
    l."status" AS "leaseStatus",
    un."id" AS "unitId",
    un."unitNumber",
    p."id" AS "propertyId",
    p."name" AS "propertyName",
    p."address" AS "propertyAddress",
    p."city" AS "propertyCity"
FROM "User" u
LEFT JOIN "TenantProfile" tp ON tp."userId" = u."id"
LEFT JOIN "Lease" l ON l."tenantId" = tp."id" AND l."status" = 'ACTIVE'
LEFT JOIN "Unit" un ON un."id" = l."unitId"
LEFT JOIN "Property" p ON p."id" = un."propertyId"
WHERE u."id" = $1 AND u."isActive" = TRUE;

-- 1.5 Verify existing password hash before changing password
-- READ
SELECT 
    u."id",
    u."passwordHash"
FROM "User" u
WHERE u."id" = $1;

-- 1.6 Update user password
-- WRITE
UPDATE "User"
SET 
    "passwordHash" = $2,
    "updatedAt" = CURRENT_TIMESTAMP
WHERE "id" = $1;

-- 1.7 Toggle user account active status (Admin / Account deactivation)
-- WRITE
UPDATE "User"
SET 
    "isActive" = $2,
    "updatedAt" = CURRENT_TIMESTAMP
WHERE "id" = $1
RETURNING "id", "email", "isActive", "updatedAt";


-- ============================================================================
-- SECTION 2: PROPERTY MANAGEMENT
-- ============================================================================

-- 2.1 List properties for a landlord/manager with owner, manager, and aggregated unit stats
-- READ
SELECT 
    p."id" AS "propertyId",
    p."name",
    p."address",
    p."city",
    p."state",
    p."pincode",
    p."type",
    p."createdAt",
    p."updatedAt",
    owner."id" AS "ownerId",
    owner."name" AS "ownerName",
    owner."email" AS "ownerEmail",
    manager."id" AS "managerId",
    manager."name" AS "managerName",
    manager."email" AS "managerEmail",
    COUNT(un."id")::INT AS "totalUnits",
    COUNT(CASE WHEN un."status" = 'OCCUPIED' THEN 1 END)::INT AS "occupiedUnits",
    COUNT(CASE WHEN un."status" = 'VACANT' THEN 1 END)::INT AS "vacantUnits",
    COALESCE(SUM(un."rent"), 0.00) AS "totalRent"
FROM "Property" p
INNER JOIN "User" owner ON owner."id" = p."ownerId"
LEFT JOIN "User" manager ON manager."id" = p."managerId"
LEFT JOIN "Unit" un ON un."propertyId" = p."id"
WHERE 
    (($1 = 'LANDLORD' AND p."ownerId" = $2) OR ($1 = 'MANAGER' AND p."managerId" = $2))
    AND ($3::TEXT IS NULL OR LOWER(p."city") = LOWER($3))
    AND ($4::TEXT IS NULL OR LOWER(p."type") = LOWER($4))
    AND (
        $5::TEXT IS NULL 
        OR p."name" ILIKE '%' || $5 || '%' 
        OR p."address" ILIKE '%' || $5 || '%' 
        OR p."city" ILIKE '%' || $5 || '%'
    )
GROUP BY 
    p."id", 
    owner."id", 
    manager."id"
ORDER BY p."createdAt" DESC
LIMIT $6 OFFSET $7;

-- 2.2 Count total properties matching filter (for pagination metadata)
-- READ
SELECT COUNT(p."id")::INT AS "total"
FROM "Property" p
WHERE 
    (($1 = 'LANDLORD' AND p."ownerId" = $2) OR ($1 = 'MANAGER' AND p."managerId" = $2))
    AND ($3::TEXT IS NULL OR LOWER(p."city") = LOWER($3))
    AND ($4::TEXT IS NULL OR LOWER(p."type") = LOWER($4))
    AND (
        $5::TEXT IS NULL 
        OR p."name" ILIKE '%' || $5 || '%' 
        OR p."address" ILIKE '%' || $5 || '%' 
        OR p."city" ILIKE '%' || $5 || '%'
    );

-- 2.3 Get property by ID with owner, manager, and detailed unit listings
-- READ
SELECT 
    p."id" AS "propertyId",
    p."name",
    p."address",
    p."city",
    p."state",
    p."pincode",
    p."type",
    p."ownerId",
    owner."name" AS "ownerName",
    owner."email" AS "ownerEmail",
    p."managerId",
    manager."name" AS "managerName",
    manager."email" AS "managerEmail",
    un."id" AS "unitId",
    un."unitNumber",
    un."rent",
    un."bedrooms",
    un."status" AS "unitStatus",
    un."createdAt" AS "unitCreatedAt"
FROM "Property" p
INNER JOIN "User" owner ON owner."id" = p."ownerId"
LEFT JOIN "User" manager ON manager."id" = p."managerId"
LEFT JOIN "Unit" un ON un."propertyId" = p."id"
WHERE p."id" = $1
ORDER BY un."unitNumber" ASC;

-- 2.4 Verify tenant authorization to access property details via active lease
-- READ
SELECT 1 AS "authorized"
FROM "Lease" l
INNER JOIN "Unit" u ON u."id" = l."unitId"
INNER JOIN "TenantProfile" tp ON tp."id" = l."tenantId"
WHERE tp."userId" = $1 
  AND u."propertyId" = $2
LIMIT 1;

-- 2.5 Validate assigned property manager exists and has appropriate role
-- READ
SELECT "id", "name", "email", "role"
FROM "User"
WHERE "id" = $1 AND "role" IN ('MANAGER', 'LANDLORD') AND "isActive" = TRUE;

-- 2.6 Create a new property
-- WRITE
INSERT INTO "Property" (
    "id",
    "ownerId",
    "managerId",
    "name",
    "address",
    "city",
    "state",
    "pincode",
    "type",
    "createdAt",
    "updatedAt"
) VALUES (
    $1, $2, $3, $4, $5, $6, $7, $8, $9, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP
)
RETURNING *;

-- 2.7 Fetch property owner and manager for permission check
-- READ
SELECT "id", "ownerId", "managerId"
FROM "Property"
WHERE "id" = $1;

-- 2.8 Update property details
-- WRITE
UPDATE "Property"
SET 
    "name" = COALESCE($2, "name"),
    "address" = COALESCE($3, "address"),
    "city" = COALESCE($4, "city"),
    "state" = COALESCE($5, "state"),
    "pincode" = COALESCE($6, "pincode"),
    "type" = COALESCE($7, "type"),
    "managerId" = CASE WHEN $8::BOOLEAN THEN $9 ELSE "managerId" END,
    "updatedAt" = CURRENT_TIMESTAMP
WHERE "id" = $1
RETURNING *;

-- 2.9 Check if property has existing units before deletion
-- READ
SELECT 
    p."id",
    COUNT(u."id")::INT AS "unitCount"
FROM "Property" p
LEFT JOIN "Unit" u ON u."propertyId" = p."id"
WHERE p."id" = $1
GROUP BY p."id";

-- 2.10 Delete a property
-- WRITE
DELETE FROM "Property"
WHERE "id" = $1 AND "ownerId" = $2;


-- ============================================================================
-- SECTION 3: UNIT MANAGEMENT
-- ============================================================================

-- 3.1 List units with property info, current active lease, and tenant details
-- READ
SELECT 
    u."id" AS "unitId",
    u."unitNumber",
    u."rent",
    u."bedrooms",
    u."status" AS "unitStatus",
    u."createdAt",
    u."updatedAt",
    p."id" AS "propertyId",
    p."name" AS "propertyName",
    p."address" AS "propertyAddress",
    p."city" AS "propertyCity",
    p."type" AS "propertyType",
    l."id" AS "activeLeaseId",
    l."startDate" AS "leaseStartDate",
    l."endDate" AS "leaseEndDate",
    l."monthlyRent" AS "leaseMonthlyRent",
    l."dueDay" AS "leaseDueDay",
    tp."id" AS "tenantId",
    tp."phone" AS "tenantPhone",
    tu."id" AS "tenantUserId",
    tu."name" AS "tenantName",
    tu."email" AS "tenantEmail"
FROM "Unit" u
INNER JOIN "Property" p ON p."id" = u."propertyId"
LEFT JOIN "Lease" l ON l."unitId" = u."id" AND l."status" = 'ACTIVE'
LEFT JOIN "TenantProfile" tp ON tp."id" = l."tenantId"
LEFT JOIN "User" tu ON tu."id" = tp."userId"
WHERE 
    (($1 = 'LANDLORD' AND p."ownerId" = $2) OR ($1 = 'MANAGER' AND p."managerId" = $2))
    AND ($3::TEXT IS NULL OR u."propertyId" = $3)
    AND ($4::"UnitStatus" IS NULL OR u."status" = $4)
    AND (
        $5::TEXT IS NULL 
        OR u."unitNumber" ILIKE '%' || $5 || '%' 
        OR p."name" ILIKE '%' || $5 || '%'
    )
ORDER BY p."name" ASC, u."unitNumber" ASC
LIMIT $6 OFFSET $7;

-- 3.2 Count units matching filter for pagination
-- READ
SELECT COUNT(u."id")::INT AS "total"
FROM "Unit" u
INNER JOIN "Property" p ON p."id" = u."propertyId"
WHERE 
    (($1 = 'LANDLORD' AND p."ownerId" = $2) OR ($1 = 'MANAGER' AND p."managerId" = $2))
    AND ($3::TEXT IS NULL OR u."propertyId" = $3)
    AND ($4::"UnitStatus" IS NULL OR u."status" = $4)
    AND (
        $5::TEXT IS NULL 
        OR u."unitNumber" ILIKE '%' || $5 || '%' 
        OR p."name" ILIKE '%' || $5 || '%'
    );

-- 3.3 Get unit by ID with property, active lease, and full lease history
-- READ
SELECT 
    u."id" AS "unitId",
    u."unitNumber",
    u."rent",
    u."bedrooms",
    u."status" AS "unitStatus",
    u."createdAt",
    u."updatedAt",
    p."id" AS "propertyId",
    p."name" AS "propertyName",
    p."address" AS "propertyAddress",
    p."city" AS "propertyCity",
    p."state" AS "propertyState",
    p."pincode" AS "propertyPincode",
    p."type" AS "propertyType",
    p."ownerId",
    p."managerId",
    l."id" AS "leaseId",
    l."startDate",
    l."endDate",
    l."monthlyRent",
    l."dueDay",
    l."status" AS "leaseStatus",
    tp."id" AS "tenantId",
    tu."id" AS "tenantUserId",
    tu."name" AS "tenantName",
    tu."email" AS "tenantEmail",
    tp."phone" AS "tenantPhone"
FROM "Unit" u
INNER JOIN "Property" p ON p."id" = u."propertyId"
LEFT JOIN "Lease" l ON l."unitId" = u."id"
LEFT JOIN "TenantProfile" tp ON tp."id" = l."tenantId"
LEFT JOIN "User" tu ON tu."id" = tp."userId"
WHERE u."id" = $1
ORDER BY l."createdAt" DESC;

-- 3.4 Check duplicate unit number on a given property
-- READ
SELECT "id"
FROM "Unit"
WHERE "propertyId" = $1 AND "unitNumber" = $2;

-- 3.5 Create a new unit
-- WRITE
INSERT INTO "Unit" (
    "id",
    "propertyId",
    "unitNumber",
    "rent",
    "bedrooms",
    "status",
    "createdAt",
    "updatedAt"
) VALUES (
    $1, $2, $3, $4, $5, COALESCE($6, 'VACANT'), CURRENT_TIMESTAMP, CURRENT_TIMESTAMP
)
RETURNING *;

-- 3.6 Update unit details (rent, bedrooms, status, unitNumber)
-- WRITE
UPDATE "Unit"
SET 
    "unitNumber" = COALESCE($2, "unitNumber"),
    "rent" = COALESCE($3, "rent"),
    "bedrooms" = COALESCE($4, "bedrooms"),
    "status" = COALESCE($5, "status"),
    "updatedAt" = CURRENT_TIMESTAMP
WHERE "id" = $1
RETURNING *;

-- 3.7 Check unit lease and maintenance history before deletion
-- READ
SELECT 
    u."id",
    COUNT(DISTINCT l."id")::INT AS "leaseCount",
    COUNT(DISTINCT m."id")::INT AS "maintenanceCount"
FROM "Unit" u
LEFT JOIN "Lease" l ON l."unitId" = u."id"
LEFT JOIN "MaintenanceRequest" m ON m."unitId" = u."id"
WHERE u."id" = $1
GROUP BY u."id";

-- 3.8 Delete a unit
-- WRITE
DELETE FROM "Unit"
WHERE "id" = $1;


-- ============================================================================
-- SECTION 4: TENANT MANAGEMENT
-- ============================================================================

-- 4.1 List tenants with user details, active lease, unit, and property
-- READ
SELECT 
    tp."id" AS "tenantProfileId",
    tp."userId",
    tp."createdByLandlordId",
    tp."phone",
    tp."emergencyContactName",
    tp."emergencyContactPhone",
    tp."idProofType",
    tp."idProofNumber",
    tp."createdAt",
    tp."updatedAt",
    u."name" AS "tenantName",
    u."email" AS "tenantEmail",
    u."isActive",
    al."id" AS "activeLeaseId",
    al."status" AS "leaseStatus",
    al."startDate" AS "leaseStartDate",
    al."endDate" AS "leaseEndDate",
    al."monthlyRent" AS "leaseMonthlyRent",
    un."id" AS "unitId",
    un."unitNumber",
    p."id" AS "propertyId",
    p."name" AS "propertyName",
    p."city" AS "propertyCity",
    COUNT(all_l."id")::INT AS "leasesCount"
FROM "TenantProfile" tp
INNER JOIN "User" u ON u."id" = tp."userId"
LEFT JOIN "Lease" al ON al."tenantId" = tp."id" AND al."status" = 'ACTIVE'
LEFT JOIN "Unit" un ON un."id" = al."unitId"
LEFT JOIN "Property" p ON p."id" = un."propertyId"
LEFT JOIN "Lease" all_l ON all_l."tenantId" = tp."id"
WHERE 
    (
        ($1 = 'LANDLORD' AND (
            tp."createdByLandlordId" = $2 
            OR EXISTS (
                SELECT 1 FROM "Lease" l2
                INNER JOIN "Unit" u2 ON u2."id" = l2."unitId"
                INNER JOIN "Property" p2 ON p2."id" = u2."propertyId"
                WHERE l2."tenantId" = tp."id" AND p2."ownerId" = $2
            )
        ))
        OR 
        ($1 = 'MANAGER' AND EXISTS (
            SELECT 1 FROM "Lease" l3
            INNER JOIN "Unit" u3 ON u3."id" = l3."unitId"
            INNER JOIN "Property" p3 ON p3."id" = u3."propertyId"
            WHERE l3."tenantId" = tp."id" AND p3."managerId" = $2
        ))
    )
    AND (
        $3::TEXT IS NULL 
        OR tp."phone" ILIKE '%' || $3 || '%' 
        OR u."name" ILIKE '%' || $3 || '%' 
        OR u."email" ILIKE '%' || $3 || '%'
    )
GROUP BY 
    tp."id", 
    u."id", 
    al."id", 
    un."id", 
    p."id"
ORDER BY tp."createdAt" DESC
LIMIT $4 OFFSET $5;

-- 4.2 Count tenants matching filter for pagination
-- READ
SELECT COUNT(DISTINCT tp."id")::INT AS "total"
FROM "TenantProfile" tp
INNER JOIN "User" u ON u."id" = tp."userId"
WHERE 
    (
        ($1 = 'LANDLORD' AND (
            tp."createdByLandlordId" = $2 
            OR EXISTS (
                SELECT 1 FROM "Lease" l2
                INNER JOIN "Unit" u2 ON u2."id" = l2."unitId"
                INNER JOIN "Property" p2 ON p2."id" = u2."propertyId"
                WHERE l2."tenantId" = tp."id" AND p2."ownerId" = $2
            )
        ))
        OR 
        ($1 = 'MANAGER' AND EXISTS (
            SELECT 1 FROM "Lease" l3
            INNER JOIN "Unit" u3 ON u3."id" = l3."unitId"
            INNER JOIN "Property" p3 ON p3."id" = u3."propertyId"
            WHERE l3."tenantId" = tp."id" AND p3."managerId" = $2
        ))
    )
    AND (
        $3::TEXT IS NULL 
        OR tp."phone" ILIKE '%' || $3 || '%' 
        OR u."name" ILIKE '%' || $3 || '%' 
        OR u."email" ILIKE '%' || $3 || '%'
    );

-- 4.3 Get tenant profile by ID with user, leases, units, and property info
-- READ
SELECT 
    tp."id" AS "tenantProfileId",
    tp."userId",
    tp."createdByLandlordId",
    tp."phone",
    tp."emergencyContactName",
    tp."emergencyContactPhone",
    tp."idProofType",
    tp."idProofNumber",
    tp."createdAt",
    tp."updatedAt",
    u."name" AS "tenantName",
    u."email" AS "tenantEmail",
    u."isActive",
    l."id" AS "leaseId",
    l."status" AS "leaseStatus",
    l."startDate",
    l."endDate",
    l."monthlyRent",
    l."dueDay",
    un."id" AS "unitId",
    un."unitNumber",
    p."id" AS "propertyId",
    p."name" AS "propertyName",
    p."address" AS "propertyAddress",
    p."city" AS "propertyCity",
    p."ownerId" AS "propertyOwnerId",
    p."managerId" AS "propertyManagerId"
FROM "TenantProfile" tp
INNER JOIN "User" u ON u."id" = tp."userId"
LEFT JOIN "Lease" l ON l."tenantId" = tp."id"
LEFT JOIN "Unit" un ON un."id" = l."unitId"
LEFT JOIN "Property" p ON p."id" = un."propertyId"
WHERE tp."id" = $1
ORDER BY l."createdAt" DESC;

-- 4.4 Get current tenant profile (`getMyTenantProfile`) by user ID
-- READ
SELECT 
    tp."id" AS "tenantProfileId",
    tp."userId",
    tp."phone",
    tp."emergencyContactName",
    tp."emergencyContactPhone",
    tp."idProofType",
    tp."idProofNumber",
    u."name" AS "tenantName",
    u."email" AS "tenantEmail",
    l."id" AS "leaseId",
    l."status" AS "leaseStatus",
    l."startDate",
    l."endDate",
    l."monthlyRent",
    l."dueDay",
    un."id" AS "unitId",
    un."unitNumber",
    p."id" AS "propertyId",
    p."name" AS "propertyName",
    p."address" AS "propertyAddress",
    p."city" AS "propertyCity"
FROM "TenantProfile" tp
INNER JOIN "User" u ON u."id" = tp."userId"
LEFT JOIN "Lease" l ON l."tenantId" = tp."id"
LEFT JOIN "Unit" un ON un."id" = l."unitId"
LEFT JOIN "Property" p ON p."id" = un."propertyId"
WHERE tp."userId" = $1
ORDER BY l."createdAt" DESC;

-- 4.5 Check if user already exists by email along with existing tenant profile
-- READ
SELECT 
    u."id" AS "userId",
    u."role",
    tp."id" AS "tenantProfileId"
FROM "User" u
LEFT JOIN "TenantProfile" tp ON tp."userId" = u."id"
WHERE LOWER(TRIM(u."email")) = LOWER(TRIM($1));

-- 4.6 Create user record for new tenant
-- WRITE
INSERT INTO "User" (
    "id",
    "name",
    "email",
    "passwordHash",
    "role",
    "isActive",
    "createdAt",
    "updatedAt"
) VALUES (
    $1, TRIM($2), LOWER(TRIM($3)), $4, 'TENANT', TRUE, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP
)
RETURNING *;

-- 4.7 Create tenant profile
-- WRITE
INSERT INTO "TenantProfile" (
    "id",
    "userId",
    "createdByLandlordId",
    "phone",
    "emergencyContactName",
    "emergencyContactPhone",
    "idProofType",
    "idProofNumber",
    "createdAt",
    "updatedAt"
) VALUES (
    $1, $2, $3, $4, $5, $6, $7, $8, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP
)
RETURNING *;

-- 4.8 Update user name for tenant
-- WRITE
UPDATE "User"
SET 
    "name" = TRIM($2),
    "updatedAt" = CURRENT_TIMESTAMP
WHERE "id" = $1;

-- 4.9 Update tenant profile fields
-- WRITE
UPDATE "TenantProfile"
SET 
    "phone" = COALESCE($2, "phone"),
    "emergencyContactName" = COALESCE($3, "emergencyContactName"),
    "emergencyContactPhone" = COALESCE($4, "emergencyContactPhone"),
    "idProofType" = COALESCE($5, "idProofType"),
    "idProofNumber" = COALESCE($6, "idProofNumber"),
    "updatedAt" = CURRENT_TIMESTAMP
WHERE "id" = $1
RETURNING *;

-- 4.10 Check tenant active leases and maintenance history before deletion
-- READ
SELECT 
    tp."id",
    COUNT(CASE WHEN l."status" = 'ACTIVE' THEN 1 END)::INT AS "activeLeasesCount",
    COUNT(l."id")::INT AS "totalLeasesCount",
    COUNT(m."id")::INT AS "maintenanceCount"
FROM "TenantProfile" tp
LEFT JOIN "Lease" l ON l."tenantId" = tp."id"
LEFT JOIN "MaintenanceRequest" m ON m."tenantId" = tp."id"
WHERE tp."id" = $1
GROUP BY tp."id";

-- 4.11 Delete tenant profile
-- WRITE
DELETE FROM "TenantProfile"
WHERE "id" = $1;

-- 4.12 Delete tenant user record
-- WRITE
DELETE FROM "User"
WHERE "id" = $1;


-- ============================================================================
-- SECTION 5: LEASE MANAGEMENT
-- ============================================================================

-- 5.1 List leases with unit, property, tenant profile, and user details
-- READ
SELECT 
    l."id" AS "leaseId",
    l."unitId",
    l."tenantId",
    l."startDate",
    l."endDate",
    l."monthlyRent",
    l."securityDeposit",
    l."dueDay",
    l."status" AS "leaseStatus",
    l."createdAt",
    l."updatedAt",
    u."unitNumber",
    u."rent" AS "unitRent",
    u."bedrooms",
    p."id" AS "propertyId",
    p."name" AS "propertyName",
    p."address" AS "propertyAddress",
    p."city" AS "propertyCity",
    tp."phone" AS "tenantPhone",
    tu."id" AS "tenantUserId",
    tu."name" AS "tenantName",
    tu."email" AS "tenantEmail"
FROM "Lease" l
INNER JOIN "Unit" u ON u."id" = l."unitId"
INNER JOIN "Property" p ON p."id" = u."propertyId"
INNER JOIN "TenantProfile" tp ON tp."id" = l."tenantId"
INNER JOIN "User" tu ON tu."id" = tp."userId"
WHERE 
    (
        ($1 = 'LANDLORD' AND p."ownerId" = $2)
        OR ($1 = 'MANAGER' AND p."managerId" = $2)
        OR ($1 = 'TENANT' AND tu."id" = $2)
    )
    AND ($3::TEXT IS NULL OR p."id" = $3)
    AND ($4::TEXT IS NULL OR u."id" = $4)
    AND ($5::TEXT IS NULL OR tp."id" = $5)
    AND ($6::"LeaseStatus" IS NULL OR l."status" = $6)
ORDER BY l."createdAt" DESC
LIMIT $7 OFFSET $8;

-- 5.2 Count leases matching filter for pagination
-- READ
SELECT COUNT(l."id")::INT AS "total"
FROM "Lease" l
INNER JOIN "Unit" u ON u."id" = l."unitId"
INNER JOIN "Property" p ON p."id" = u."propertyId"
INNER JOIN "TenantProfile" tp ON tp."id" = l."tenantId"
INNER JOIN "User" tu ON tu."id" = tp."userId"
WHERE 
    (
        ($1 = 'LANDLORD' AND p."ownerId" = $2)
        OR ($1 = 'MANAGER' AND p."managerId" = $2)
        OR ($1 = 'TENANT' AND tu."id" = $2)
    )
    AND ($3::TEXT IS NULL OR p."id" = $3)
    AND ($4::TEXT IS NULL OR u."id" = $4)
    AND ($5::TEXT IS NULL OR tp."id" = $5)
    AND ($6::"LeaseStatus" IS NULL OR l."status" = $6);

-- 5.3 Get lease by ID with unit, property, tenant user, and payment records
-- READ
SELECT 
    l."id" AS "leaseId",
    l."startDate",
    l."endDate",
    l."monthlyRent",
    l."securityDeposit",
    l."dueDay",
    l."status" AS "leaseStatus",
    l."createdAt",
    l."updatedAt",
    u."id" AS "unitId",
    u."unitNumber",
    p."id" AS "propertyId",
    p."name" AS "propertyName",
    p."address" AS "propertyAddress",
    p."city" AS "propertyCity",
    p."state" AS "propertyState",
    p."pincode" AS "propertyPincode",
    p."type" AS "propertyType",
    p."ownerId",
    p."managerId",
    tp."id" AS "tenantProfileId",
    tp."phone" AS "tenantPhone",
    tu."id" AS "tenantUserId",
    tu."name" AS "tenantName",
    tu."email" AS "tenantEmail",
    pm."id" AS "paymentId",
    pm."billingMonth",
    pm."amount" AS "paymentAmount",
    pm."method" AS "paymentMethod",
    pm."paidOn",
    pm."notes"
FROM "Lease" l
INNER JOIN "Unit" u ON u."id" = l."unitId"
INNER JOIN "Property" p ON p."id" = u."propertyId"
INNER JOIN "TenantProfile" tp ON tp."id" = l."tenantId"
INNER JOIN "User" tu ON tu."id" = tp."userId"
LEFT JOIN "Payment" pm ON pm."leaseId" = l."id"
WHERE l."id" = $1
ORDER BY pm."paidOn" DESC;

-- 5.4 Check if an active lease already exists on a unit
-- READ
SELECT "id", "startDate", "endDate"
FROM "Lease"
WHERE "unitId" = $1 AND "status" = 'ACTIVE'
LIMIT 1;

-- 5.5 Create a new lease
-- WRITE
INSERT INTO "Lease" (
    "id",
    "unitId",
    "tenantId",
    "startDate",
    "endDate",
    "monthlyRent",
    "securityDeposit",
    "dueDay",
    "status",
    "createdAt",
    "updatedAt"
) VALUES (
    $1, $2, $3, $4, $5, $6, $7, $8, COALESCE($9, 'ACTIVE'), CURRENT_TIMESTAMP, CURRENT_TIMESTAMP
)
RETURNING *;

-- 5.6 Update unit status when lease becomes active
-- WRITE
UPDATE "Unit"
SET 
    "status" = 'OCCUPIED',
    "updatedAt" = CURRENT_TIMESTAMP
WHERE "id" = $1;

-- 5.7 Update lease details or status
-- WRITE
UPDATE "Lease"
SET 
    "startDate" = COALESCE($2, "startDate"),
    "endDate" = COALESCE($3, "endDate"),
    "monthlyRent" = COALESCE($4, "monthlyRent"),
    "securityDeposit" = COALESCE($5, "securityDeposit"),
    "dueDay" = COALESCE($6, "dueDay"),
    "status" = COALESCE($7, "status"),
    "updatedAt" = CURRENT_TIMESTAMP
WHERE "id" = $1
RETURNING *;

-- 5.8 Check if other active leases remain for the unit when a lease is ended/terminated
-- READ
SELECT "id"
FROM "Lease"
WHERE "unitId" = $1 AND "status" = 'ACTIVE' AND "id" != $2
LIMIT 1;

-- 5.9 Reset unit status to VACANT when no active lease remains
-- WRITE
UPDATE "Unit"
SET 
    "status" = 'VACANT',
    "updatedAt" = CURRENT_TIMESTAMP
WHERE "id" = $1;

-- 5.10 Check payment history on a lease before deletion
-- READ
SELECT 
    l."id",
    COUNT(pm."id")::INT AS "paymentCount"
FROM "Lease" l
LEFT JOIN "Payment" pm ON pm."leaseId" = l."id"
WHERE l."id" = $1
GROUP BY l."id";

-- 5.11 Delete a lease
-- WRITE
DELETE FROM "Lease"
WHERE "id" = $1;


-- ============================================================================
-- SECTION 6: RENT PAYMENTS
-- ============================================================================

-- 6.1 List rent payments with lease, unit, property, and tenant user details
-- READ
SELECT 
    pm."id" AS "paymentId",
    pm."billingMonth",
    pm."amount",
    pm."method",
    pm."paidOn",
    pm."notes",
    pm."createdAt",
    l."id" AS "leaseId",
    l."dueDay",
    l."monthlyRent",
    u."id" AS "unitId",
    u."unitNumber",
    p."id" AS "propertyId",
    p."name" AS "propertyName",
    tu."id" AS "tenantUserId",
    tu."name" AS "tenantName",
    tu."email" AS "tenantEmail"
FROM "Payment" pm
INNER JOIN "Lease" l ON l."id" = pm."leaseId"
INNER JOIN "Unit" u ON u."id" = l."unitId"
INNER JOIN "Property" p ON p."id" = u."propertyId"
INNER JOIN "TenantProfile" tp ON tp."id" = l."tenantId"
INNER JOIN "User" tu ON tu."id" = tp."userId"
WHERE 
    (
        ($1 = 'LANDLORD' AND p."ownerId" = $2)
        OR ($1 = 'MANAGER' AND p."managerId" = $2)
        OR ($1 = 'TENANT' AND tu."id" = $2)
    )
    AND ($3::TEXT IS NULL OR pm."leaseId" = $3)
    AND ($4::DATE IS NULL OR pm."billingMonth" = $4)
ORDER BY pm."paidOn" DESC, pm."createdAt" DESC
LIMIT $5 OFFSET $6;

-- 6.2 Get payment by ID with full lease, property, and tenant context
-- READ
SELECT 
    pm."id" AS "paymentId",
    pm."billingMonth",
    pm."amount",
    pm."method",
    pm."paidOn",
    pm."notes",
    pm."createdAt",
    l."id" AS "leaseId",
    l."dueDay",
    l."monthlyRent",
    u."unitNumber",
    p."id" AS "propertyId",
    p."name" AS "propertyName",
    p."ownerId",
    p."managerId",
    tu."id" AS "tenantUserId",
    tu."name" AS "tenantName",
    tu."email" AS "tenantEmail"
FROM "Payment" pm
INNER JOIN "Lease" l ON l."id" = pm."leaseId"
INNER JOIN "Unit" u ON u."id" = l."unitId"
INNER JOIN "Property" p ON p."id" = u."propertyId"
INNER JOIN "TenantProfile" tp ON tp."id" = l."tenantId"
INNER JOIN "User" tu ON tu."id" = tp."userId"
WHERE pm."id" = $1;

-- 6.3 Check if payment already exists for a lease and billing month (unique check)
-- READ
SELECT "id", "amount", "paidOn"
FROM "Payment"
WHERE "leaseId" = $1 AND "billingMonth" = $2;

-- 6.4 Record a new rent payment
-- WRITE
INSERT INTO "Payment" (
    "id",
    "leaseId",
    "billingMonth",
    "amount",
    "method",
    "paidOn",
    "notes",
    "createdAt",
    "updatedAt"
) VALUES (
    $1, $2, $3, $4, $5, $6, $7, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP
)
RETURNING *;

-- 6.5 Update payment notes or payment method
-- WRITE
UPDATE "Payment"
SET 
    "notes" = COALESCE($2, "notes"),
    "method" = COALESCE($3, "method"),
    "amount" = COALESCE($4, "amount"),
    "paidOn" = COALESCE($5, "paidOn"),
    "updatedAt" = CURRENT_TIMESTAMP
WHERE "id" = $1
RETURNING *;

-- 6.6 Delete / void a payment record
-- WRITE
DELETE FROM "Payment"
WHERE "id" = $1;


-- ============================================================================
-- SECTION 7: MAINTENANCE REQUESTS
-- ============================================================================

-- 7.1 List maintenance requests with unit, property, and reporting tenant details
-- READ
SELECT 
    m."id" AS "requestId",
    m."title",
    m."description",
    m."priority",
    m."status",
    m."resolvedAt",
    m."createdAt",
    m."updatedAt",
    u."id" AS "unitId",
    u."unitNumber",
    p."id" AS "propertyId",
    p."name" AS "propertyName",
    p."address" AS "propertyAddress",
    tp."id" AS "tenantProfileId",
    tu."id" AS "tenantUserId",
    tu."name" AS "tenantName",
    tu."email" AS "tenantEmail",
    l."id" AS "leaseId"
FROM "MaintenanceRequest" m
INNER JOIN "Unit" u ON u."id" = m."unitId"
INNER JOIN "Property" p ON p."id" = u."propertyId"
INNER JOIN "TenantProfile" tp ON tp."id" = m."tenantId"
INNER JOIN "User" tu ON tu."id" = tp."userId"
LEFT JOIN "Lease" l ON l."id" = m."leaseId"
WHERE 
    (
        ($1 = 'LANDLORD' AND p."ownerId" = $2)
        OR ($1 = 'MANAGER' AND p."managerId" = $2)
        OR ($1 = 'TENANT' AND tu."id" = $2)
    )
    AND ($3::"MaintenanceStatus" IS NULL OR m."status" = $3)
    AND ($4::TEXT IS NULL OR p."id" = $4)
    AND ($5::TEXT IS NULL OR u."id" = $5)
ORDER BY 
    CASE m."priority"
        WHEN 'URGENT' THEN 1
        WHEN 'HIGH' THEN 2
        WHEN 'MEDIUM' THEN 3
        WHEN 'LOW' THEN 4
    END ASC,
    m."createdAt" DESC
LIMIT $6 OFFSET $7;

-- 7.2 Get maintenance request by ID with complete details
-- READ
SELECT 
    m."id" AS "requestId",
    m."title",
    m."description",
    m."priority",
    m."status",
    m."resolvedAt",
    m."createdAt",
    m."updatedAt",
    u."id" AS "unitId",
    u."unitNumber",
    p."id" AS "propertyId",
    p."name" AS "propertyName",
    p."ownerId",
    p."managerId",
    tp."id" AS "tenantProfileId",
    tp."phone" AS "tenantPhone",
    tu."id" AS "tenantUserId",
    tu."name" AS "tenantName",
    tu."email" AS "tenantEmail",
    l."id" AS "leaseId"
FROM "MaintenanceRequest" m
INNER JOIN "Unit" u ON u."id" = m."unitId"
INNER JOIN "Property" p ON p."id" = u."propertyId"
INNER JOIN "TenantProfile" tp ON tp."id" = m."tenantId"
INNER JOIN "User" tu ON tu."id" = tp."userId"
LEFT JOIN "Lease" l ON l."id" = m."leaseId"
WHERE m."id" = $1;

-- 7.3 Auto-lookup tenant active lease for unit when creating maintenance request
-- READ
SELECT l."id" AS "leaseId"
FROM "Lease" l
WHERE l."tenantId" = $1 AND l."unitId" = $2 AND l."status" = 'ACTIVE'
LIMIT 1;

-- 7.4 Create a new maintenance request
-- WRITE
INSERT INTO "MaintenanceRequest" (
    "id",
    "unitId",
    "leaseId",
    "tenantId",
    "title",
    "description",
    "priority",
    "status",
    "createdAt",
    "updatedAt"
) VALUES (
    $1, $2, $3, $4, $5, $6, COALESCE($7, 'MEDIUM'), 'OPEN', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP
)
RETURNING *;

-- 7.5 Update maintenance request status and set resolution timestamp
-- WRITE
UPDATE "MaintenanceRequest"
SET 
    "status" = $2,
    "resolvedAt" = CASE WHEN $2 IN ('RESOLVED', 'CLOSED') THEN CURRENT_TIMESTAMP ELSE NULL END,
    "updatedAt" = CURRENT_TIMESTAMP
WHERE "id" = $1
RETURNING *;

-- 7.6 Delete maintenance request
-- WRITE
DELETE FROM "MaintenanceRequest"
WHERE "id" = $1;


-- ============================================================================
-- SECTION 8: LANDLORD / MANAGER DASHBOARD ANALYTICS
-- ============================================================================

-- 8.1 Portfolio summary: property count, total units, occupied units, vacant units
-- READ
SELECT 
    COUNT(DISTINCT p."id")::INT AS "totalProperties",
    COUNT(u."id")::INT AS "totalUnits",
    COUNT(CASE WHEN u."status" = 'OCCUPIED' THEN 1 END)::INT AS "occupiedUnits",
    COUNT(CASE WHEN u."status" = 'VACANT' THEN 1 END)::INT AS "vacantUnits",
    CASE 
        WHEN COUNT(u."id") = 0 THEN 0.00
        ELSE ROUND((COUNT(CASE WHEN u."status" = 'OCCUPIED' THEN 1 END)::NUMERIC / COUNT(u."id")::NUMERIC) * 100, 2)
    END AS "occupancyRate"
FROM "Property" p
LEFT JOIN "Unit" u ON u."propertyId" = p."id"
WHERE ($1 = 'LANDLORD' AND p."ownerId" = $2) OR ($1 = 'MANAGER' AND p."managerId" = $2);

-- 8.2 Expected rent this month: sum of monthlyRent for active leases covering the current month
-- READ
SELECT 
    COALESCE(SUM(l."monthlyRent"), 0.00) AS "expectedRentThisMonth"
FROM "Lease" l
INNER JOIN "Unit" u ON u."id" = l."unitId"
INNER JOIN "Property" p ON p."id" = u."propertyId"
WHERE 
    (($1 = 'LANDLORD' AND p."ownerId" = $2) OR ($1 = 'MANAGER' AND p."managerId" = $2))
    AND l."status" = 'ACTIVE'
    AND l."startDate" <= $3  -- monthEnd
    AND l."endDate" >= $4;   -- monthStart

-- 8.3 Collected rent this month: sum of payments made in the current month
-- READ
SELECT 
    COALESCE(SUM(pm."amount"), 0.00) AS "rentCollectedThisMonth"
FROM "Payment" pm
INNER JOIN "Lease" l ON l."id" = pm."leaseId"
INNER JOIN "Unit" u ON u."id" = l."unitId"
INNER JOIN "Property" p ON p."id" = u."propertyId"
WHERE 
    (($1 = 'LANDLORD' AND p."ownerId" = $2) OR ($1 = 'MANAGER' AND p."managerId" = $2))
    AND pm."paidOn" >= $3    -- monthStart
    AND pm."paidOn" <= $4;   -- monthEnd

-- 8.4 Overdue rent identification: active leases that have passed due date without payment for billing month
-- READ
SELECT 
    l."id" AS "leaseId",
    l."dueDay",
    l."monthlyRent" AS "amount",
    l."startDate",
    l."endDate",
    u."unitNumber",
    p."name" AS "propertyName",
    tu."name" AS "tenantName",
    tu."email" AS "tenantEmail"
FROM "Lease" l
INNER JOIN "Unit" u ON u."id" = l."unitId"
INNER JOIN "Property" p ON p."id" = u."propertyId"
INNER JOIN "TenantProfile" tp ON tp."id" = l."tenantId"
INNER JOIN "User" tu ON tu."id" = tp."userId"
WHERE 
    (($1 = 'LANDLORD' AND p."ownerId" = $2) OR ($1 = 'MANAGER' AND p."managerId" = $2))
    AND l."status" = 'ACTIVE'
    AND l."startDate" <= CURRENT_DATE
    AND NOT EXISTS (
        SELECT 1 
        FROM "Payment" pm
        WHERE pm."leaseId" = l."id" 
          AND pm."billingMonth" = $3  -- current billing month (1st of month)
    );

-- 8.5 Count open and in-progress maintenance requests across landlord portfolio
-- READ
SELECT COUNT(m."id")::INT AS "openMaintenanceRequests"
FROM "MaintenanceRequest" m
INNER JOIN "Unit" u ON u."id" = m."unitId"
INNER JOIN "Property" p ON p."id" = u."propertyId"
WHERE 
    (($1 = 'LANDLORD' AND p."ownerId" = $2) OR ($1 = 'MANAGER' AND p."managerId" = $2))
    AND m."status" IN ('OPEN', 'IN_PROGRESS');

-- 8.6 Rent collected grouped by billing month (last 6 months trend)
-- READ
SELECT 
    pm."billingMonth",
    COALESCE(SUM(pm."amount"), 0.00) AS "totalCollected"
FROM "Payment" pm
INNER JOIN "Lease" l ON l."id" = pm."leaseId"
INNER JOIN "Unit" u ON u."id" = l."unitId"
INNER JOIN "Property" p ON p."id" = u."propertyId"
WHERE 
    (($1 = 'LANDLORD' AND p."ownerId" = $2) OR ($1 = 'MANAGER' AND p."managerId" = $2))
    AND pm."billingMonth" >= $3  -- 6 months ago
    AND pm."billingMonth" <= $4  -- current month
GROUP BY pm."billingMonth"
ORDER BY pm."billingMonth" ASC;

-- 8.7 Recent 5 payments across portfolio with tenant, unit, and property info
-- READ
SELECT 
    pm."id" AS "paymentId",
    pm."amount",
    pm."billingMonth",
    pm."paidOn",
    pm."method",
    tu."id" AS "tenantUserId",
    tu."name" AS "tenantName",
    tu."email" AS "tenantEmail",
    p."id" AS "propertyId",
    p."name" AS "propertyName",
    u."unitNumber",
    l."dueDay"
FROM "Payment" pm
INNER JOIN "Lease" l ON l."id" = pm."leaseId"
INNER JOIN "Unit" u ON u."id" = l."unitId"
INNER JOIN "Property" p ON p."id" = u."propertyId"
INNER JOIN "TenantProfile" tp ON tp."id" = l."tenantId"
INNER JOIN "User" tu ON tu."id" = tp."userId"
WHERE 
    (($1 = 'LANDLORD' AND p."ownerId" = $2) OR ($1 = 'MANAGER' AND p."managerId" = $2))
ORDER BY pm."paidOn" DESC, pm."createdAt" DESC
LIMIT 5;


-- ============================================================================
-- SECTION 9: TENANT DASHBOARD ANALYTICS
-- ============================================================================

-- 9.1 Tenant active lease, unit, and property summary
-- READ
SELECT 
    l."id" AS "leaseId",
    l."startDate",
    l."endDate",
    l."monthlyRent",
    l."dueDay",
    u."id" AS "unitId",
    u."unitNumber",
    p."id" AS "propertyId",
    p."name" AS "propertyName",
    p."address" AS "propertyAddress",
    p."city" AS "propertyCity",
    p."state" AS "propertyState"
FROM "TenantProfile" tp
INNER JOIN "Lease" l ON l."tenantId" = tp."id"
INNER JOIN "Unit" u ON u."id" = l."unitId"
INNER JOIN "Property" p ON p."id" = u."propertyId"
WHERE 
    tp."userId" = $1
    AND l."status" = 'ACTIVE'
    AND l."startDate" <= CURRENT_DATE
    AND l."endDate" >= CURRENT_DATE
ORDER BY l."startDate" DESC
LIMIT 1;

-- 9.2 Count open/in-progress maintenance requests for signed-in tenant
-- READ
SELECT COUNT(m."id")::INT AS "openMaintenanceRequestCount"
FROM "MaintenanceRequest" m
INNER JOIN "TenantProfile" tp ON tp."id" = m."tenantId"
WHERE 
    tp."userId" = $1
    AND m."status" IN ('OPEN', 'IN_PROGRESS');

-- 9.3 Current month payment lookup for active lease
-- READ
SELECT 
    pm."id" AS "paymentId",
    pm."amount",
    pm."billingMonth",
    pm."paidOn",
    pm."method"
FROM "Payment" pm
WHERE pm."leaseId" = $1 AND pm."billingMonth" = $2;

-- 9.4 Most recent payment on tenant lease
-- READ
SELECT 
    pm."id" AS "paymentId",
    pm."amount",
    pm."billingMonth",
    pm."paidOn",
    pm."method"
FROM "Payment" pm
WHERE pm."leaseId" = $1
ORDER BY pm."paidOn" DESC, pm."createdAt" DESC
LIMIT 1;


-- ============================================================================
-- SECTION 10: SEED & ENVIRONMENT RESET OPERATIONS
-- ============================================================================

-- 10.1 Reset/clean development database in referential order
-- WRITE
DELETE FROM "MaintenanceRequest";
DELETE FROM "Payment";
DELETE FROM "Lease";
DELETE FROM "TenantProfile";
DELETE FROM "Unit";
DELETE FROM "Property";
DELETE FROM "User";
