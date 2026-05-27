-- warehouse é o “motor” que executa consultas
USE WAREHOUSE olist_wh;
-- database é o banco principal do projeto
USE DATABASE olist_db;
-- uma pasta dentro do banco
USE SCHEMA raw;

-- ========================
-- STEP 1: RECORD COUNT
-- ========================
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


-- ========================
-- STEP 2: NULL ANALYSIS - ORDERS_ITEMS
-- ========================
SELECT
    COUNT(*) AS total,
    COUNT(order_id) AS order_id_preenchido,
    COUNT(product_id) AS product_id_preenchido,
    COUNT(price) AS price_preenchido,
    COUNT(freight_value) AS freight_preenchido,
    SUM(CASE WHEN price IS NULL THEN 1 ELSE 0 END) AS price_nulo,
    SUM(CASE WHEN freight_value IS NULL THEN 1 ELSE 0 END) AS freight_nulo
FROM olist_db.raw.order_items;

-- FINDINGS:
-- order_items: 112.650 records, zero nulls
-- price and freight_value: 100% complete
-- clean table, ready for pricing analysis


-- ========================
-- STEP 3: NULL ANALYSIS - CUSTOMERS
-- ========================
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


-- ========================
-- STEP 4: NULL ANALYSIS - GEOLOCATION
-- ========================
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


-- ========================
-- STEP 5: NULL ANALYSIS - ORDER PAYMENTS
-- ========================
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


-- ========================
-- STEP 6: NULL ANALYSIS - ORDER REVIEWS
-- ========================
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


-- ========================
-- STEP 7: NULL ANALYSIS - SELLERS
-- ========================
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


-- ========================
-- STEP 8: NULL ANALYSIS - ORDERS
-- ========================
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


-- ========================
-- STEP 9: NULL ANALYSIS - PRODUCTS
-- ========================
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


-- ========================
-- STEP 10: DUPLICATE ANALYSIS
-- ========================
SELECT 'customers' AS tabela,
    COUNT(*) AS total,
    COUNT(DISTINCT customer_id) AS unique_ids,
    COUNT(*) - COUNT(DISTINCT customer_id) AS duplicatas
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


-- ========================
-- STEP 11: PRICE RANGE ANALYSIS
-- ========================
SELECT
    COUNT(*) AS total,
    MIN(CAST(price AS FLOAT)) AS price_min,
    MAX(CAST(price AS FLOAT)) AS price_max,
    ROUND(AVG(CAST(price AS FLOAT)), 2) AS price_avg,
    ROUND(STDDEV(CAST(price AS FLOAT)), 2) AS price_stddev,
    MIN(CAST(freight_value AS FLOAT)) AS freight_min,
    MAX(CAST(freight_value AS FLOAT)) AS freight_max,
    ROUND(AVG(CAST(freight_value AS FLOAT)), 2) AS freight_avg,
    SUM(CASE WHEN CAST(price AS FLOAT) <= 0 THEN 1 ELSE 0 END) AS price_zero_negativo,
    SUM(CASE WHEN CAST(freight_value AS FLOAT) < 0 THEN 1 ELSE 0 END) AS freight_negativo
FROM olist_db.raw.order_items;

-- FINDINGS:
-- price range: R$ 0.85 to R$ 6.735
-- price avg: R$ 120.65, stddev: 183.63 - high dispersion
-- high stddev indicates pricing analysis must be done by category
-- freight range: R$ 0 to R$ 409.68, avg: R$ 19.99
-- zero negative or zero prices - clean data ready for pricing analysis
-- action: segment pricing analysis by product category in silver layer


-- ========================
-- STEP 12: ORDER STATUS DISTRIBUTION
-- ========================
SELECT
    order_status,
    COUNT(*) AS total,
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER(), 2) AS percentual
FROM olist_db.raw.orders
GROUP BY order_status
ORDER BY total DESC;

-- FINDINGS:
-- 97.02% orders delivered - healthy fulfillment rate
-- 0.63% canceled - low cancellation rate
-- canceled and unavailable orders must be excluded from pricing analysis
-- action: filter order_status = 'delivered' in silver layer for pricing


-- ========================
-- STEP 13: PAYMENT TYPE DISTRIBUTION
-- ========================
SELECT
    payment_type,
    COUNT(*) AS total,
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER(), 2) AS percentual,
    ROUND(AVG(CAST(payment_value AS FLOAT)), 2) AS avg_payment_value,
    ROUND(SUM(CAST(payment_value AS FLOAT)), 2) AS total_revenue
FROM olist_db.raw.order_payments
GROUP BY payment_type
ORDER BY total DESC;

-- FINDINGS:
-- credit_card: 73.92% of payments, highest avg ticket R$ 163.32
-- boleto: 19.04%, lower avg ticket R$ 145.03 - price sensitive customers
-- voucher: avg ticket R$ 65.70 - likely promotional, impacts margin analysis
-- not_defined: 3 records - remove in silver layer
-- action: use payment_type as segmentation variable in pricing analysis


-- ========================
-- STEP 14: REVENUE BY CATEGORY
-- ========================
SELECT
    p.product_category_name,
    COUNT(DISTINCT oi.order_id) AS total_orders,
    COUNT(oi.order_item_id) AS total_items,
    ROUND(AVG(CAST(oi.price AS FLOAT)), 2) AS avg_price,
    ROUND(MIN(CAST(oi.price AS FLOAT)), 2) AS min_price,
    ROUND(MAX(CAST(oi.price AS FLOAT)), 2) AS max_price,
    ROUND(SUM(CAST(oi.price AS FLOAT)), 2) AS total_revenue,
    ROUND(AVG(CAST(oi.freight_value AS FLOAT)), 2) AS avg_freight
FROM olist_db.raw.order_items oi
LEFT JOIN olist_db.raw.products p
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


-- ========================
-- STEP 15: FREIGHT VS PRICE RATIO
-- ========================
SELECT
    p.product_category_name,
    COUNT(oi.order_item_id) AS total_items,
    ROUND(AVG(CAST(oi.price AS FLOAT)), 2) AS avg_price,
    ROUND(AVG(CAST(oi.freight_value AS FLOAT)), 2) AS avg_freight,
    ROUND(AVG(CAST(oi.freight_value AS FLOAT)) / 
          NULLIF(AVG(CAST(oi.price AS FLOAT)), 0) * 100, 2) AS freight_price_ratio_pct
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


-- ========================
-- STEP 16: REFERENTIAL INTEGRITY
-- ========================
SELECT 'order_items -> orders' AS relacionamento,
    COUNT(*) AS registros_orfaos
FROM olist_db.raw.order_items oi
LEFT JOIN olist_db.raw.orders o ON oi.order_id = o.order_id
WHERE o.order_id IS NULL

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


-- ========================
-- STEP 17: DATE RANGE VALIDATION
-- ========================
SELECT
    MIN(CAST(order_purchase_timestamp AS TIMESTAMP)) AS first_order,
    MAX(CAST(order_purchase_timestamp AS TIMESTAMP)) AS last_order,
    COUNT(CASE WHEN CAST(order_purchase_timestamp AS TIMESTAMP) > CURRENT_TIMESTAMP() 
          THEN 1 END) AS future_dates,
    COUNT(CASE WHEN CAST(order_delivered_customer_date AS TIMESTAMP) < 
               CAST(order_purchase_timestamp AS TIMESTAMP) 
          THEN 1 END) AS delivered_before_purchase,
    COUNT(CASE WHEN CAST(order_approved_at AS TIMESTAMP) < 
               CAST(order_purchase_timestamp AS TIMESTAMP) 
          THEN 1 END) AS approved_before_purchase
FROM olist_db.raw.orders;

-- FINDINGS:
-- date range: 2016-09-04 to 2018-10-17 (2 years of data)
-- zero future dates - no invalid timestamps
-- zero delivered before purchase - logical consistency confirmed
-- zero approved before purchase - chronological order valid
-- date range sufficient for seasonality and price trend analysis


-- ========================
-- STEP 18: GEOLOCATION VALIDATION
-- ========================
SELECT
    COUNT(*) AS total,
    COUNT(DISTINCT geolocation_state) AS total_states,
    COUNT(DISTINCT geolocation_city) AS total_cities,
    SUM(CASE WHEN CAST(geolocation_lat AS FLOAT) > 5.27 
             OR CAST(geolocation_lat AS FLOAT) < -33.75 
             THEN 1 END) AS invalid_lat,
    SUM(CASE WHEN CAST(geolocation_lng AS FLOAT) > -34.79 
             OR CAST(geolocation_lng AS FLOAT) < -73.98 
             THEN 1 END) AS invalid_lng,
    SUM(CASE WHEN geolocation_state NOT IN (
        'AC','AL','AM','AP','BA','CE','DF','ES','GO',
        'MA','MG','MS','MT','PA','PB','PE','PI','PR',
        'RJ','RN','RO','RR','RS','SC','SE','SP','TO')
        THEN 1 END) AS invalid_states
FROM olist_db.raw.geolocation;


-- ========================
-- STEP 19: REVIEW SCORE DISTRIBUTION
-- ========================
SELECT
    review_score,
    COUNT(*) AS total,
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER(), 2) AS percentual,
    ROUND(AVG(CAST(oi.price AS FLOAT)), 2) AS avg_price,
    ROUND(AVG(CAST(oi.freight_value AS FLOAT)), 2) AS avg_freight
FROM olist_db.raw.order_reviews ore
LEFT JOIN olist_db.raw.order_items oi
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


-- ========================
-- STEP 20: TOP SELLERS ANALYSIS
-- ========================
SELECT
    s.seller_id,
    s.seller_city,
    s.seller_state,
    COUNT(DISTINCT oi.order_id) AS total_orders,
    COUNT(oi.order_item_id) AS total_items,
    ROUND(SUM(CAST(oi.price AS FLOAT)), 2) AS total_revenue,
    ROUND(AVG(CAST(oi.price AS FLOAT)), 2) AS avg_price,
    ROUND(SUM(CAST(oi.price AS FLOAT)) * 100.0 / 
          SUM(SUM(CAST(oi.price AS FLOAT))) OVER(), 2) AS revenue_share_pct
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


-- ========================
-- STEP 21: PRODUCTS WITHOUT CATEGORY
-- ========================
SELECT
    COUNT(*) AS total_products,
    SUM(CASE WHEN product_category_name IS NULL 
        THEN 1 ELSE 0 END) AS no_category,
    ROUND(SUM(CASE WHEN product_category_name IS NULL 
        THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 2) AS no_category_pct,
    ROUND(AVG(CASE WHEN product_category_name IS NULL 
        THEN CAST(oi.price AS FLOAT) END), 2) AS avg_price_no_category,
    ROUND(AVG(CASE WHEN product_category_name IS NOT NULL 
        THEN CAST(oi.price AS FLOAT) END), 2) AS avg_price_with_category,
    SUM(CASE WHEN product_category_name IS NULL 
        THEN 1 ELSE 0 END) AS total_items_no_category,
    ROUND(SUM(CASE WHEN product_category_name IS NULL 
        THEN CAST(oi.price AS FLOAT) ELSE 0 END), 2) AS revenue_no_category
FROM olist_db.raw.products p
LEFT JOIN olist_db.raw.order_items oi
    ON p.product_id = oi.product_id;

    -- FINDINGS:
-- 1.603 items without category (1.42%) - small but relevant
-- R$ 179.535 revenue at risk of exclusion from category analysis
-- avg price without category R$ 112 vs R$ 120.78 with category
-- action: assign 'uncategorized' to null categories in silver layer
-- action: investigate products without category for potential recategorization


-- ========================
-- STEP 22: PRICE OUTLIERS BY CATEGORY
-- ========================
WITH category_stats AS (
    SELECT
        p.product_category_name,
        oi.order_item_id,
        CAST(oi.price AS FLOAT) AS price,
        AVG(CAST(oi.price AS FLOAT)) OVER(PARTITION BY p.product_category_name) AS avg_price,
        STDDEV(CAST(oi.price AS FLOAT)) OVER(PARTITION BY p.product_category_name) AS stddev_price
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
    ROUND(AVG(price) - 2 * AVG(stddev_price), 2) AS lower_bound,
    ROUND(AVG(price) + 2 * AVG(stddev_price), 2) AS upper_bound,
    SUM(CASE WHEN price > avg_price + 2 * stddev_price THEN 1 ELSE 0 END) AS outliers_above,
    SUM(CASE WHEN price < avg_price - 2 * stddev_price THEN 1 ELSE 0 END) AS outliers_below
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




-- ========================
-- DATA PROFILING SUMMARY
-- PROJECT: Olist Pricing & BI Analytics
-- AUTHOR: Gisele CP
-- DATE: 2026-05-25
-- ========================

-- DATASET OVERVIEW
-- customers:         99.441 records
-- geolocation:    1.000.163 records
-- order_items:      112.650 records
-- order_payments:   103.886 records
-- order_reviews:     99.224 records
-- orders:            99.441 records
-- products:          32.951 records
-- sellers:            3.095 records
-- category_translation: 71 records

-- NULL ANALYSIS
-- order_items:       zero nulls - clean for pricing analysis
-- customers:         zero nulls - clean
-- geolocation:       zero nulls - clean
-- order_payments:    zero nulls - clean
-- sellers:           zero nulls - clean
-- orders:            2.965 nulls in delivered_date - expected, undelivered orders
-- order_reviews:     87.656 nulls in comment_title, 58.247 in comment_message - expected
-- products:          610 nulls in category_name, 2 nulls in dimensions

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
-- 1. beleza_saude:      R$ 1.258.681
-- 2. relogios_presentes: R$ 1.205.005
-- 3. cama_mesa_banho:   R$ 1.036.988

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