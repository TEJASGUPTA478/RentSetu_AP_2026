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
