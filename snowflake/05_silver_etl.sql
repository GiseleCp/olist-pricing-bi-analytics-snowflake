-- ============================================================
-- PROJECT: Olist Pricing Intelligence
-- FILE: 05_silver_etl.sql
-- DESCRIPTION: ETL transformation from RAW to STAGING layer.
--              Applies all data quality treatments identified
--              in 04_data_profiling.sql. This is the Silver layer
--              of the Medallion Architecture — data is cleaned,
--              typed, enriched and business-ready for modeling.
--              Prerequisites:
--              - 03_load_raw_data.sql must have been executed
--              - 04_data_profiling.sql findings must be reviewed
-- AUTHOR: Gisele CP
-- DATE: 2026-06-06
-- ============================================================

-- SILVER LAYER DESIGN PRINCIPLES
-- 1. All VARCHAR fields cast to correct data types (FLOAT, INT, TIMESTAMP)
-- 2. Null values treated with COALESCE — no nulls in critical fields
-- 3. Only delivered orders — canceled/pending excluded from pricing analysis
-- 4. Derived fields added — business metrics calculated once, reused everywhere
-- 5. Data standardized — city names in title case, states in upper case
-- 6. Invalid records removed — coordinates outside Brazil, undefined payment types
-- 7. CREATE OR REPLACE — idempotent, safe to rerun after raw data updates
--
-- TREATMENTS APPLIED (from data profiling action items):
-- action 1: filter order_status = delivered
-- action 2: cast all numeric fields from VARCHAR
-- action 3: assign uncategorized to null categories
-- action 4: remove invalid geolocation coordinates
-- action 5: treat null review comments as no comment
-- action 6: freight ratio per category calculated
-- action 7: flag products with high freight ratio

-- ============================================================
-- CONTEXT SETUP
-- ============================================================
-- Sets the active warehouse, database and schema for this session.
-- ============================================================

USE WAREHOUSE olist_wh;   -- compute layer for transformation processing
USE DATABASE olist_db;    -- project database
USE SCHEMA staging;       -- target schema for cleaned and enriched data

-- ============================================================
-- TABLE 1: STAGING.ORDERS
-- ============================================================
-- Source: olist_db.raw.orders
-- Treatments applied:
--   - Filter: only order_status = 'delivered' (97.02% of orders)
--     Canceled and pending orders are excluded from pricing analysis
--     as they do not represent completed commercial transactions.
--   - Cast: all timestamp fields from VARCHAR to TIMESTAMP
--   - Derived: delivery_days — actual delivery time in days
--     Used to correlate delivery speed with customer satisfaction.
--   - Derived: delivery_delay_days — difference between actual and
--     estimated delivery. Negative = delivered early, positive = late.
--   - Derived: delivery_status — on_time / late / pending
--     Business flag for SLA monitoring and pricing impact analysis.
-- Expected rows: ~96,478 (delivered orders only)
-- ============================================================

CREATE OR REPLACE TABLE olist_db.staging.orders AS
SELECT
    order_id,                                                           -- unique order identifier
    customer_id,                                                        -- foreign key to customers
    order_status,                                                       -- always 'delivered' after filter
    CAST(order_purchase_timestamp AS TIMESTAMP) AS order_purchase_timestamp,   -- when order was placed
    CAST(order_approved_at AS TIMESTAMP) AS order_approved_at,                 -- when payment approved
    CAST(order_delivered_carrier_date AS TIMESTAMP) AS order_delivered_carrier_date,   -- shipped to carrier
    CAST(order_delivered_customer_date AS TIMESTAMP) AS order_delivered_customer_date, -- received by customer
    CAST(order_estimated_delivery_date AS TIMESTAMP) AS order_estimated_delivery_date, -- promised delivery date
    DATEDIFF('day',
        CAST(order_purchase_timestamp AS TIMESTAMP),
        CAST(order_delivered_customer_date AS TIMESTAMP)) AS delivery_days,    -- actual days to deliver
    DATEDIFF('day',
        CAST(order_delivered_customer_date AS TIMESTAMP),
        CAST(order_estimated_delivery_date AS TIMESTAMP)) AS delivery_delay_days, -- negative=early, positive=late
    CASE
        WHEN order_delivered_customer_date <= order_estimated_delivery_date THEN 'on_time'  -- delivered on or before promise
        WHEN order_delivered_customer_date > order_estimated_delivery_date THEN 'late'      -- delivered after promise
        ELSE 'pending'                                                          -- not yet delivered
    END AS delivery_status
FROM olist_db.raw.orders
WHERE order_status = 'delivered'              -- action 1: exclude non-delivered orders
AND order_purchase_timestamp IS NOT NULL;     -- exclude orders without purchase date

-- ============================================================
-- TABLE 2: STAGING.ORDER_ITEMS
-- ============================================================
-- Source: olist_db.raw.order_items
-- Treatments applied:
--   - Cast: price and freight_value from VARCHAR to FLOAT
--   - Derived: total_item_value = price + freight
--     Represents the true cost to the customer per item.
--   - Derived: freight_ratio_pct = freight / price * 100
--     Key pricing metric — high ratio indicates margin erosion.
--     NULLIF prevents division by zero when price = 0.
--   - Derived: freight_risk_flag — business classification:
--     critical (>30%): freight exceeds 30% of price, likely negative margin
--     attention (>20%): freight between 20-30%, margin under pressure
--     ok (<20%): acceptable freight-to-price ratio
-- Expected rows: ~112,650 (all items have price and freight)
-- ============================================================

CREATE OR REPLACE TABLE olist_db.staging.order_items AS
SELECT
    order_id,                                                           -- foreign key to orders
    order_item_id,                                                      -- item sequence within order
    product_id,                                                         -- foreign key to products
    seller_id,                                                          -- foreign key to sellers
    CAST(shipping_limit_date AS TIMESTAMP) AS shipping_limit_date,     -- seller shipping deadline
    CAST(price AS FLOAT) AS price,                                      -- item price in BRL
    CAST(freight_value AS FLOAT) AS freight_value,                     -- freight cost in BRL
    CAST(price AS FLOAT) + CAST(freight_value AS FLOAT) AS total_item_value,  -- total cost to customer
    ROUND(CAST(freight_value AS FLOAT) /
          NULLIF(CAST(price AS FLOAT), 0) * 100, 2) AS freight_ratio_pct,     -- freight as % of price
    CASE
        WHEN ROUND(CAST(freight_value AS FLOAT) /
             NULLIF(CAST(price AS FLOAT), 0) * 100, 2) > 30 THEN 'critical'   -- margin at risk
        WHEN ROUND(CAST(freight_value AS FLOAT) /
             NULLIF(CAST(price AS FLOAT), 0) * 100, 2) > 20 THEN 'attention'  -- margin under pressure
        ELSE 'ok'                                                               -- acceptable ratio
    END AS freight_risk_flag
FROM olist_db.raw.order_items
WHERE price IS NOT NULL                       -- action 2: exclude items without price
AND freight_value IS NOT NULL;                -- exclude items without freight value

-- ============================================================
-- TABLE 3: STAGING.PRODUCTS
-- ============================================================
-- Source: olist_db.raw.products
-- Treatments applied:
--   - Null treatment: COALESCE assigns 'uncategorized' to null
--     product_category_name (610 nulls identified in profiling).
--     Prevents R$ 179,535 revenue from being excluded in analysis.
--   - Cast: all numeric fields from VARCHAR to correct types
--   - Null treatment: COALESCE assigns 0 to null dimensions (2 nulls)
--   - Derived: product_volume_cm3 = length * height * width
--     Used to estimate freight cost and identify heavy/bulky products
--     that may require pricing adjustment to cover logistics costs.
-- Expected rows: ~32,951
-- ============================================================

CREATE OR REPLACE TABLE olist_db.staging.products AS
SELECT
    product_id,                                                                    -- unique product identifier
    COALESCE(product_category_name, 'uncategorized') AS product_category_name,    -- action 3: fill null categories
    CAST(product_name_lenght AS INT) AS product_name_length,                      -- name character count
    CAST(product_description_lenght AS INT) AS product_description_length,        -- description character count
    CAST(product_photos_qty AS INT) AS product_photos_qty,                        -- number of product photos
    COALESCE(CAST(product_weight_g AS FLOAT), 0) AS product_weight_g,             -- weight in grams (0 if null)
    COALESCE(CAST(product_length_cm AS FLOAT), 0) AS product_length_cm,           -- length in cm (0 if null)
    COALESCE(CAST(product_height_cm AS FLOAT), 0) AS product_height_cm,           -- height in cm (0 if null)
    COALESCE(CAST(product_width_cm AS FLOAT), 0) AS product_width_cm,             -- width in cm (0 if null)
    COALESCE(CAST(product_weight_g AS FLOAT), 0) *
    COALESCE(CAST(product_length_cm AS FLOAT), 0) *
    COALESCE(CAST(product_height_cm AS FLOAT), 0) *
    COALESCE(CAST(product_width_cm AS FLOAT), 0) AS product_volume_cm3            -- derived: cubic volume
FROM olist_db.raw.products;

-- ============================================================
-- TABLE 4: STAGING.CUSTOMERS
-- ============================================================
-- Source: olist_db.raw.customers
-- Treatments applied:
--   - INITCAP: standardizes city names to Title Case
--     e.g. 'sao paulo' -> 'Sao Paulo'
--   - UPPER: standardizes state codes to uppercase
--     e.g. 'sp' -> 'SP'
-- Expected rows: ~99,441 (zero nulls confirmed in profiling)
-- ============================================================

CREATE OR REPLACE TABLE olist_db.staging.customers AS
SELECT
    customer_id,                                    -- transaction-level customer identifier
    customer_unique_id,                             -- true customer identifier across orders
    customer_zip_code_prefix,                       -- first 5 digits of zip code
    INITCAP(customer_city) AS customer_city,        -- standardized city name in Title Case
    UPPER(customer_state) AS customer_state         -- standardized state code in UPPERCASE
FROM olist_db.raw.customers;

-- ============================================================
-- TABLE 5: STAGING.SELLERS
-- ============================================================
-- Source: olist_db.raw.sellers
-- Treatments applied:
--   - INITCAP: standardizes city names to Title Case
--   - UPPER: standardizes state codes to uppercase
-- Expected rows: ~3,095 (zero nulls confirmed in profiling)
-- ============================================================

CREATE OR REPLACE TABLE olist_db.staging.sellers AS
SELECT
    seller_id,                                      -- unique seller identifier
    seller_zip_code_prefix,                         -- first 5 digits of seller zip code
    INITCAP(seller_city) AS seller_city,            -- standardized city name in Title Case
    UPPER(seller_state) AS seller_state             -- standardized state code in UPPERCASE
FROM olist_db.raw.sellers;

-- ============================================================
-- TABLE 6: STAGING.ORDER_PAYMENTS
-- ============================================================
-- Source: olist_db.raw.order_payments
-- Treatments applied:
--   - Filter: removes payment_type = 'not_defined' (3 records)
--     These records have payment_value = 0 and no valid type.
--   - Cast: payment_sequential and payment_installments to INT
--   - Cast: payment_value to FLOAT
-- Expected rows: ~103,883 (3 not_defined records removed)
-- ============================================================

CREATE OR REPLACE TABLE olist_db.staging.order_payments AS
SELECT
    order_id,                                                           -- foreign key to orders
    CAST(payment_sequential AS INT) AS payment_sequential,             -- payment sequence (for split payments)
    payment_type,                                                       -- credit_card, boleto, voucher, debit_card
    CAST(payment_installments AS INT) AS payment_installments,         -- number of installments
    CAST(payment_value AS FLOAT) AS payment_value                      -- payment amount in BRL
FROM olist_db.raw.order_payments
WHERE payment_type != 'not_defined';              -- remove 3 records with undefined payment type

-- ============================================================
-- TABLE 7: STAGING.ORDER_REVIEWS
-- ============================================================
-- Source: olist_db.raw.order_reviews
-- Treatments applied:
--   - Cast: review_score from VARCHAR to INT
--   - COALESCE: replaces null comment titles with 'no_title'
--     (87,656 nulls = 88% of records — all treated)
--   - COALESCE: replaces null comment messages with 'no_comment'
--     (58,247 nulls = 59% of records — all treated)
--   - Cast: date fields from VARCHAR to TIMESTAMP
-- Expected rows: ~99,224
-- ============================================================

CREATE OR REPLACE TABLE olist_db.staging.order_reviews AS
SELECT
    review_id,                                                              -- unique review identifier
    order_id,                                                               -- foreign key to orders
    CAST(review_score AS INT) AS review_score,                             -- satisfaction score 1-5
    COALESCE(review_comment_title, 'no_title') AS review_comment_title,    -- action 5: fill null titles
    COALESCE(review_comment_message, 'no_comment') AS review_comment_message, -- fill null messages
    CAST(review_creation_date AS TIMESTAMP) AS review_creation_date,       -- when review was created
    CAST(review_answer_timestamp AS TIMESTAMP) AS review_answer_timestamp  -- when customer submitted
FROM olist_db.raw.order_reviews;

-- ============================================================
-- TABLE 8: STAGING.GEOLOCATION
-- ============================================================
-- Source: olist_db.raw.geolocation
-- Treatments applied:
--   - Filter: removes coordinates outside Brazil geographic bounds
--     Brazil latitude range:  -33.75 (south) to +5.27 (north)
--     Brazil longitude range: -73.98 (west)  to -34.79 (east)
--     31 invalid latitudes and 37 invalid longitudes removed.
--   - Cast: lat and lng from VARCHAR to FLOAT
--   - INITCAP: standardizes city names to Title Case
--   - UPPER: standardizes state codes to uppercase
-- Expected rows: ~1,000,121 (42 invalid coordinates removed)
-- ============================================================

CREATE OR REPLACE TABLE olist_db.staging.geolocation AS
SELECT
    geolocation_zip_code_prefix,                                        -- first 5 digits of zip code
    CAST(geolocation_lat AS FLOAT) AS geolocation_lat,                  -- latitude coordinate
    CAST(geolocation_lng AS FLOAT) AS geolocation_lng,                  -- longitude coordinate
    INITCAP(geolocation_city) AS geolocation_city,                      -- standardized city name
    UPPER(geolocation_state) AS geolocation_state                       -- standardized state code
FROM olist_db.raw.geolocation
WHERE CAST(geolocation_lat AS FLOAT) BETWEEN -33.75 AND 5.27            -- action 4: Brazil latitude bounds
AND CAST(geolocation_lng AS FLOAT) BETWEEN -73.98 AND -34.79;           -- action 4: Brazil longitude bounds

-- ============================================================
-- TABLE 9: STAGING.CATEGORY_TRANSLATION
-- ============================================================
-- Source: olist_db.raw.category_translation
-- No treatments required — 71 records, zero nulls confirmed.
-- Used in MARTS layer to display English category names
-- in dashboards and reports.
-- Expected rows: 71
-- ============================================================

CREATE OR REPLACE TABLE olist_db.staging.category_translation AS
SELECT
    product_category_name,          -- category name in Portuguese
    product_category_name_english   -- category name in English
FROM olist_db.raw.category_translation;

-- ============================================================
-- VALIDATION
-- ============================================================
-- Confirms all 9 tables were created in the STAGING schema.
-- Compare row counts against RAW to validate treatments:
--   orders:         96,478 vs 99,441 raw (-2,963 non-delivered)
--   order_payments: 103,883 vs 103,886 raw (-3 not_defined)
--   geolocation:  1,000,121 vs 1,000,163 raw (-42 invalid coords)
--   all others: same count as RAW
-- ============================================================

SHOW TABLES IN SCHEMA olist_db.staging;