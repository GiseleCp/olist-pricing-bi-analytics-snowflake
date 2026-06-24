-- ============================================================
-- PROJECT: Olist Pricing Intelligence
-- FILE: 05_silver_etl.sql
-- DESCRIPTION: ETL transformation from RAW to STAGING layer.
--              Applies all data quality treatments identified
--              in 04_data_profiling.sql.
-- AUTHOR: Gisele CP
-- DATE: 2026-05-25
-- UPDATED: 2026-06-23
-- CHANGES:
--   v1.1 - corrigido cálculo de product_volume_cm3
--   v1.2 - freight_ratio_pct refatorado usando CTE
--   v1.3 - valores dos campos padronizados em inglês
-- ============================================================

USE WAREHOUSE olist_wh;
USE DATABASE olist_db;
USE SCHEMA staging;

-- ============================================================
-- TABELA 1: STAGING.ORDERS
-- ============================================================
-- Fonte: olist_db.raw.orders
-- Tratamentos:
--   - Filtro: apenas order_status = 'delivered'
--   - Cast: timestamps de VARCHAR para TIMESTAMP
--   - Derivado: delivery_days, delivery_delay_days, delivery_status
-- Registros esperados: ~96.478
-- ============================================================

CREATE OR REPLACE TABLE olist_db.staging.orders AS
SELECT
    order_id,
    customer_id,
    order_status,
    CAST(order_purchase_timestamp AS TIMESTAMP) AS order_purchase_timestamp,
    CAST(order_approved_at AS TIMESTAMP) AS order_approved_at,
    CAST(order_delivered_carrier_date AS TIMESTAMP) AS order_delivered_carrier_date,
    CAST(order_delivered_customer_date AS TIMESTAMP) AS order_delivered_customer_date,
    CAST(order_estimated_delivery_date AS TIMESTAMP) AS order_estimated_delivery_date,
    DATEDIFF('day',
        CAST(order_purchase_timestamp AS TIMESTAMP),
        CAST(order_delivered_customer_date AS TIMESTAMP)) AS delivery_days,
    DATEDIFF('day',
        CAST(order_delivered_customer_date AS TIMESTAMP),
        CAST(order_estimated_delivery_date AS TIMESTAMP)) AS delivery_delay_days,
    CASE
        WHEN order_delivered_customer_date <= order_estimated_delivery_date THEN 'on_time'   -- entregue dentro do prazo
        WHEN order_delivered_customer_date > order_estimated_delivery_date  THEN 'late'      -- entregue com atraso
        ELSE 'pending'                                                                        -- ainda não entregue
    END AS delivery_status
FROM olist_db.raw.orders
WHERE order_status = 'delivered'
AND order_purchase_timestamp IS NOT NULL;

-- ============================================================
-- TABELA 2: STAGING.ORDER_ITEMS
-- ============================================================
-- Fonte: olist_db.raw.order_items
-- Tratamentos:
--   - CTE base_items: freight_ratio_pct calculado uma única vez
--   - Cast: price e freight_value para FLOAT
--   - Derivado: total_item_value, freight_ratio_pct, freight_risk_flag
-- Registros esperados: ~112.650
-- ============================================================

CREATE OR REPLACE TABLE olist_db.staging.order_items AS
WITH base_items AS (
    -- calcula freight_ratio_pct uma única vez para reutilização
    SELECT
        order_id,
        order_item_id,
        product_id,
        seller_id,
        shipping_limit_date,
        CAST(price AS FLOAT) AS price,
        CAST(freight_value AS FLOAT) AS freight_value,
        ROUND(
            CAST(freight_value AS FLOAT) /
            NULLIF(CAST(price AS FLOAT), 0) * 100
        , 2) AS freight_ratio_pct
    FROM olist_db.raw.order_items
    WHERE price IS NOT NULL
    AND freight_value IS NOT NULL
)
SELECT
    order_id,
    order_item_id,
    product_id,
    seller_id,
    CAST(shipping_limit_date AS TIMESTAMP) AS shipping_limit_date,
    price,
    freight_value,
    price + freight_value AS total_item_value,                      -- custo total ao cliente
    freight_ratio_pct,                                              -- frete como % do preço
    CASE
        WHEN freight_ratio_pct > 30 THEN 'critical'                 -- frete > 30% do preço
        WHEN freight_ratio_pct > 20 THEN 'attention'                -- frete entre 20-30%
        ELSE 'ok'                                                    -- ratio aceitável
    END AS freight_risk_flag
FROM base_items;

-- ============================================================
-- TABELA 3: STAGING.PRODUCTS
-- ============================================================
-- Fonte: olist_db.raw.products
-- Tratamentos:
--   - COALESCE: 'uncategorized' para category nula (610 nulos)
--   - Cast: campos numéricos de VARCHAR para tipos corretos
--   - Derivado: product_volume_cm3 = comprimento * altura * largura
--     NOTA v1.1: peso removido da fórmula de volume
-- Registros esperados: ~32.951
-- ============================================================

CREATE OR REPLACE TABLE olist_db.staging.products AS
SELECT
    product_id,
    COALESCE(product_category_name, 'uncategorized') AS product_category_name,
    CAST(product_name_lenght AS INT) AS product_name_length,
    CAST(product_description_lenght AS INT) AS product_description_length,
    CAST(product_photos_qty AS INT) AS product_photos_qty,
    COALESCE(CAST(product_weight_g AS FLOAT), 0) AS product_weight_g,
    COALESCE(CAST(product_length_cm AS FLOAT), 0) AS product_length_cm,
    COALESCE(CAST(product_height_cm AS FLOAT), 0) AS product_height_cm,
    COALESCE(CAST(product_width_cm AS FLOAT), 0) AS product_width_cm,
    COALESCE(CAST(product_length_cm AS FLOAT), 0) *
    COALESCE(CAST(product_height_cm AS FLOAT), 0) *
    COALESCE(CAST(product_width_cm AS FLOAT), 0) AS product_volume_cm3  -- volume: comprimento * altura * largura
FROM olist_db.raw.products;

-- ============================================================
-- TABELA 4: STAGING.CUSTOMERS
-- ============================================================
-- Fonte: olist_db.raw.customers
-- Tratamentos:
--   - INITCAP: cidades em Title Case
--   - UPPER: estados em maiúsculo
-- Registros esperados: ~99.441
-- ============================================================

CREATE OR REPLACE TABLE olist_db.staging.customers AS
SELECT
    customer_id,
    customer_unique_id,
    customer_zip_code_prefix,
    INITCAP(customer_city) AS customer_city,
    UPPER(customer_state) AS customer_state
FROM olist_db.raw.customers;

-- ============================================================
-- TABELA 5: STAGING.SELLERS
-- ============================================================
-- Fonte: olist_db.raw.sellers
-- Tratamentos:
--   - INITCAP: cidades em Title Case
--   - UPPER: estados em maiúsculo
-- Registros esperados: ~3.095
-- ============================================================

CREATE OR REPLACE TABLE olist_db.staging.sellers AS
SELECT
    seller_id,
    seller_zip_code_prefix,
    INITCAP(seller_city) AS seller_city,
    UPPER(seller_state) AS seller_state
FROM olist_db.raw.sellers;

-- ============================================================
-- TABELA 6: STAGING.ORDER_PAYMENTS
-- ============================================================
-- Fonte: olist_db.raw.order_payments
-- Tratamentos:
--   - Filtro: remove payment_type = 'not_defined' (3 registros)
--   - Cast: sequential e installments para INT, value para FLOAT
-- Registros esperados: ~103.883
-- ============================================================

CREATE OR REPLACE TABLE olist_db.staging.order_payments AS
SELECT
    order_id,
    CAST(payment_sequential AS INT) AS payment_sequential,
    payment_type,
    CAST(payment_installments AS INT) AS payment_installments,
    CAST(payment_value AS FLOAT) AS payment_value
FROM olist_db.raw.order_payments
WHERE payment_type != 'not_defined';

-- ============================================================
-- TABELA 7: STAGING.ORDER_REVIEWS
-- ============================================================
-- Fonte: olist_db.raw.order_reviews
-- Tratamentos:
--   - Cast: review_score para INT
--   - COALESCE: 'no_title' para títulos nulos (87.656 nulos)
--   - COALESCE: 'no_comment' para mensagens nulas (58.247 nulos)
--   - Cast: datas para TIMESTAMP
-- Registros esperados: ~99.224
-- ============================================================

CREATE OR REPLACE TABLE olist_db.staging.order_reviews AS
SELECT
    review_id,
    order_id,
    CAST(review_score AS INT) AS review_score,
    COALESCE(review_comment_title, 'no_title') AS review_comment_title,
    COALESCE(review_comment_message, 'no_comment') AS review_comment_message,
    CAST(review_creation_date AS TIMESTAMP) AS review_creation_date,
    CAST(review_answer_timestamp AS TIMESTAMP) AS review_answer_timestamp
FROM olist_db.raw.order_reviews;

-- ============================================================
-- TABELA 8: STAGING.GEOLOCATION
-- ============================================================
-- Fonte: olist_db.raw.geolocation
-- Tratamentos:
--   - Filtro: remove coordenadas fora dos limites do Brasil
--     latitude: -33.75 (sul) a +5.27 (norte)
--     longitude: -73.98 (oeste) a -34.79 (leste)
--   - Cast: lat e lng para FLOAT
--   - INITCAP/UPPER: padronização de cidade e estado
-- Registros esperados: ~1.000.121
-- ============================================================

CREATE OR REPLACE TABLE olist_db.staging.geolocation AS
SELECT
    geolocation_zip_code_prefix,
    CAST(geolocation_lat AS FLOAT) AS geolocation_lat,
    CAST(geolocation_lng AS FLOAT) AS geolocation_lng,
    INITCAP(geolocation_city) AS geolocation_city,
    UPPER(geolocation_state) AS geolocation_state
FROM olist_db.raw.geolocation
WHERE CAST(geolocation_lat AS FLOAT) BETWEEN -33.75 AND 5.27
AND CAST(geolocation_lng AS FLOAT) BETWEEN -73.98 AND -34.79;

-- ============================================================
-- TABELA 9: STAGING.CATEGORY_TRANSLATION
-- ============================================================
-- Fonte: olist_db.raw.category_translation
-- Sem tratamentos necessários — 71 registros, zero nulos
-- Registros esperados: 71
-- ============================================================

CREATE OR REPLACE TABLE olist_db.staging.category_translation AS
SELECT
    product_category_name,
    product_category_name_english
FROM olist_db.raw.category_translation;

-- ============================================================
-- VALIDAÇÃO
-- ============================================================

SELECT 'customers' AS tabela, COUNT(*) AS total FROM olist_db.staging.customers
UNION ALL
SELECT 'geolocation', COUNT(*) FROM olist_db.staging.geolocation
UNION ALL
SELECT 'order_items', COUNT(*) FROM olist_db.staging.order_items
UNION ALL
SELECT 'order_payments', COUNT(*) FROM olist_db.staging.order_payments
UNION ALL
SELECT 'order_reviews', COUNT(*) FROM olist_db.staging.order_reviews
UNION ALL
SELECT 'orders', COUNT(*) FROM olist_db.staging.orders
UNION ALL
SELECT 'products', COUNT(*) FROM olist_db.staging.products
UNION ALL
SELECT 'sellers', COUNT(*) FROM olist_db.staging.sellers
UNION ALL
SELECT 'category_translation', COUNT(*) FROM olist_db.staging.category_translation
ORDER BY total DESC;