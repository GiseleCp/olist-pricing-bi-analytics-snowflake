-- ============================================================
-- PROJECT: Olist Pricing Intelligence
-- FILE: 03_load_raw_data.sql
-- DESCRIPTION: Loads all 9 CSV files from the Snowflake internal
--              stage (raw_stage) into the RAW schema tables.
--              Uses COPY INTO command — Snowflake native bulk load.
--              Prerequisites:
--              - 01_setup_environment.sql must have been executed
--              - 02_create_raw_tables.sql must have been executed
--              - CSV files must be uploaded to raw_stage
-- AUTHOR: Gisele CP
-- DATE: 2026-06-06
-- ============================================================

-- COPY INTO OVERVIEW
-- COPY INTO is Snowflake native bulk load command.
-- It reads files from a stage and loads into a table.
-- FILE_FORMAT parameters:
--   TYPE = CSV              -> file format
--   FIELD_OPTIONALLY_ENCLOSED_BY = '"' -> handles fields wrapped in quotes
--   SKIP_HEADER = 1         -> skips the first row (column headers)
-- The stage @olist_db.raw.raw_stage was created manually
-- via Snowflake UI and contains all 9 CSV files uploaded.

-- ============================================================
-- CONTEXT SETUP
-- ============================================================
-- Sets the active warehouse, database and schema for this session.
-- ============================================================

USE WAREHOUSE olist_wh;   -- compute layer for data loading
USE DATABASE olist_db;    -- project database
USE SCHEMA raw;           -- target schema for raw data loading

-- ============================================================
-- LOAD 1: CUSTOMERS
-- ============================================================
-- Loads customer registration data.
-- Expected rows: ~99,441
-- ============================================================

COPY INTO olist_db.raw.customers
FROM @olist_db.raw.raw_stage/olist_customers_dataset.csv
FILE_FORMAT = (TYPE = 'CSV' FIELD_OPTIONALLY_ENCLOSED_BY = '"' SKIP_HEADER = 1);

-- ============================================================
-- LOAD 2: GEOLOCATION
-- ============================================================
-- Loads zip code to coordinates mapping.
-- Expected rows: ~1,000,163 — largest file in the dataset.
-- May take slightly longer to load due to volume.
-- ============================================================

COPY INTO olist_db.raw.geolocation
FROM @olist_db.raw.raw_stage/olist_geolocation_dataset.csv
FILE_FORMAT = (TYPE = 'CSV' FIELD_OPTIONALLY_ENCLOSED_BY = '"' SKIP_HEADER = 1);

-- ============================================================
-- LOAD 3: ORDER ITEMS
-- ============================================================
-- Loads item-level order data including price and freight.
-- This is the most critical table for pricing analysis.
-- Expected rows: ~112,650
-- ============================================================

COPY INTO olist_db.raw.order_items
FROM @olist_db.raw.raw_stage/olist_order_items_dataset.csv
FILE_FORMAT = (TYPE = 'CSV' FIELD_OPTIONALLY_ENCLOSED_BY = '"' SKIP_HEADER = 1);

-- ============================================================
-- LOAD 4: ORDER PAYMENTS
-- ============================================================
-- Loads payment details per order.
-- Expected rows: ~103,886
-- Note: more rows than orders because one order can have
-- multiple payment records (installments or split payments).
-- ============================================================

COPY INTO olist_db.raw.order_payments
FROM @olist_db.raw.raw_stage/olist_order_payments_dataset.csv
FILE_FORMAT = (TYPE = 'CSV' FIELD_OPTIONALLY_ENCLOSED_BY = '"' SKIP_HEADER = 1);

-- ============================================================
-- LOAD 5: ORDER REVIEWS
-- ============================================================
-- Loads customer satisfaction reviews.
-- Expected rows: ~99,224
-- Note: comment fields have high null rate — this is expected.
-- ============================================================

COPY INTO olist_db.raw.order_reviews
FROM @olist_db.raw.raw_stage/olist_order_reviews_dataset.csv
FILE_FORMAT = (TYPE = 'CSV' FIELD_OPTIONALLY_ENCLOSED_BY = '"' SKIP_HEADER = 1);

-- ============================================================
-- LOAD 6: ORDERS
-- ============================================================
-- Loads master order data — central hub of the data model.
-- Expected rows: ~99,441
-- ============================================================

COPY INTO olist_db.raw.orders
FROM @olist_db.raw.raw_stage/olist_orders_dataset.csv
FILE_FORMAT = (TYPE = 'CSV' FIELD_OPTIONALLY_ENCLOSED_BY = '"' SKIP_HEADER = 1);

-- ============================================================
-- LOAD 7: PRODUCTS
-- ============================================================
-- Loads product catalog with categories and dimensions.
-- Expected rows: ~32,951
-- Note: 610 nulls in product_category_name — treated in STAGING.
-- ============================================================

COPY INTO olist_db.raw.products
FROM @olist_db.raw.raw_stage/olist_products_dataset.csv
FILE_FORMAT = (TYPE = 'CSV' FIELD_OPTIONALLY_ENCLOSED_BY = '"' SKIP_HEADER = 1);

-- ============================================================
-- LOAD 8: SELLERS
-- ============================================================
-- Loads seller registration data.
-- Expected rows: ~3,095
-- ============================================================

COPY INTO olist_db.raw.sellers
FROM @olist_db.raw.raw_stage/olist_sellers_dataset.csv
FILE_FORMAT = (TYPE = 'CSV' FIELD_OPTIONALLY_ENCLOSED_BY = '"' SKIP_HEADER = 1);

-- ============================================================
-- LOAD 9: CATEGORY TRANSLATION
-- ============================================================
-- Loads Portuguese to English category name mapping.
-- Expected rows: 71
-- Used in STAGING and MARTS to standardize category labels.
-- ============================================================

COPY INTO olist_db.raw.category_translation
FROM @olist_db.raw.raw_stage/product_category_name_translation.csv
FILE_FORMAT = (TYPE = 'CSV' FIELD_OPTIONALLY_ENCLOSED_BY = '"' SKIP_HEADER = 1);

-- ============================================================
-- VALIDATION
-- ============================================================
-- Confirms all tables were loaded with expected row counts.
-- Expected results:
--   customers:   99,441 rows
--   orders:      99,441 rows
--   order_items: 112,650 rows
--   products:    32,951 rows
-- ============================================================

SELECT 'customers' AS tabela, COUNT(*) AS total FROM olist_db.raw.customers
UNION ALL
SELECT 'orders', COUNT(*) FROM olist_db.raw.orders
UNION ALL
SELECT 'order_items', COUNT(*) FROM olist_db.raw.order_items
UNION ALL
SELECT 'products', COUNT(*) FROM olist_db.raw.products
UNION ALL
SELECT 'sellers', COUNT(*) FROM olist_db.raw.sellers
UNION ALL
SELECT 'geolocation', COUNT(*) FROM olist_db.raw.geolocation
UNION ALL
SELECT 'order_payments', COUNT(*) FROM olist_db.raw.order_payments
UNION ALL
SELECT 'order_reviews', COUNT(*) FROM olist_db.raw.order_reviews
UNION ALL
SELECT 'category_translation', COUNT(*) FROM olist_db.raw.category_translation
ORDER BY total DESC;