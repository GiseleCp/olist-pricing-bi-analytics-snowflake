-- ============================================================
-- PROJECT: Olist Pricing Intelligence
-- FILE: 04_data_profiling.sql
-- DESCRIPTION: Comprehensive data profiling of all RAW tables.
--              Investigates data quality, null values, duplicates,
--              price ranges, referential integrity and business
--              patterns to guide STAGING layer treatment decisions.
--              All findings are documented as action items for
--              05_silver_etl.sql.
-- AUTHOR: Gisele CP
-- DATE: 2026-06-06
-- ============================================================

-- DATA PROFILING OVERVIEW
-- Data Profiling is the process of examining raw data to understand
-- its structure, content, quality and relationships before transformation.
-- A senior analyst never transforms data without first profiling it.
--
-- This file covers 22 analysis steps organized in 5 categories:
--
-- VOLUME       -> Steps 1       (record counts per table)
-- NULLS        -> Steps 2-9     (null analysis per table)
-- DUPLICATES   -> Step 10       (primary key uniqueness)
-- RANGES       -> Steps 11-15   (price, status, payment distributions)
-- INTEGRITY    -> Steps 16-22   (referential integrity, dates, outliers)
--
-- SQL TECHNIQUES USED:
-- UNION ALL            -> combines results of multiple queries into one
-- Conditional Aggregation (CASE WHEN inside COUNT/SUM) -> counts rows matching a condition
-- Window Functions (COUNT() OVER()) -> calculates totals without collapsing rows
-- CTE (WITH clause)   -> creates temporary named result set for reuse
-- NULLIF()            -> prevents division by zero errors
-- CAST()              -> converts VARCHAR to numeric/date types

-- ============================================================
-- CONTEXT SETUP
-- ============================================================
-- Sets the active warehouse, database and schema for this session.
-- ============================================================

USE WAREHOUSE olist_wh;   -- compute layer for query processing
USE DATABASE olist_db;    -- project database
USE SCHEMA raw;           -- schema containing raw source tables

-- ============================================================
-- STEP 1: RECORD COUNT
-- ============================================================
-- First step of any data profiling — validates that all tables
-- were loaded with the expected number of records.
-- Uses UNION ALL to combine counts from all 9 tables in one query.
-- UNION ALL is preferred over UNION because it does not deduplicate
-- rows, which is faster and correct here since each row has a
-- different table name.
-- Expected total: ~1.6M records across all tables.
-- ============================================================

SELECT 'customers' AS tabela, COUNT(*) AS total_registros FROM olist_db.raw.customers
UNION ALL
SELECT 'geolocation', COUNT(*) FROM olist_db.raw.geolocation
UNION ALL
SELECT 'order_items', COUNT(*) FROM olist_db.raw.order_items
UNION ALL
SELECT 'order_payments', COUNT(*) FROM olist_db.raw.order_payments
UNION ALL
SELECT 'order_reviews', COUNT(*) FROM olist_db.raw.order_reviews
UNION ALL
SELECT 'orders', COUNT(*) FROM olist_db.raw.orders
UNION ALL
SELECT 'products', COUNT(*) FROM olist_db.raw.products
UNION ALL
SELECT 'sellers', COUNT(*) FROM olist_db.raw.sellers
UNION ALL
SELECT 'category_translation', COUNT(*) FROM olist_db.raw.category_translation
ORDER BY tabela;

-- FINDINGS:
-- geolocation: 1.000.163 records - largest table
-- customers and orders: same count (99.441) - 1 order per customer
-- order_items > orders - multiple items per order
-- products: 32.951 unique products

-- ============================================================
-- STEP 2: NULL ANALYSIS - ORDER ITEMS
-- ============================================================
-- Null analysis identifies missing values that could impact
-- analysis quality. order_items is analyzed first because it
-- contains price and freight_value — the core fields for
-- all pricing analysis in this project.
-- COUNT(column) counts non-null values — if equal to COUNT(*),
-- the column has zero nulls.
-- CASE WHEN price IS NULL THEN 1 ELSE 0 END is Conditional
-- Aggregation — counts only rows matching the condition.
-- ============================================================

SELECT
    COUNT(*) AS total,
    COUNT(order_id) AS order_id_preenchido,       -- non-null order_id count
    COUNT(product_id) AS product_id_preenchido,   -- non-null product_id count
    COUNT(price) AS price_preenchido,             -- non-null price count
    COUNT(freight_value) AS freight_preenchido,   -- non-null freight count
    SUM(CASE WHEN price IS NULL THEN 1 ELSE 0 END) AS price_nulo,           -- null price count
    SUM(CASE WHEN freight_value IS NULL THEN 1 ELSE 0 END) AS freight_nulo  -- null freight count
FROM olist_db.raw.order_items;

-- FINDINGS:
-- order_items: 112.650 records, zero nulls
-- price and freight_value: 100% complete
-- clean table, ready for pricing analysis

-- ============================================================
-- STEP 3: NULL ANALYSIS - CUSTOMERS
-- ============================================================
-- Validates customer registration data completeness.
-- All fields are required for customer segmentation and
-- regional pricing analysis.
-- ============================================================

SELECT
    COUNT(*) AS total,
    SUM(CASE WHEN customer_id IS NULL THEN 1 ELSE 0 END) AS customer_id_nulo,
    SUM(CASE WHEN customer_unique_id IS NULL THEN 1 ELSE 0 END) AS unique_id_nulo,
    SUM(CASE WHEN customer_zip_code_prefix IS NULL THEN 1 ELSE 0 END) AS zip_nulo,
    SUM(CASE WHEN customer_city IS NULL THEN 1 ELSE 0 END) AS city_nulo,
    SUM(CASE WHEN customer_state IS NULL THEN 1 ELSE 0 END) AS state_nulo
FROM olist_db.raw.customers;

-- FINDINGS:
-- customers: 99.441 records, zero nulls
-- all fields: 100% complete

-- ============================================================
-- STEP 4: NULL ANALYSIS - GEOLOCATION
-- ============================================================
-- Validates geographic coordinate data completeness.
-- Null coordinates would break regional price index mapping.
-- ============================================================

SELECT
    COUNT(*) AS total,
    SUM(CASE WHEN geolocation_zip_code_prefix IS NULL THEN 1 ELSE 0 END) AS zip_nulo,
    SUM(CASE WHEN geolocation_lat IS NULL THEN 1 ELSE 0 END) AS lat_nulo,
    SUM(CASE WHEN geolocation_lng IS NULL THEN 1 ELSE 0 END) AS lng_nulo,
    SUM(CASE WHEN geolocation_city IS NULL THEN 1 ELSE 0 END) AS city_nulo,
    SUM(CASE WHEN geolocation_state IS NULL THEN 1 ELSE 0 END) AS state_nulo
FROM olist_db.raw.geolocation;

-- FINDINGS:
-- geolocation: 1.000.163 records, zero nulls
-- all fields: 100% complete

-- ============================================================
-- STEP 5: NULL ANALYSIS - ORDER PAYMENTS
-- ============================================================
-- Validates payment data completeness.
-- payment_value nulls would undercount total revenue.
-- payment_type nulls would break payment segmentation analysis.
-- ============================================================

SELECT
    COUNT(*) AS total,
    SUM(CASE WHEN order_id IS NULL THEN 1 ELSE 0 END) AS order_id_nulo,
    SUM(CASE WHEN payment_sequential IS NULL THEN 1 ELSE 0 END) AS sequential_nulo,
    SUM(CASE WHEN payment_type IS NULL THEN 1 ELSE 0 END) AS type_nulo,
    SUM(CASE WHEN payment_installments IS NULL THEN 1 ELSE 0 END) AS installments_nulo,
    SUM(CASE WHEN payment_value IS NULL THEN 1 ELSE 0 END) AS value_nulo
FROM olist_db.raw.order_payments;

-- FINDINGS:
-- order_payments: 103.886 records, zero nulls
-- all fields: 100% complete

-- ============================================================
-- STEP 6: NULL ANALYSIS - ORDER REVIEWS
-- ============================================================
-- Validates review data completeness.
-- Comment fields are optional by design — high null rate expected.
-- review_score is mandatory and must have zero nulls.
-- ============================================================

SELECT
    COUNT(*) AS total,
    SUM(CASE WHEN review_id IS NULL THEN 1 ELSE 0 END) AS review_id_nulo,
    SUM(CASE WHEN order_id IS NULL THEN 1 ELSE 0 END) AS order_id_nulo,
    SUM(CASE WHEN review_score IS NULL THEN 1 ELSE 0 END) AS score_nulo,
    SUM(CASE WHEN review_comment_title IS NULL THEN 1 ELSE 0 END) AS title_nulo,
    SUM(CASE WHEN review_comment_message IS NULL THEN 1 ELSE 0 END) AS message_nulo,
    SUM(CASE WHEN review_creation_date IS NULL THEN 1 ELSE 0 END) AS creation_date_nulo,
    SUM(CASE WHEN review_answer_timestamp IS NULL THEN 1 ELSE 0 END) AS answer_date_nulo
FROM olist_db.raw.order_reviews;

-- FINDINGS:
-- order_reviews: 99.224 records
-- review_comment_title: 87.656 nulls (88%) - expected, optional field
-- review_comment_message: 58.247 nulls (59%) - expected, optional field
-- review_score: 100% complete - key field for analysis
-- action: treat nulls as 'no comment' in silver layer

-- ============================================================
-- STEP 7: NULL ANALYSIS - SELLERS
-- ============================================================
-- Validates seller registration data completeness.
-- seller_state is required for regional pricing analysis.
-- ============================================================

SELECT
    COUNT(*) AS total,
    SUM(CASE WHEN seller_id IS NULL THEN 1 ELSE 0 END) AS seller_id_nulo,
    SUM(CASE WHEN seller_zip_code_prefix IS NULL THEN 1 ELSE 0 END) AS zip_nulo,
    SUM(CASE WHEN seller_city IS NULL THEN 1 ELSE 0 END) AS city_nulo,
    SUM(CASE WHEN seller_state IS NULL THEN 1 ELSE 0 END) AS state_nulo
FROM olist_db.raw.sellers;

-- FINDINGS:
-- sellers: 3.095 records, zero nulls
-- all fields: 100% complete

-- ============================================================
-- STEP 8: NULL ANALYSIS - ORDERS
-- ============================================================
-- Validates order lifecycle data completeness.
-- order_delivered_customer_date nulls are expected —
-- they represent orders not yet delivered (shipped, processing).
-- All timestamp fields are stored as VARCHAR and will be cast
-- to TIMESTAMP in the STAGING layer.
-- ============================================================

SELECT
    COUNT(*) AS total,
    SUM(CASE WHEN order_id IS NULL THEN 1 ELSE 0 END) AS order_id_nulo,
    SUM(CASE WHEN customer_id IS NULL THEN 1 ELSE 0 END) AS customer_id_nulo,
    SUM(CASE WHEN order_status IS NULL THEN 1 ELSE 0 END) AS status_nulo,
    SUM(CASE WHEN order_purchase_timestamp IS NULL THEN 1 ELSE 0 END) AS purchase_date_nulo,
    SUM(CASE WHEN order_delivered_customer_date IS NULL THEN 1 ELSE 0 END) AS delivered_date_nulo,
    SUM(CASE WHEN order_estimated_delivery_date IS NULL THEN 1 ELSE 0 END) AS estimated_date_nulo
FROM olist_db.raw.orders;

-- FINDINGS:
-- orders: 99.441 records
-- order_delivered_customer_date: 2.965 nulls - expected, undelivered orders
-- all other fields: 100% complete

-- ============================================================
-- STEP 9: NULL ANALYSIS - PRODUCTS
-- ============================================================
-- Validates product catalog data completeness.
-- product_category_name nulls impact pricing by category analysis.
-- Physical dimension nulls impact freight calculation.
-- ============================================================

SELECT
    COUNT(*) AS total,
    SUM(CASE WHEN product_id IS NULL THEN 1 ELSE 0 END) AS product_id_nulo,
    SUM(CASE WHEN product_category_name IS NULL THEN 1 ELSE 0 END) AS category_nulo,
    SUM(CASE WHEN product_weight_g IS NULL THEN 1 ELSE 0 END) AS weight_nulo,
    SUM(CASE WHEN product_length_cm IS NULL THEN 1 ELSE 0 END) AS length_nulo,
    SUM(CASE WHEN product_height_cm IS NULL THEN 1 ELSE 0 END) AS height_nulo,
    SUM(CASE WHEN product_width_cm IS NULL THEN 1 ELSE 0 END) AS width_nulo
FROM olist_db.raw.products;

-- FINDINGS:
-- products: 32.951 records
-- product_category_name: 610 nulls - products without category
-- weight and dimensions: 2 nulls each - minor, needs treatment in silver layer
-- action: fill nulls with 'uncategorized' in silver layer

-- ============================================================
-- STEP 10: DUPLICATE ANALYSIS
-- ============================================================
-- Validates primary key uniqueness in entity tables.
-- Duplicates in primary keys would cause row multiplication
-- in JOINs and distort all aggregated metrics.
-- Logic: duplicates = total rows - distinct id count
-- Only entity tables are checked here — transactional tables
-- (order_items, order_payments) naturally have repeated order_ids.
-- ============================================================

SELECT 'customers' AS tabela,
    COUNT(*) AS total,
    COUNT(DISTINCT customer_id) AS unique_ids,               -- distinct primary keys
    COUNT(*) - COUNT(DISTINCT customer_id) AS duplicatas     -- difference = duplicates
FROM olist_db.raw.customers
UNION ALL
SELECT 'orders',
    COUNT(*),
    COUNT(DISTINCT order_id),
    COUNT(*) - COUNT(DISTINCT order_id)
FROM olist_db.raw.orders
UNION ALL
SELECT 'products',
    COUNT(*),
    COUNT(DISTINCT product_id),
    COUNT(*) - COUNT(DISTINCT product_id)
FROM olist_db.raw.products
UNION ALL
SELECT 'sellers',
    COUNT(*),
    COUNT(DISTINCT seller_id),
    COUNT(*) - COUNT(DISTINCT seller_id)
FROM olist_db.raw.sellers;

-- FINDINGS:
-- customers: 99.441 records, 0 duplicates
-- orders: 99.441 records, 0 duplicates
-- products: 32.951 records, 0 duplicates
-- sellers: 3.095 records, 0 duplicates
-- all primary keys are unique and clean

-- ============================================================
-- STEP 11: PRICE RANGE ANALYSIS
-- ============================================================
-- Analyzes price and freight value distributions.
-- Key metrics for pricing intelligence:
-- STDDEV (standard deviation) measures price dispersion.
-- High stddev relative to mean indicates heterogeneous pricing
-- that requires category-level analysis.
-- Zero or negative prices would indicate data entry errors.
-- CAST is required because all fields are stored as VARCHAR in RAW.
-- ============================================================

SELECT
    COUNT(*) AS total,
    MIN(CAST(price AS FLOAT)) AS price_min,                      -- lowest price
    MAX(CAST(price AS FLOAT)) AS price_max,                      -- highest price
    ROUND(AVG(CAST(price AS FLOAT)), 2) AS price_avg,            -- mean price
    ROUND(STDDEV(CAST(price AS FLOAT)), 2) AS price_stddev,      -- price dispersion
    MIN(CAST(freight_value AS FLOAT)) AS freight_min,            -- lowest freight
    MAX(CAST(freight_value AS FLOAT)) AS freight_max,            -- highest freight
    ROUND(AVG(CAST(freight_value AS FLOAT)), 2) AS freight_avg,  -- mean freight
    SUM(CASE WHEN CAST(price AS FLOAT) <= 0 THEN 1 ELSE 0 END) AS price_zero_negativo,     -- invalid prices
    SUM(CASE WHEN CAST(freight_value AS FLOAT) < 0 THEN 1 ELSE 0 END) AS freight_negativo  -- invalid freight
FROM olist_db.raw.order_items;

-- FINDINGS:
-- price range: R$ 0.85 to R$ 6.735
-- price avg: R$ 120.65, stddev: 183.63 - high dispersion
-- high stddev indicates pricing analysis must be done by category
-- freight range: R$ 0 to R$ 409.68, avg: R$ 19.99
-- zero negative or zero prices - clean data ready for pricing analysis
-- action: segment pricing analysis by product category in silver layer

-- ============================================================
-- STEP 12: ORDER STATUS DISTRIBUTION
-- ============================================================
-- Analyzes order status distribution to understand data scope.
-- Window function SUM(COUNT(*)) OVER() calculates the grand total
-- without collapsing the GROUP BY — enables percentual calculation
-- in the same query without a subquery.
-- Only 'delivered' orders will be used in pricing analysis.
-- ============================================================

SELECT
    order_status,
    COUNT(*) AS total,
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER(), 2) AS percentual  -- % of total using window function
FROM olist_db.raw.orders
GROUP BY order_status
ORDER BY total DESC;

-- FINDINGS:
-- 97.02% orders delivered - healthy fulfillment rate
-- 0.63% canceled - low cancellation rate
-- canceled and unavailable orders must be excluded from pricing analysis
-- action: filter order_status = 'delivered' in silver layer for pricing

-- ============================================================
-- STEP 13: PAYMENT TYPE DISTRIBUTION
-- ============================================================
-- Analyzes payment method preferences and average ticket by type.
-- Payment type is a key segmentation variable for pricing strategy:
-- credit card customers have higher avg ticket and less price sensitivity.
-- Boleto customers are more price sensitive — different pricing strategy.
-- ============================================================

SELECT
    payment_type,
    COUNT(*) AS total,
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER(), 2) AS percentual,        -- % of total
    ROUND(AVG(CAST(payment_value AS FLOAT)), 2) AS avg_payment_value,        -- avg ticket
    ROUND(SUM(CAST(payment_value AS FLOAT)), 2) AS total_revenue             -- total revenue
FROM olist_db.raw.order_payments
GROUP BY payment_type
ORDER BY total DESC;

-- FINDINGS:
-- credit_card: 73.92% of payments, highest avg ticket R$ 163.32
-- boleto: 19.04%, lower avg ticket R$ 145.03 - price sensitive customers
-- voucher: avg ticket R$ 65.70 - likely promotional, impacts margin analysis
-- not_defined: 3 records - remove in silver layer
-- action: use payment_type as segmentation variable in pricing analysis

-- ============================================================
-- STEP 14: REVENUE BY CATEGORY
-- ============================================================
-- Identifies top revenue categories and pricing patterns.
-- Uses LEFT JOIN to include order_items without matching products.
-- COUNT(DISTINCT order_id) counts unique orders to avoid
-- double-counting orders with multiple items.
-- This analysis drives pricing prioritization — focus on
-- high-revenue categories with high price dispersion.
-- ============================================================

SELECT
    p.product_category_name,
    COUNT(DISTINCT oi.order_id) AS total_orders,                      -- unique orders per category
    COUNT(oi.order_item_id) AS total_items,                           -- total items sold
    ROUND(AVG(CAST(oi.price AS FLOAT)), 2) AS avg_price,              -- avg price
    ROUND(MIN(CAST(oi.price AS FLOAT)), 2) AS min_price,              -- lowest price
    ROUND(MAX(CAST(oi.price AS FLOAT)), 2) AS max_price,              -- highest price
    ROUND(SUM(CAST(oi.price AS FLOAT)), 2) AS total_revenue,          -- total revenue
    ROUND(AVG(CAST(oi.freight_value AS FLOAT)), 2) AS avg_freight     -- avg freight cost
FROM olist_db.raw.order_items oi
LEFT JOIN olist_db.raw.products p                                     -- brings product category
    ON oi.product_id = p.product_id
GROUP BY p.product_category_name
ORDER BY total_revenue DESC
LIMIT 20;

-- FINDINGS:
-- top revenue category: beleza_saude R$ 1.258.681
-- highest avg ticket: pcs R$ 1.098 - low volume, high value
-- high freight categories: pcs R$ 48, moveis_escritorio R$ 40
-- suspicious min prices: beleza_saude R$ 1.20 - potential underpricing
-- high price dispersion in utilidades_domesticas: R$ 3.06 to R$ 6.735
-- action: analyze price outliers by category in step 22
-- action: include freight in margin calculation - impacts heavily in pcs and moveis

-- ============================================================
-- STEP 15: FREIGHT VS PRICE RATIO
-- ============================================================
-- Calculates freight cost as a percentage of product price.
-- High ratio categories have reduced effective margin —
-- the freight cost consumes a large portion of the selling price.
-- NULLIF(avg_price, 0) prevents division by zero errors
-- when avg_price equals zero.
-- Categories above 25% ratio are flagged for pricing review.
-- ============================================================

SELECT
    p.product_category_name,
    COUNT(oi.order_item_id) AS total_items,
    ROUND(AVG(CAST(oi.price AS FLOAT)), 2) AS avg_price,
    ROUND(AVG(CAST(oi.freight_value AS FLOAT)), 2) AS avg_freight,
    ROUND(AVG(CAST(oi.freight_value AS FLOAT)) /
          NULLIF(AVG(CAST(oi.price AS FLOAT)), 0) * 100, 2) AS freight_price_ratio_pct  -- freight as % of price
FROM olist_db.raw.order_items oi
LEFT JOIN olist_db.raw.products p
    ON oi.product_id = p.product_id
GROUP BY p.product_category_name
ORDER BY freight_price_ratio_pct DESC
LIMIT 20;

-- FINDINGS:
-- casa_conforto_2: freight ratio 53.97% - freight exceeds half the product price
-- flores: 44.04% - high freight vs low price, likely negative margin
-- moveis and eletronicos: high ratio due to weight and dimensions
-- categories with ratio above 30% are candidates for price adjustment
-- action: include freight in margin calculation for all categories
-- action: flag categories with freight ratio above 25% in pricing recommendations

-- ============================================================
-- STEP 16: REFERENTIAL INTEGRITY
-- ============================================================
-- Validates that all foreign key relationships are consistent.
-- Uses LEFT JOIN + WHERE right_table.id IS NULL pattern to find
-- orphan records — rows that reference a non-existent parent.
-- Orphan records would cause data loss in INNER JOINs and
-- distort aggregated metrics in the MARTS layer.
-- Expected result: 0 orphans in all relationships.
-- ============================================================

SELECT 'order_items -> orders' AS relacionamento,
    COUNT(*) AS registros_orfaos                                      -- orphan count
FROM olist_db.raw.order_items oi
LEFT JOIN olist_db.raw.orders o ON oi.order_id = o.order_id
WHERE o.order_id IS NULL                                              -- null = no match found

UNION ALL

SELECT 'order_items -> products',
    COUNT(*)
FROM olist_db.raw.order_items oi
LEFT JOIN olist_db.raw.products p ON oi.product_id = p.product_id
WHERE p.product_id IS NULL

UNION ALL

SELECT 'order_items -> sellers',
    COUNT(*)
FROM olist_db.raw.order_items oi
LEFT JOIN olist_db.raw.sellers s ON oi.seller_id = s.seller_id
WHERE s.seller_id IS NULL

UNION ALL

SELECT 'order_payments -> orders',
    COUNT(*)
FROM olist_db.raw.order_payments op
LEFT JOIN olist_db.raw.orders o ON op.order_id = o.order_id
WHERE o.order_id IS NULL

UNION ALL

SELECT 'order_reviews -> orders',
    COUNT(*)
FROM olist_db.raw.order_reviews ore
LEFT JOIN olist_db.raw.orders o ON ore.order_id = o.order_id
WHERE o.order_id IS NULL

UNION ALL

SELECT 'orders -> customers',
    COUNT(*)
FROM olist_db.raw.orders o
LEFT JOIN olist_db.raw.customers c ON o.customer_id = c.customer_id
WHERE c.customer_id IS NULL;

-- FINDINGS:
-- order_items -> orders: 0 orphans
-- order_items -> products: 0 orphans
-- order_items -> sellers: 0 orphans
-- order_payments -> orders: 0 orphans
-- order_reviews -> orders: 0 orphans
-- orders -> customers: 0 orphans
-- referential integrity: 100% consistent
-- all relationships are valid and ready for star schema modeling

-- ============================================================
-- STEP 17: DATE RANGE VALIDATION
-- ============================================================
-- Validates chronological consistency of order timestamps.
-- Three checks performed:
-- 1. future_dates: purchase dates after current timestamp = invalid
-- 2. delivered_before_purchase: delivery before purchase = impossible
-- 3. approved_before_purchase: approval before purchase = impossible
-- CAST AS TIMESTAMP converts VARCHAR dates for comparison.
-- CURRENT_TIMESTAMP() returns the current Snowflake server time.
-- ============================================================

SELECT
    MIN(CAST(order_purchase_timestamp AS TIMESTAMP)) AS first_order,   -- earliest order date
    MAX(CAST(order_purchase_timestamp AS TIMESTAMP)) AS last_order,    -- latest order date
    COUNT(CASE WHEN CAST(order_purchase_timestamp AS TIMESTAMP) > CURRENT_TIMESTAMP()
          THEN 1 END) AS future_dates,                                  -- invalid future dates
    COUNT(CASE WHEN CAST(order_delivered_customer_date AS TIMESTAMP) 
               CAST(order_purchase_timestamp AS TIMESTAMP)
          THEN 1 END) AS delivered_before_purchase,                     -- logically impossible
    COUNT(CASE WHEN CAST(order_approved_at AS TIMESTAMP) 
               CAST(order_purchase_timestamp AS TIMESTAMP)
          THEN 1 END) AS approved_before_purchase                       -- logically impossible
FROM olist_db.raw.orders;

-- FINDINGS:
-- date range: 2016-09-04 to 2018-10-17 (2 years of data)
-- zero future dates - no invalid timestamps
-- zero delivered before purchase - logical consistency confirmed
-- zero approved before purchase - chronological order valid
-- date range sufficient for seasonality and price trend analysis

-- ============================================================
-- STEP 18: GEOLOCATION VALIDATION
-- ============================================================
-- Validates geographic coordinates against Brazil's boundaries.
-- Brazil geographic limits:
--   Latitude:  -33.75 (south) to +5.27 (north)
--   Longitude: -73.98 (west)  to -34.79 (east)
-- Coordinates outside these bounds are invalid and will be
-- removed in the STAGING layer to avoid map distortion.
-- All 27 Brazilian states are validated against a whitelist.
-- ============================================================

SELECT
    COUNT(*) AS total,
    COUNT(DISTINCT geolocation_state) AS total_states,                 -- should be 27
    COUNT(DISTINCT geolocation_city) AS total_cities,                  -- unique cities
    SUM(CASE WHEN CAST(geolocation_lat AS FLOAT) > 5.27
             OR CAST(geolocation_lat AS FLOAT) < -33.75
             THEN 1 END) AS invalid_lat,                               -- outside Brazil latitude bounds
    SUM(CASE WHEN CAST(geolocation_lng AS FLOAT) > -34.79
             OR CAST(geolocation_lng AS FLOAT) < -73.98
             THEN 1 END) AS invalid_lng,                               -- outside Brazil longitude bounds
    SUM(CASE WHEN geolocation_state NOT IN (
        'AC','AL','AM','AP','BA','CE','DF','ES','GO',
        'MA','MG','MS','MT','PA','PB','PE','PI','PR',
        'RJ','RN','RO','RR','RS','SC','SE','SP','TO')
        THEN 1 END) AS invalid_states                                  -- state codes not in Brazil list
FROM olist_db.raw.geolocation;

-- ============================================================
-- STEP 19: REVIEW SCORE DISTRIBUTION
-- ============================================================
-- Analyzes satisfaction score distribution and correlates
-- with average price and freight per score level.
-- Key pricing intelligence insight: if score 1 has highest
-- avg price, expensive products generate more dissatisfaction.
-- Window function OVER() calculates grand total for percentual.
-- LEFT JOIN brings price/freight data from order_items.
-- ============================================================

SELECT
    review_score,
    COUNT(*) AS total,
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER(), 2) AS percentual,   -- % of total reviews
    ROUND(AVG(CAST(oi.price AS FLOAT)), 2) AS avg_price,                -- avg price per score
    ROUND(AVG(CAST(oi.freight_value AS FLOAT)), 2) AS avg_freight       -- avg freight per score
FROM olist_db.raw.order_reviews ore
LEFT JOIN olist_db.raw.order_items oi                                   -- brings price and freight
    ON ore.order_id = oi.order_id
GROUP BY review_score
ORDER BY review_score DESC;

-- FINDINGS:
-- 56.21% of reviews scored 5 stars - positive overall satisfaction
-- score 1 has highest avg price R$ 127.35 - expensive products generate more dissatisfaction
-- score 3 has lowest avg price R$ 110.06 - mid-range products with fair pricing
-- freight slightly higher in low scores - freight impacts customer satisfaction
-- action: include review_score as variable in pricing recommendation model
-- action: flag high price + low review score products for pricing review

-- ============================================================
-- STEP 20: TOP SELLERS ANALYSIS
-- ============================================================
-- Identifies top revenue sellers and their pricing strategies.
-- SUM(SUM(...)) OVER() is a nested window function:
--   inner SUM: total revenue per seller (from GROUP BY)
--   outer SUM with OVER(): grand total across all sellers
-- This pattern calculates revenue share % in a single query.
-- ============================================================

SELECT
    s.seller_id,
    s.seller_city,
    s.seller_state,
    COUNT(DISTINCT oi.order_id) AS total_orders,                       -- unique orders per seller
    COUNT(oi.order_item_id) AS total_items,                            -- total items sold
    ROUND(SUM(CAST(oi.price AS FLOAT)), 2) AS total_revenue,           -- total revenue
    ROUND(AVG(CAST(oi.price AS FLOAT)), 2) AS avg_price,               -- avg ticket
    ROUND(SUM(CAST(oi.price AS FLOAT)) * 100.0 /
          SUM(SUM(CAST(oi.price AS FLOAT))) OVER(), 2) AS revenue_share_pct  -- % of total revenue
FROM olist_db.raw.sellers s
LEFT JOIN olist_db.raw.order_items oi
    ON s.seller_id = oi.seller_id
GROUP BY s.seller_id, s.seller_city, s.seller_state
ORDER BY total_revenue DESC
LIMIT 20;

-- FINDINGS:
-- top seller: guariba/SP with R$ 229.472 revenue
-- highest avg ticket: lauro de freitas/BA R$ 543 - premium pricing strategy
-- heavy concentration in Sao Paulo state
-- top 20 sellers represent ~18% of total revenue
-- action: analyze pricing strategy by seller concentration in silver layer

-- ============================================================
-- STEP 21: PRODUCTS WITHOUT CATEGORY
-- ============================================================
-- Quantifies the revenue impact of uncategorized products.
-- Products without category are excluded from category-level
-- pricing analysis, representing a risk of revenue blind spots.
-- Conditional Aggregation used to calculate metrics for both
-- null and non-null category groups in a single query.
-- ============================================================

SELECT
    COUNT(*) AS total_products,
    SUM(CASE WHEN product_category_name IS NULL
        THEN 1 ELSE 0 END) AS no_category,                             -- items without category
    ROUND(SUM(CASE WHEN product_category_name IS NULL
        THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 2) AS no_category_pct, -- % without category
    ROUND(AVG(CASE WHEN product_category_name IS NULL
        THEN CAST(oi.price AS FLOAT) END), 2) AS avg_price_no_category,    -- avg price without category
    ROUND(AVG(CASE WHEN product_category_name IS NOT NULL
        THEN CAST(oi.price AS FLOAT) END), 2) AS avg_price_with_category,  -- avg price with category
    SUM(CASE WHEN product_category_name IS NULL
        THEN 1 ELSE 0 END) AS total_items_no_category,                 -- total items impacted
    ROUND(SUM(CASE WHEN product_category_name IS NULL
        THEN CAST(oi.price AS FLOAT) ELSE 0 END), 2) AS revenue_no_category  -- revenue at risk
FROM olist_db.raw.products p
LEFT JOIN olist_db.raw.order_items oi
    ON p.product_id = oi.product_id;

-- FINDINGS:
-- 1.603 items without category (1.42%) - small but relevant
-- R$ 179.535 revenue at risk of exclusion from category analysis
-- avg price without category R$ 112 vs R$ 120.78 with category
-- action: assign 'uncategorized' to null categories in silver layer
-- action: investigate products without category for potential recategorization

-- ============================================================
-- STEP 22: PRICE OUTLIERS BY CATEGORY
-- ============================================================
-- Detects products priced outside the normal range per category.
-- Uses CTE (Common Table Expression) with Window Functions to
-- calculate avg and stddev per category at row level first,
-- then aggregates in the outer query.
-- This two-step approach is required because Snowflake does not
-- allow window functions inside aggregate functions directly.
-- Outlier bounds: avg +/- 2 standard deviations (95% rule).
-- Products above upper_bound are candidates for price reduction.
-- Products below lower_bound are candidates for price increase.
-- Note: lower_bound is negative for most categories because
-- price distribution is right-skewed — IQR method applied in
-- STAGING layer will provide more robust outlier detection.
-- ============================================================

WITH category_stats AS (
    SELECT
        p.product_category_name,
        oi.order_item_id,
        CAST(oi.price AS FLOAT) AS price,
        AVG(CAST(oi.price AS FLOAT)) OVER(PARTITION BY p.product_category_name) AS avg_price,    -- category avg
        STDDEV(CAST(oi.price AS FLOAT)) OVER(PARTITION BY p.product_category_name) AS stddev_price -- category stddev
    FROM olist_db.raw.order_items oi
    LEFT JOIN olist_db.raw.products p
        ON oi.product_id = p.product_id
)
SELECT
    product_category_name,
    COUNT(order_item_id) AS total_items,
    ROUND(AVG(price), 2) AS avg_price,
    ROUND(AVG(stddev_price), 2) AS stddev_price,
    ROUND(MIN(price), 2) AS min_price,
    ROUND(MAX(price), 2) AS max_price,
    ROUND(AVG(price) - 2 * AVG(stddev_price), 2) AS lower_bound,      -- lower outlier threshold
    ROUND(AVG(price) + 2 * AVG(stddev_price), 2) AS upper_bound,      -- upper outlier threshold
    SUM(CASE WHEN price > avg_price + 2 * stddev_price THEN 1 ELSE 0 END) AS outliers_above,  -- overpriced
    SUM(CASE WHEN price < avg_price - 2 * stddev_price THEN 1 ELSE 0 END) AS outliers_below   -- underpriced
FROM category_stats
GROUP BY product_category_name
ORDER BY outliers_above DESC
LIMIT 20;

-- FINDINGS:
-- beleza_saude: 395 overpriced outliers - highest concentration
-- moveis_decoracao: 291 outliers - high price dispersion
-- relogios_presentes: avg R$ 201, upper bound R$ 714 - premium category
-- all lower bounds are negative - no underpriced outliers detected with 2-stddev rule
-- action: apply IQR method in silver layer for better outlier detection
-- action: flag outliers_above products for pricing review in marts layer

-- ============================================================
-- DATA PROFILING SUMMARY
-- PROJECT: Olist Pricing Intelligence
-- AUTHOR: Gisele CP
-- DATE: 2026-06-06
-- ============================================================

-- DATASET OVERVIEW
-- customers:            99.441 records
-- geolocation:       1.000.163 records
-- order_items:         112.650 records
-- order_payments:      103.886 records
-- order_reviews:        99.224 records
-- orders:               99.441 records
-- products:             32.951 records
-- sellers:               3.095 records
-- category_translation:     71 records

-- NULL ANALYSIS
-- order_items:    zero nulls - clean for pricing analysis
-- customers:      zero nulls - clean
-- geolocation:    zero nulls - clean
-- order_payments: zero nulls - clean
-- sellers:        zero nulls - clean
-- orders:         2.965 nulls in delivered_date - expected, undelivered orders
-- order_reviews:  87.656 nulls in comment_title, 58.247 in comment_message - expected
-- products:       610 nulls in category_name, 2 nulls in dimensions

-- DUPLICATE ANALYSIS
-- customers, orders, products, sellers: zero duplicates
-- all primary keys unique and valid

-- PRICE ANALYSIS
-- price range: R$ 0.85 to R$ 6.735
-- price avg: R$ 120.65, stddev: R$ 183.63 - high dispersion
-- freight range: R$ 0 to R$ 409.68, avg: R$ 19.99
-- zero negative or zero prices

-- ORDER STATUS
-- 97.02% delivered, 0.63% canceled
-- action: filter delivered orders for pricing analysis

-- PAYMENT TYPES
-- credit card: 73.92%, avg ticket R$ 163.32
-- boleto: 19.04%, avg ticket R$ 145.03
-- voucher: 5.56%, avg ticket R$ 65.70

-- TOP CATEGORIES BY REVENUE
-- 1. beleza_saude:       R$ 1.258.681
-- 2. relogios_presentes: R$ 1.205.005
-- 3. cama_mesa_banho:    R$ 1.036.988

-- FREIGHT VS PRICE RATIO
-- casa_conforto_2: 53.97% - critical
-- flores: 44.04% - critical
-- action: flag categories with ratio above 25%

-- REFERENTIAL INTEGRITY
-- all relationships 100% consistent - zero orphan records

-- DATE VALIDATION
-- date range: 2016-09-04 to 2018-10-17
-- zero invalid or future dates

-- GEOLOCATION VALIDATION
-- 27 states - full national coverage
-- 31 invalid latitudes, 37 invalid longitudes
-- action: remove invalid coordinates in silver layer

-- REVIEW SCORE
-- 56.21% score 5 stars
-- score 1 has highest avg price R$ 127.35
-- action: include review score in pricing model

-- TOP SELLERS
-- top seller: guariba/SP R$ 229.472
-- heavy concentration in Sao Paulo state

-- PRODUCTS WITHOUT CATEGORY
-- 1.603 items (1.42%) without category
-- R$ 179.535 revenue at risk
-- action: assign uncategorized in silver layer

-- PRICE OUTLIERS
-- beleza_saude: 395 overpriced outliers
-- moveis_decoracao: 291 outliers
-- all lower bounds negative - apply IQR method in silver layer

-- SILVER LAYER ACTION ITEMS
-- 1. filter order_status = delivered
-- 2. cast all numeric fields from VARCHAR
-- 3. assign uncategorized to null categories
-- 4. remove invalid geolocation coordinates
-- 5. treat null review comments as no comment
-- 6. apply IQR method for outlier detection
-- 7. calculate freight ratio per category
-- 8. flag products with review score 1 and high price