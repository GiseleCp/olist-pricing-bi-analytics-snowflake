-- ============================================================
-- PROJECT: Olist Pricing Intelligence
-- FILE: 06_gold_modelagem.sql
-- DESCRIPTION: Star Schema modeling in the MARTS layer.
--              Creates fact and dimension tables for BI consumption
--              and pricing decision support.
--              This is the Gold layer of the Medallion Architecture
--              — data is aggregated, enriched with business metrics
--              and optimized for dashboard and API consumption.
--              Prerequisites:
--              - 05_silver_etl.sql must have been executed
-- AUTHOR: Gisele CP
-- DATE: 2026-06-06
-- ============================================================

-- STAR SCHEMA OVERVIEW
-- A Star Schema organizes data into one central FACT table
-- surrounded by DIMENSION tables. This model is optimized for
-- analytical queries and BI tools like Power BI and Looker.
--
-- FACT TABLE (measures — what happened):
--   fact_orders -> one row per order item with all metrics
--
-- DIMENSION TABLES (context — who, what, where, when):
--   dim_customers  -> customer segmentation and RFM scores
--   dim_products   -> product details with pricing flags
--   dim_sellers    -> seller performance metrics
--   dim_payments   -> payment aggregates per order
--   dim_date       -> date dimension for time intelligence
--
-- DECISION CENTRIC DESIGN:
-- Every table includes business flags and recommendations
-- that directly support pricing decisions:
--   - freight_risk_flag: identifies margin erosion by freight
--   - price_segment: classifies products by price range
--   - rfm_segment: classifies customers by purchase behavior
--   - seller_tier: classifies sellers by revenue performance
--   - delivery_status: on_time vs late for SLA monitoring

-- ============================================================
-- CONTEXT SETUP
-- ============================================================

USE WAREHOUSE olist_wh;   -- compute layer for modeling
USE DATABASE olist_db;    -- project database
USE SCHEMA marts;         -- target schema for business-ready tables

-- ============================================================
-- DIMENSION 1: DIM_DATE
-- ============================================================
-- Date dimension for time intelligence analysis.
-- Enables seasonality analysis, year-over-year comparisons
-- and monthly/quarterly pricing trend identification.
-- Generated from the orders date range: 2016-09-04 to 2018-10-17.
-- Uses Snowflake GENERATOR function to create a date sequence.
-- ============================================================

CREATE OR REPLACE TABLE olist_db.marts.dim_date AS
WITH date_spine AS (
    SELECT
        DATEADD('day', SEQ4(), '2016-09-01'::DATE) AS date_day   -- generates one row per day
    FROM TABLE(GENERATOR(ROWCOUNT => 800))                         -- 800 days covers full dataset range
)
SELECT
    date_day AS date_id,                                           -- primary key — the date itself
    DATE_PART('year', date_day) AS year,                           -- year number
    DATE_PART('month', date_day) AS month_number,                  -- month number 1-12
    MONTHNAME(date_day) AS month_name,                             -- month name (Jan, Feb...)
    DATE_PART('quarter', date_day) AS quarter,                     -- quarter 1-4
    DATE_PART('week', date_day) AS week_number,                    -- week number 1-52
    DATE_PART('dayofweek', date_day) AS day_of_week,               -- day of week 0=Sunday
    DAYNAME(date_day) AS day_name,                                 -- day name (Mon, Tue...)
    CASE
        WHEN DATE_PART('month', date_day) IN (11, 12) THEN 'high_season'   -- Nov-Dec: Black Friday + Christmas
        WHEN DATE_PART('month', date_day) IN (1, 2) THEN 'post_season'     -- Jan-Feb: post holiday slowdown
        ELSE 'regular_season'                                               -- rest of year
    END AS season_flag,                                            -- pricing season classification
    CASE
        WHEN DATE_PART('dayofweek', date_day) IN (0, 6) THEN TRUE
        ELSE FALSE
    END AS is_weekend                                              -- weekend flag for delivery analysis
FROM date_spine;

-- ============================================================
-- DIMENSION 2: DIM_CUSTOMERS
-- ============================================================
-- Customer dimension enriched with RFM scores.
-- RFM (Recency, Frequency, Monetary) is the standard framework
-- for customer segmentation in pricing strategy.
--
-- RECENCY:   how recently did the customer buy?
--            Recent customers are more likely to buy again.
-- FREQUENCY: how many orders did the customer place?
--            Frequent customers are less price sensitive.
-- MONETARY:  how much did the customer spend in total?
--            High-value customers deserve premium pricing strategy.
--
-- RFM scores are calculated on a 1-3 scale:
--   3 = best (most recent / most frequent / highest spend)
--   1 = worst
-- Combined RFM score ranges from 3 (worst) to 9 (best).
-- ============================================================

CREATE OR REPLACE TABLE olist_db.marts.dim_customers AS
WITH customer_orders AS (
    SELECT
        c.customer_unique_id,                                      -- true customer identifier
        c.customer_id,                                             -- transaction customer id
        c.customer_city,
        c.customer_state,
        c.customer_zip_code_prefix,
        COUNT(DISTINCT o.order_id) AS total_orders,                -- frequency metric
        SUM(oi.price + oi.freight_value) AS total_spent,           -- monetary metric
        MAX(o.order_purchase_timestamp) AS last_order_date,        -- recency metric
        DATEDIFF('day',
            MAX(o.order_purchase_timestamp),
            '2018-10-17'::TIMESTAMP) AS days_since_last_order,     -- recency in days
        ROUND(AVG(oi.price), 2) AS avg_order_value,                -- avg ticket
        ROUND(AVG(oi.freight_value), 2) AS avg_freight_paid        -- avg freight paid
    FROM olist_db.staging.customers c
    LEFT JOIN olist_db.staging.orders o
        ON c.customer_id = o.customer_id
    LEFT JOIN olist_db.staging.order_items oi
        ON o.order_id = oi.order_id
    GROUP BY
        c.customer_unique_id,
        c.customer_id,
        c.customer_city,
        c.customer_state,
        c.customer_zip_code_prefix
),
rfm_scores AS (
    SELECT
        *,
        NTILE(3) OVER (ORDER BY days_since_last_order ASC) AS recency_score,   -- 3=most recent
        NTILE(3) OVER (ORDER BY total_orders DESC) AS frequency_score,          -- 3=most frequent
        NTILE(3) OVER (ORDER BY total_spent DESC) AS monetary_score             -- 3=highest spend
    FROM customer_orders
)
SELECT
    customer_unique_id,
    customer_id,
    customer_city,
    customer_state,
    customer_zip_code_prefix,
    total_orders,
    ROUND(total_spent, 2) AS total_spent,
    last_order_date,
    days_since_last_order,
    avg_order_value,
    avg_freight_paid,
    recency_score,                                                  -- 1-3 recency score
    frequency_score,                                                -- 1-3 frequency score
    monetary_score,                                                 -- 1-3 monetary score
    recency_score + frequency_score + monetary_score AS rfm_score,  -- combined 3-9 score
    CASE
        WHEN recency_score + frequency_score + monetary_score >= 8 THEN 'champions'        -- best customers
        WHEN recency_score + frequency_score + monetary_score >= 6 THEN 'loyal'            -- regular buyers
        WHEN recency_score + frequency_score + monetary_score >= 4 THEN 'potential'        -- growth opportunity
        ELSE 'at_risk'                                                                      -- needs attention
    END AS rfm_segment                                              -- decision: pricing strategy per segment
FROM rfm_scores;

-- ============================================================
-- DIMENSION 3: DIM_PRODUCTS
-- ============================================================
-- Product dimension enriched with pricing intelligence flags.
-- Joins with category_translation for English category names.
-- Includes IQR-based price outlier detection per category —
-- more robust than standard deviation for skewed price data.
-- price_segment classifies products for tiered pricing strategy.
-- ============================================================

CREATE OR REPLACE TABLE olist_db.marts.dim_products AS
WITH product_stats AS (
    SELECT
        p.product_id,
        p.product_category_name,
        ct.product_category_name_english,                          -- English category name for dashboards
        p.product_weight_g,
        p.product_length_cm,
        p.product_height_cm,
        p.product_width_cm,
        p.product_volume_cm3,
        ROUND(AVG(oi.price), 2) AS avg_price,                      -- avg selling price
        ROUND(MIN(oi.price), 2) AS min_price,                      -- lowest price sold
        ROUND(MAX(oi.price), 2) AS max_price,                      -- highest price sold
        ROUND(AVG(oi.freight_value), 2) AS avg_freight,            -- avg freight cost
        ROUND(AVG(oi.freight_ratio_pct), 2) AS avg_freight_ratio,  -- avg freight as % of price
        COUNT(oi.order_item_id) AS total_items_sold,               -- total units sold
        ROUND(SUM(oi.price), 2) AS total_revenue,                  -- total revenue generated
        ROUND(AVG(oi.freight_value) /
              NULLIF(AVG(oi.price), 0) * 100, 2) AS freight_ratio_pct,  -- freight ratio
        PERCENTILE_CONT(0.25) WITHIN GROUP
            (ORDER BY oi.price) AS q1_price,                       -- first quartile for IQR
        PERCENTILE_CONT(0.75) WITHIN GROUP
            (ORDER BY oi.price) AS q3_price                        -- third quartile for IQR
    FROM olist_db.staging.products p
    LEFT JOIN olist_db.staging.order_items oi
        ON p.product_id = oi.product_id
    LEFT JOIN olist_db.staging.category_translation ct
        ON p.product_category_name = ct.product_category_name
    GROUP BY
        p.product_id,
        p.product_category_name,
        ct.product_category_name_english,
        p.product_weight_g,
        p.product_length_cm,
        p.product_height_cm,
        p.product_width_cm,
        p.product_volume_cm3
)
SELECT
    product_id,
    product_category_name,
    COALESCE(product_category_name_english, product_category_name) AS product_category_english,
    product_weight_g,
    product_volume_cm3,
    avg_price,
    min_price,
    max_price,
    avg_freight,
    avg_freight_ratio,
    total_items_sold,
    total_revenue,
    q1_price,
    q3_price,
    ROUND(q3_price - q1_price, 2) AS iqr,                          -- interquartile range
    ROUND(q1_price - 1.5 * (q3_price - q1_price), 2) AS price_lower_bound,  -- IQR lower bound
    ROUND(q3_price + 1.5 * (q3_price - q1_price), 2) AS price_upper_bound,  -- IQR upper bound
    CASE
        WHEN avg_price <= 50 THEN 'budget'                         -- price segment: budget
        WHEN avg_price <= 150 THEN 'mid_range'                     -- price segment: mid range
        WHEN avg_price <= 500 THEN 'premium'                       -- price segment: premium
        ELSE 'luxury'                                               -- price segment: luxury
    END AS price_segment,                                           -- decision: tiered pricing strategy
    CASE
        WHEN freight_ratio_pct > 30 THEN 'critical'                -- freight eroding margin
        WHEN freight_ratio_pct > 20 THEN 'attention'               -- margin under pressure
        ELSE 'ok'                                                   -- acceptable freight ratio
    END AS freight_risk_flag,                                       -- decision: price adjustment needed
    CASE
        WHEN avg_price > q3_price + 1.5 * (q3_price - q1_price) THEN 'overpriced'   -- above IQR upper
        WHEN avg_price < q1_price - 1.5 * (q3_price - q1_price) THEN 'underpriced'  -- below IQR lower
        ELSE 'fair_price'                                                              -- within normal range
    END AS pricing_flag                                             -- decision: pricing review needed
FROM product_stats;

-- ============================================================
-- DIMENSION 4: DIM_SELLERS
-- ============================================================
-- Seller dimension with performance metrics and tier classification.
-- seller_tier enables differentiated pricing strategy per seller:
-- platinum/gold sellers may receive better commercial conditions.
-- avg_review_score correlates seller quality with pricing power.
-- ============================================================

CREATE OR REPLACE TABLE olist_db.marts.dim_sellers AS
WITH seller_metrics AS (
    SELECT
        s.seller_id,
        s.seller_city,
        s.seller_state,
        s.seller_zip_code_prefix,
        COUNT(DISTINCT oi.order_id) AS total_orders,               -- unique orders fulfilled
        COUNT(oi.order_item_id) AS total_items_sold,               -- total units sold
        ROUND(SUM(oi.price), 2) AS total_revenue,                  -- total revenue generated
        ROUND(AVG(oi.price), 2) AS avg_ticket,                     -- average selling price
        ROUND(AVG(oi.freight_value), 2) AS avg_freight,            -- average freight charged
        ROUND(AVG(oi.freight_ratio_pct), 2) AS avg_freight_ratio,  -- avg freight as % of price
        ROUND(AVG(ore.review_score), 2) AS avg_review_score,       -- average customer satisfaction
        COUNT(DISTINCT CASE
            WHEN ore.review_score <= 2 THEN oi.order_id END) AS low_score_orders,  -- orders with bad reviews
        ROUND(SUM(oi.price) * 100.0 /
              SUM(SUM(oi.price)) OVER(), 2) AS revenue_share_pct   -- seller revenue share of total
    FROM olist_db.staging.sellers s
    LEFT JOIN olist_db.staging.order_items oi
        ON s.seller_id = oi.seller_id
    LEFT JOIN olist_db.staging.order_reviews ore
        ON oi.order_id = ore.order_id
    GROUP BY
        s.seller_id,
        s.seller_city,
        s.seller_state,
        s.seller_zip_code_prefix
)
SELECT
    seller_id,
    seller_city,
    seller_state,
    seller_zip_code_prefix,
    total_orders,
    total_items_sold,
    total_revenue,
    avg_ticket,
    avg_freight,
    avg_freight_ratio,
    avg_review_score,
    low_score_orders,
    revenue_share_pct,
    CASE
        WHEN total_revenue >= 100000 THEN 'platinum'               -- top revenue sellers
        WHEN total_revenue >= 50000 THEN 'gold'                    -- high revenue sellers
        WHEN total_revenue >= 10000 THEN 'silver'                  -- mid revenue sellers
        ELSE 'bronze'                                               -- low revenue sellers
    END AS seller_tier,                                             -- decision: commercial conditions per tier
    CASE
        WHEN avg_review_score >= 4.5 THEN 'excellent'              -- high satisfaction
        WHEN avg_review_score >= 3.5 THEN 'good'                   -- acceptable satisfaction
        WHEN avg_review_score >= 2.5 THEN 'regular'                -- below average satisfaction
        ELSE 'poor'                                                  -- low satisfaction — pricing risk
    END AS quality_tier                                             -- decision: seller quality classification
FROM seller_metrics;

-- ============================================================
-- DIMENSION 5: DIM_PAYMENTS
-- ============================================================
-- Payment dimension aggregated at order level.
-- One row per order with payment summary.
-- Enables payment type segmentation in pricing analysis.
-- ============================================================

CREATE OR REPLACE TABLE olist_db.marts.dim_payments AS
SELECT
    order_id,                                                       -- foreign key to fact_orders
    COUNT(payment_sequential) AS total_payments,                    -- number of payment records
    SUM(payment_value) AS total_payment_value,                      -- total amount paid
    MAX(payment_installments) AS max_installments,                  -- max installments used
    MODE(payment_type) AS primary_payment_type,                     -- most used payment type
    SUM(CASE WHEN payment_type = 'credit_card'
        THEN payment_value ELSE 0 END) AS credit_card_value,        -- amount paid by credit card
    SUM(CASE WHEN payment_type = 'boleto'
        THEN payment_value ELSE 0 END) AS boleto_value,             -- amount paid by boleto
    SUM(CASE WHEN payment_type = 'voucher'
        THEN payment_value ELSE 0 END) AS voucher_value,            -- amount paid by voucher
    SUM(CASE WHEN payment_type = 'debit_card'
        THEN payment_value ELSE 0 END) AS debit_card_value          -- amount paid by debit card
FROM olist_db.staging.order_payments
GROUP BY order_id;

-- ============================================================
-- FACT TABLE: FACT_ORDERS
-- ============================================================
-- Central fact table of the Star Schema.
-- One row per order item — the most granular level of analysis.
-- Joins all dimensions to provide full context for each transaction.
-- Contains all measures needed for pricing intelligence:
--   - price, freight, total_value (revenue metrics)
--   - review_score (satisfaction metric)
--   - delivery_days, delivery_status (SLA metrics)
--   - freight_ratio_pct, freight_risk_flag (pricing risk metrics)
-- DECISION CENTRIC: pricing_recommendation field provides
-- direct actionable guidance for each transaction.
-- ============================================================

CREATE OR REPLACE TABLE olist_db.marts.fact_orders AS
SELECT
    oi.order_id,                                                    -- order identifier
    oi.order_item_id,                                               -- item sequence within order
    oi.product_id,                                                  -- foreign key to dim_products
    oi.seller_id,                                                   -- foreign key to dim_sellers
    o.customer_id,                                                  -- foreign key to dim_customers
    o.order_purchase_timestamp::DATE AS order_date,                 -- foreign key to dim_date
    o.order_purchase_timestamp,                                     -- full purchase timestamp
    o.order_delivered_customer_date,                                -- delivery timestamp
    oi.price,                                                       -- item selling price
    oi.freight_value,                                               -- freight cost
    oi.total_item_value,                                            -- price + freight
    oi.freight_ratio_pct,                                           -- freight as % of price
    oi.freight_risk_flag,                                           -- critical / attention / ok
    o.delivery_days,                                                -- actual delivery time
    o.delivery_delay_days,                                          -- delay vs estimated
    o.delivery_status,                                              -- on_time / late / pending
    ore.review_score,                                               -- customer satisfaction 1-5
    p.product_category_name,                                        -- product category Portuguese
    p.product_category_english,                                     -- product category English
    p.price_segment,                                                -- budget/mid/premium/luxury
    p.pricing_flag,                                                 -- overpriced/underpriced/fair
    s.seller_state,                                                 -- seller location state
    s.seller_tier,                                                  -- platinum/gold/silver/bronze
    pay.primary_payment_type,                                       -- main payment method
    pay.max_installments,                                           -- installments used
    DATE_PART('year', o.order_purchase_timestamp) AS order_year,    -- year for time analysis
    DATE_PART('month', o.order_purchase_timestamp) AS order_month,  -- month for seasonality
    DATE_PART('quarter', o.order_purchase_timestamp) AS order_quarter, -- quarter for trend analysis
    CASE
        WHEN oi.freight_risk_flag = 'critical'
             AND ore.review_score <= 2
             THEN 'reduce_price_and_freight'                        -- price too high + bad review + high freight
        WHEN oi.freight_risk_flag = 'critical'
             THEN 'review_freight_strategy'                         -- freight eroding margin
        WHEN p.pricing_flag = 'overpriced'
             AND ore.review_score <= 3
             THEN 'reduce_price'                                    -- overpriced with bad reviews
        WHEN p.pricing_flag = 'underpriced'
             AND ore.review_score >= 4
             THEN 'increase_price'                                  -- underpriced with good reviews
        WHEN ore.review_score = 5
             AND p.pricing_flag = 'fair_price'
             THEN 'maintain_pricing'                                -- optimal pricing confirmed
        ELSE 'monitor'                                              -- standard monitoring
    END AS pricing_recommendation                                   -- DECISION CENTRIC: actionable pricing guidance
FROM olist_db.staging.order_items oi
LEFT JOIN olist_db.staging.orders o
    ON oi.order_id = o.order_id
LEFT JOIN olist_db.marts.dim_products p
    ON oi.product_id = p.product_id
LEFT JOIN olist_db.marts.dim_sellers s
    ON oi.seller_id = s.seller_id
LEFT JOIN olist_db.staging.order_reviews ore
    ON oi.order_id = ore.order_id
LEFT JOIN olist_db.marts.dim_payments pay
    ON oi.order_id = pay.order_id;

-- ============================================================
-- VALIDATION
-- ============================================================
-- Confirms all tables were created in the MARTS schema.
-- Expected tables: dim_date, dim_customers, dim_products,
--                  dim_sellers, dim_payments, fact_orders
-- ============================================================

SHOW TABLES IN SCHEMA olist_db.marts;