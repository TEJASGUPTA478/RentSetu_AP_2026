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
