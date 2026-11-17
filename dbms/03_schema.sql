CREATE TYPE "Role" AS ENUM ('LANDLORD', 'MANAGER', 'TENANT');
CREATE TYPE "UnitStatus" AS ENUM ('VACANT', 'OCCUPIED');
CREATE TYPE "LeaseStatus" AS ENUM ('ACTIVE', 'ENDED', 'TERMINATED');
CREATE TYPE "PaymentMethod" AS ENUM ('CASH', 'UPI', 'BANK_TRANSFER', 'CHEQUE', 'CARD');
CREATE TYPE "MaintenanceStatus" AS ENUM ('OPEN', 'IN_PROGRESS', 'RESOLVED', 'CLOSED');
CREATE TYPE "Priority" AS ENUM ('LOW', 'MEDIUM', 'HIGH', 'URGENT');

CREATE TABLE "User" (
    "id" TEXT NOT NULL,
    "name" TEXT NOT NULL,
    "email" TEXT NOT NULL,
    "passwordHash" TEXT NOT NULL,
    "role" "Role" NOT NULL DEFAULT 'TENANT',
    "isActive" BOOLEAN NOT NULL DEFAULT TRUE,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,
    CONSTRAINT "User_pkey" PRIMARY KEY ("id"),
    CONSTRAINT "User_email_key" UNIQUE ("email")
);

CREATE TABLE "Property" (
    "id" TEXT NOT NULL,
    "ownerId" TEXT NOT NULL,
    "managerId" TEXT,
    "name" TEXT NOT NULL,
    "address" TEXT NOT NULL,
    "city" TEXT NOT NULL,
    "state" TEXT NOT NULL,
    "pincode" TEXT NOT NULL,
    "type" TEXT NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,
    CONSTRAINT "Property_pkey" PRIMARY KEY ("id"),
    CONSTRAINT "Property_ownerId_fkey"
        FOREIGN KEY ("ownerId") REFERENCES "User"("id")
        ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT "Property_managerId_fkey"
        FOREIGN KEY ("managerId") REFERENCES "User"("id")
        ON DELETE RESTRICT ON UPDATE CASCADE
);

CREATE TABLE "Unit" (
    "id" TEXT NOT NULL,
    "propertyId" TEXT NOT NULL,
    "unitNumber" TEXT NOT NULL,
    "rent" DECIMAL(12, 2) NOT NULL,
    "bedrooms" INTEGER NOT NULL,
    "status" "UnitStatus" NOT NULL DEFAULT 'VACANT',
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,
    CONSTRAINT "Unit_pkey" PRIMARY KEY ("id"),
    CONSTRAINT "Unit_propertyId_fkey"
        FOREIGN KEY ("propertyId") REFERENCES "Property"("id")
        ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT "Unit_propertyId_unitNumber_key" UNIQUE ("propertyId", "unitNumber")
);

CREATE TABLE "TenantProfile" (
    "id" TEXT NOT NULL,
    "userId" TEXT NOT NULL,
    "createdByLandlordId" TEXT NOT NULL,
    "phone" TEXT NOT NULL,
    "emergencyContactName" TEXT,
    "emergencyContactPhone" TEXT,
    "idProofType" TEXT,
    "idProofNumber" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,
    CONSTRAINT "TenantProfile_pkey" PRIMARY KEY ("id"),
    CONSTRAINT "TenantProfile_userId_key" UNIQUE ("userId"),
    CONSTRAINT "TenantProfile_userId_fkey"
        FOREIGN KEY ("userId") REFERENCES "User"("id")
        ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT "TenantProfile_createdByLandlordId_fkey"
        FOREIGN KEY ("createdByLandlordId") REFERENCES "User"("id")
        ON DELETE RESTRICT ON UPDATE CASCADE
);

CREATE TABLE "Lease" (
    "id" TEXT NOT NULL,
    "unitId" TEXT NOT NULL,
    "tenantId" TEXT NOT NULL,
    "startDate" DATE NOT NULL,
    "endDate" DATE NOT NULL,
    "monthlyRent" DECIMAL(12, 2) NOT NULL,
    "securityDeposit" DECIMAL(12, 2) NOT NULL,
    "dueDay" INTEGER NOT NULL,
    "status" "LeaseStatus" NOT NULL DEFAULT 'ACTIVE',
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,
    CONSTRAINT "Lease_pkey" PRIMARY KEY ("id"),
    CONSTRAINT "Lease_dueDay_range_check" CHECK ("dueDay" BETWEEN 1 AND 28),
    CONSTRAINT "Lease_unitId_fkey"
        FOREIGN KEY ("unitId") REFERENCES "Unit"("id")
        ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT "Lease_tenantId_fkey"
        FOREIGN KEY ("tenantId") REFERENCES "TenantProfile"("id")
        ON DELETE RESTRICT ON UPDATE CASCADE
);

CREATE TABLE "Payment" (
    "id" TEXT NOT NULL,
    "leaseId" TEXT NOT NULL,
    "billingMonth" DATE NOT NULL,
    "amount" DECIMAL(12, 2) NOT NULL,
    "method" "PaymentMethod" NOT NULL,
    "paidOn" DATE NOT NULL,
    "notes" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,
    CONSTRAINT "Payment_pkey" PRIMARY KEY ("id"),
    CONSTRAINT "Payment_billingMonth_first_day_check"
        CHECK (EXTRACT(DAY FROM "billingMonth") = 1),
    CONSTRAINT "Payment_leaseId_billingMonth_key" UNIQUE ("leaseId", "billingMonth"),
    CONSTRAINT "Payment_leaseId_fkey"
        FOREIGN KEY ("leaseId") REFERENCES "Lease"("id")
        ON DELETE RESTRICT ON UPDATE CASCADE
);

CREATE TABLE "MaintenanceRequest" (
    "id" TEXT NOT NULL,
    "unitId" TEXT NOT NULL,
    "leaseId" TEXT,
    "tenantId" TEXT NOT NULL,
    "title" TEXT NOT NULL,
    "description" TEXT NOT NULL,
    "priority" "Priority" NOT NULL DEFAULT 'MEDIUM',
    "status" "MaintenanceStatus" NOT NULL DEFAULT 'OPEN',
    "resolvedAt" TIMESTAMP(3),
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,
    CONSTRAINT "MaintenanceRequest_pkey" PRIMARY KEY ("id"),
    CONSTRAINT "MaintenanceRequest_unitId_fkey"
        FOREIGN KEY ("unitId") REFERENCES "Unit"("id")
        ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT "MaintenanceRequest_leaseId_fkey"
        FOREIGN KEY ("leaseId") REFERENCES "Lease"("id")
        ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT "MaintenanceRequest_tenantId_fkey"
        FOREIGN KEY ("tenantId") REFERENCES "TenantProfile"("id")
        ON DELETE RESTRICT ON UPDATE CASCADE
);

CREATE INDEX "User_role_isActive_idx" ON "User"("role", "isActive");

CREATE INDEX "Property_ownerId_idx" ON "Property"("ownerId");
CREATE INDEX "Property_managerId_idx" ON "Property"("managerId");
CREATE INDEX "Property_ownerId_city_idx" ON "Property"("ownerId", "city");

CREATE INDEX "Unit_propertyId_idx" ON "Unit"("propertyId");
CREATE INDEX "Unit_status_idx" ON "Unit"("status");
CREATE INDEX "Unit_propertyId_status_idx" ON "Unit"("propertyId", "status");

CREATE INDEX "TenantProfile_createdByLandlordId_idx"
    ON "TenantProfile"("createdByLandlordId");

CREATE INDEX "Lease_unitId_idx" ON "Lease"("unitId");
CREATE INDEX "Lease_tenantId_idx" ON "Lease"("tenantId");
CREATE INDEX "Lease_status_idx" ON "Lease"("status");
CREATE INDEX "Lease_status_startDate_endDate_idx"
    ON "Lease"("status", "startDate", "endDate");
CREATE UNIQUE INDEX "one_active_lease_per_unit"
    ON "Lease"("unitId") WHERE "status" = 'ACTIVE';

CREATE INDEX "Payment_leaseId_idx" ON "Payment"("leaseId");
CREATE INDEX "Payment_billingMonth_idx" ON "Payment"("billingMonth");
CREATE INDEX "Payment_paidOn_idx" ON "Payment"("paidOn");

CREATE INDEX "MaintenanceRequest_unitId_idx" ON "MaintenanceRequest"("unitId");
CREATE INDEX "MaintenanceRequest_leaseId_idx" ON "MaintenanceRequest"("leaseId");
CREATE INDEX "MaintenanceRequest_tenantId_idx" ON "MaintenanceRequest"("tenantId");
CREATE INDEX "MaintenanceRequest_status_idx" ON "MaintenanceRequest"("status");
CREATE INDEX "MaintenanceRequest_unitId_status_idx"
    ON "MaintenanceRequest"("unitId", "status");
