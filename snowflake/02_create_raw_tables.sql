-- ============================================================
-- PROJECT: Olist Pricing Intelligence
-- FILE: 02_create_raw_tables.sql
-- DESCRIPTION: Creates all raw tables in the RAW schema.
--              All columns are defined as VARCHAR intentionally —
--              this is the landing zone pattern. Type casting
--              and data quality are handled in the STAGING layer.
--              Using CREATE OR REPLACE makes the script idempotent,
--              safe to run multiple times without errors.
-- AUTHOR: Gisele CP
-- DATE: 2026-06-06
-- ============================================================

-- RAW LAYER DESIGN PRINCIPLES
-- 1. All columns are VARCHAR — preserves data exactly as received
-- 2. No constraints, no foreign keys — raw data may have issues
-- 3. No transformations — source data must be auditable
-- 4. CREATE OR REPLACE — idempotent, safe to rerun
-- 5. Tables mirror the CSV structure 1:1

-- ============================================================
-- CONTEXT SETUP
-- ============================================================
-- Sets the active warehouse, database and schema for this session.
-- All subsequent statements will execute in this context.
-- ============================================================

USE WAREHOUSE olist_wh;   -- compute layer for query processing
USE DATABASE olist_db;    -- top-level container for all project objects
USE SCHEMA raw;           -- landing zone schema for raw CSV data

-- ============================================================
-- TABLE 1: CUSTOMERS
-- ============================================================
-- Stores customer registration data.
-- customer_id: transaction-level identifier (one per order)
-- customer_unique_id: true customer identifier across orders
-- Note: one customer_unique_id can have multiple customer_ids
-- Source: olist_customers_dataset.csv | Expected rows: ~99,441
-- ============================================================

CREATE OR REPLACE TABLE olist_db.raw.customers (
    customer_id              VARCHAR,   -- transaction-level customer identifier
    customer_unique_id       VARCHAR,   -- unique customer across all orders
    customer_zip_code_prefix VARCHAR,   -- first 5 digits of zip code
    customer_city            VARCHAR,   -- customer city name
    customer_state           VARCHAR    -- customer state abbreviation (e.g. SP, RJ)
);

-- ============================================================
-- TABLE 2: GEOLOCATION
-- ============================================================
-- Maps Brazilian zip codes to geographic coordinates.
-- Used for regional pricing analysis and Price Index by region.
-- Contains latitude/longitude for mapping and distance analysis.
-- Source: olist_geolocation_dataset.csv | Expected rows: ~1,000,163
-- Note: largest table in the dataset — 1M+ records
-- ============================================================

CREATE OR REPLACE TABLE olist_db.raw.geolocation (
    geolocation_zip_code_prefix VARCHAR,   -- first 5 digits of zip code
    geolocation_lat             VARCHAR,   -- latitude coordinate (stored as VARCHAR)
    geolocation_lng             VARCHAR,   -- longitude coordinate (stored as VARCHAR)
    geolocation_city            VARCHAR,   -- city name for this zip code
    geolocation_state           VARCHAR    -- state abbreviation for this zip code
);

-- ============================================================
-- TABLE 3: ORDER ITEMS
-- ============================================================
-- Core pricing table — contains price and freight per item.
-- This is the primary source for all pricing analysis:
-- markup, margin, freight ratio and price outlier detection.
-- One order can have multiple items (order_item_id sequence).
-- Source: olist_order_items_dataset.csv | Expected rows: ~112,650
-- ============================================================

CREATE OR REPLACE TABLE olist_db.raw.order_items (
    order_id            VARCHAR,   -- foreign key to orders table
    order_item_id       VARCHAR,   -- sequence number of item within order
    product_id          VARCHAR,   -- foreign key to products table
    seller_id           VARCHAR,   -- foreign key to sellers table
    shipping_limit_date VARCHAR,   -- deadline for seller to ship the item
    price               VARCHAR,   -- item price in BRL (stored as VARCHAR)
    freight_value       VARCHAR    -- freight cost for this item in BRL
);

-- ============================================================
-- TABLE 4: ORDER PAYMENTS
-- ============================================================
-- Contains payment details per order.
-- One order can have multiple payment records (installments).
-- Used for revenue analysis and payment type segmentation.
-- Source: olist_order_payments_dataset.csv | Expected rows: ~103,886
-- ============================================================

CREATE OR REPLACE TABLE olist_db.raw.order_payments (
    order_id             VARCHAR,   -- foreign key to orders table
    payment_sequential   VARCHAR,   -- sequence when multiple payments per order
    payment_type         VARCHAR,   -- credit_card, boleto, voucher, debit_card
    payment_installments VARCHAR,   -- number of installments chosen by customer
    payment_value        VARCHAR    -- payment amount in BRL
);

-- ============================================================
-- TABLE 5: ORDER REVIEWS
-- ============================================================
-- Customer satisfaction data per order.
-- review_score is the key field — 1 to 5 stars.
-- Used for correlating pricing with customer satisfaction.
-- Note: comment fields have high null rate (~58-88%) — expected,
-- as customers often rate without leaving written feedback.
-- Source: olist_order_reviews_dataset.csv | Expected rows: ~99,224
-- ============================================================

CREATE OR REPLACE TABLE olist_db.raw.order_reviews (
    review_id               VARCHAR,   -- unique review identifier
    order_id                VARCHAR,   -- foreign key to orders table
    review_score            VARCHAR,   -- satisfaction score 1 to 5 stars
    review_comment_title    VARCHAR,   -- optional review title (88% null)
    review_comment_message  VARCHAR,   -- optional review message (58% null)
    review_creation_date    VARCHAR,   -- date review was created by system
    review_answer_timestamp VARCHAR    -- date customer submitted the review
);

-- ============================================================
-- TABLE 6: ORDERS
-- ============================================================
-- Master order table — connects all other tables.
-- Central hub of the star schema in the MARTS layer.
-- Contains order lifecycle timestamps for delivery analysis.
-- Note: order_delivered_customer_date has 2,965 nulls —
-- expected for orders not yet delivered (shipped, processing).
-- Source: olist_orders_dataset.csv | Expected rows: ~99,441
-- ============================================================

CREATE OR REPLACE TABLE olist_db.raw.orders (
    order_id                      VARCHAR,   -- unique order identifier (primary key)
    customer_id                   VARCHAR,   -- foreign key to customers table
    order_status                  VARCHAR,   -- delivered, shipped, canceled, etc.
    order_purchase_timestamp      VARCHAR,   -- when customer placed the order
    order_approved_at             VARCHAR,   -- when payment was approved
    order_delivered_carrier_date  VARCHAR,   -- when seller handed to carrier
    order_delivered_customer_date VARCHAR,   -- when customer received the order
    order_estimated_delivery_date VARCHAR    -- estimated delivery date shown to customer
);

-- ============================================================
-- TABLE 7: PRODUCTS
-- ============================================================
-- Product catalog with category and physical dimensions.
-- Category is critical for pricing segmentation analysis.
-- Physical dimensions (weight, size) impact freight calculation.
-- Note: 610 nulls in product_category_name — treated in STAGING
-- with COALESCE as 'uncategorized'.
-- Source: olist_products_dataset.csv | Expected rows: ~32,951
-- ============================================================

CREATE OR REPLACE TABLE olist_db.raw.products (
    product_id                 VARCHAR,   -- unique product identifier (primary key)
    product_category_name      VARCHAR,   -- product category in Portuguese (610 nulls)
    product_name_lenght        VARCHAR,   -- character length of product name
    product_description_lenght VARCHAR,   -- character length of product description
    product_photos_qty         VARCHAR,   -- number of product photos
    product_weight_g           VARCHAR,   -- product weight in grams
    product_length_cm          VARCHAR,   -- product length in centimeters
    product_height_cm          VARCHAR,   -- product height in centimeters
    product_width_cm           VARCHAR    -- product width in centimeters
);

-- ============================================================
-- TABLE 8: SELLERS
-- ============================================================
-- Seller registration data with location information.
-- Used for seller performance analysis and regional pricing.
-- Source: olist_sellers_dataset.csv | Expected rows: ~3,095
-- ============================================================

CREATE OR REPLACE TABLE olist_db.raw.sellers (
    seller_id              VARCHAR,   -- unique seller identifier (primary key)
    seller_zip_code_prefix VARCHAR,   -- first 5 digits of seller zip code
    seller_city            VARCHAR,   -- seller city name
    seller_state           VARCHAR    -- seller state abbreviation
);

-- ============================================================
-- TABLE 9: CATEGORY TRANSLATION
-- ============================================================
-- Maps Portuguese category names to English equivalents.
-- Used to standardize category names for international reporting
-- and dashboard labels.
-- Source: product_category_name_translation.csv | Expected rows: 71
-- ============================================================

CREATE OR REPLACE TABLE olist_db.raw.category_translation (
    product_category_name         VARCHAR,   -- category name in Portuguese
    product_category_name_english VARCHAR    -- category name in English
);

-- ============================================================
-- VALIDATION
-- ============================================================
-- Confirms all 9 tables were created successfully in RAW schema.
-- Expected result: 9 tables listed with 0 rows each.
-- Rows will be populated in the next step: 03_load_raw_data.sql
-- ============================================================

SHOW TABLES IN SCHEMA olist_db.raw;