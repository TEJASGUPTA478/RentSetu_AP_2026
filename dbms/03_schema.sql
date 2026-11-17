CREATE TABLE "User" (
    user_id SERIAL PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    email VARCHAR(255) UNIQUE NOT NULL
);

CREATE TABLE "Property" (
    property_id SERIAL PRIMARY KEY,
    owner_id INTEGER NOT NULL REFERENCES "User"(user_id),
    address VARCHAR(255) NOT NULL,
    city VARCHAR(100) NOT NULL,
    rent NUMERIC(10,2) NOT NULL
);

CREATE TABLE "Booking" (
    booking_id SERIAL PRIMARY KEY,
    property_id INTEGER NOT NULL REFERENCES "Property"(property_id),
    tenant_id INTEGER NOT NULL REFERENCES "User"(user_id),
    start_date DATE NOT NULL,
    end_date DATE NOT NULL,
    CHECK (end_date > start_date)
);

CREATE TABLE "Payment" (
    payment_id SERIAL PRIMARY KEY,
    booking_id INTEGER NOT NULL REFERENCES "Booking"(booking_id) ON DELETE CASCADE,
    amount NUMERIC(10,2) NOT NULL CHECK (amount >= 0),
    payment_date DATE NOT NULL
);

-- Indexes for faster lookups
CREATE INDEX idx_property_owner ON "Property"(owner_id);
CREATE INDEX idx_booking_property ON "Booking"(property_id);
CREATE INDEX idx_booking_tenant ON "Booking"(tenant_id);
CREATE INDEX idx_payment_booking ON "Payment"(booking_id);
