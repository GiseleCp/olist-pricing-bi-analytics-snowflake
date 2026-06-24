-- ============================================================
-- PROJECT: Olist Pricing Intelligence
-- FILE: 06_gold_modelagem.sql
-- DESCRIPTION: Modelagem Star Schema na camada MARTS.
--              Cria tabelas fato e dimensão para consumo de BI
--              e suporte a decisões de pricing.
-- AUTHOR: Gisele CP
-- DATE: 2026-06-10
-- UPDATED: 2026-06-23
-- CHANGES:
--   v1.1 - RFM com pesos (R=0.4, F=0.3, M=0.3)
--   v1.2 - métricas financeiras no fact_orders
--   v1.3 - recommended_price adicionado
--   v1.4 - valores dos campos padronizados em inglês
--   v1.5 - CTE reviews_dedup para evitar duplicação na fact
--   v1.6 - filtro total_orders > 0 na dim_customers
--   v1.7 - margin_alert adicionado na fact_orders
-- MELHORIAS FUTURAS:
--   - surrogate keys para SCD Type 2
--   - dim_categories separada com margin_target
--   - estimated_margin real quando COGS disponível
--   - dim_date com range dinâmico
-- ============================================================

USE WAREHOUSE olist_wh;
USE DATABASE olist_db;
USE SCHEMA marts;

-- ============================================================
-- DIMENSÃO 1: DIM_DATE
-- ============================================================
-- Dimensão de data para análise temporal e sazonalidade.
-- NOTA: range fixo de 800 dias cobre o dataset 2016-2018.
-- Se novos dados forem adicionados ao staging, o range
-- deve ser ajustado manualmente ou refatorado para dinâmico.
-- Documentado como melhoria futura.
-- ============================================================

CREATE OR REPLACE TABLE olist_db.marts.dim_date AS
WITH date_spine AS (
    SELECT
        DATEADD('day', SEQ4(), '2016-09-01'::DATE) AS date_day
    FROM TABLE(GENERATOR(ROWCOUNT => 800))                         -- 800 dias cobre 2016-2018
)
SELECT
    date_day AS date_id,
    DATE_PART('year', date_day) AS year,
    DATE_PART('month', date_day) AS month_number,
    MONTHNAME(date_day) AS month_name,
    DATE_PART('quarter', date_day) AS quarter,
    DATE_PART('week', date_day) AS week_number,
    DATE_PART('dayofweek', date_day) AS day_of_week,
    DAYNAME(date_day) AS day_name,
    CASE
        WHEN DATE_PART('month', date_day) IN (11, 12) THEN 'high_season'   -- novembro e dezembro: Black Friday e Natal
        WHEN DATE_PART('month', date_day) IN (1, 2)   THEN 'post_season'   -- janeiro e fevereiro: desaceleração pós-férias
        ELSE 'regular_season'                                               -- restante do ano
    END AS season_flag,
    CASE
        WHEN DATE_PART('dayofweek', date_day) IN (0, 6) THEN TRUE
        ELSE FALSE
    END AS is_weekend
FROM date_spine;

-- ============================================================
-- DIMENSÃO 2: DIM_CUSTOMERS
-- ============================================================
-- Dimensão de clientes com RFM ponderado.
-- R=40%, F=30%, M=30% — pesos refletem importância para pricing.
-- AJUSTE v1.6: filtro total_orders > 0 evita distorção no NTILE
-- Clientes sem pedido tinham days_since_last_order = NULL,
-- o que distorcia a distribuição dos scores RFM.
-- ============================================================

CREATE OR REPLACE TABLE olist_db.marts.dim_customers AS
WITH max_date AS (
    -- data de referência dinâmica para cálculo de recência
    -- evita hardcoding de datas — se novos dados entrarem, recência se atualiza
    SELECT MAX(order_purchase_timestamp) AS reference_date
    FROM olist_db.staging.orders
),
customer_orders AS (
    SELECT
        c.customer_unique_id,
        c.customer_id,
        c.customer_city,
        c.customer_state,
        c.customer_zip_code_prefix,
        COUNT(DISTINCT o.order_id) AS total_orders,                -- métrica de frequência
        SUM(oi.price + oi.freight_value) AS total_spent,           -- métrica monetária
        MAX(o.order_purchase_timestamp) AS last_order_date,        -- data da última compra
        DATEDIFF('day',
            MAX(o.order_purchase_timestamp),
            (SELECT reference_date FROM max_date)) AS days_since_last_order, -- recência dinâmica
        ROUND(AVG(oi.price), 2) AS avg_order_value,
        ROUND(AVG(oi.freight_value), 2) AS avg_freight_paid
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
    HAVING COUNT(DISTINCT o.order_id) > 0                          -- v1.6: exclui clientes sem pedido
),
rfm_scores AS (
    SELECT
        *,
        NTILE(3) OVER (ORDER BY days_since_last_order ASC) AS recency_score,   -- 3=mais recente
        NTILE(3) OVER (ORDER BY total_orders DESC) AS frequency_score,          -- 3=mais frequente
        NTILE(3) OVER (ORDER BY total_spent DESC) AS monetary_score             -- 3=maior gasto
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
    recency_score,
    frequency_score,
    monetary_score,
    recency_score + frequency_score + monetary_score AS rfm_score,
    ROUND(
        (recency_score * 0.4) +
        (frequency_score * 0.3) +
        (monetary_score * 0.3)
    , 2) AS rfm_weighted_score,                                    -- score ponderado 1.0-3.0
    CASE
        WHEN (recency_score * 0.4) + (frequency_score * 0.3) + (monetary_score * 0.3) >= 2.5
            THEN 'champions'                                        -- melhores clientes
        WHEN (recency_score * 0.4) + (frequency_score * 0.3) + (monetary_score * 0.3) >= 2.0
            THEN 'loyal'                                            -- compradores regulares
        WHEN (recency_score * 0.4) + (frequency_score * 0.3) + (monetary_score * 0.3) >= 1.5
            THEN 'potential'                                        -- oportunidade de crescimento
        ELSE 'at_risk'                                              -- necessita atenção
    END AS rfm_segment
FROM rfm_scores;

-- ============================================================
-- DIMENSÃO 3: DIM_PRODUCTS
-- ============================================================
-- Dimensão de produtos com detecção de outliers via IQR.
-- price_segment classifica produtos para estratégia de pricing em tiers.
-- pricing_flag identifica produtos fora do range normal de preço.
-- NOTA: dim_categories separada documentada como melhoria futura.
-- ============================================================

CREATE OR REPLACE TABLE olist_db.marts.dim_products AS
WITH product_stats AS (
    SELECT
        p.product_id,
        p.product_category_name,
        ct.product_category_name_english,
        p.product_weight_g,
        p.product_length_cm,
        p.product_height_cm,
        p.product_width_cm,
        p.product_volume_cm3,
        ROUND(AVG(oi.price), 2) AS avg_price,
        ROUND(MIN(oi.price), 2) AS min_price,
        ROUND(MAX(oi.price), 2) AS max_price,
        ROUND(AVG(oi.freight_value), 2) AS avg_freight,
        ROUND(AVG(oi.freight_ratio_pct), 2) AS avg_freight_ratio,
        COUNT(oi.order_item_id) AS total_items_sold,
        ROUND(SUM(oi.price), 2) AS total_revenue,
        ROUND(AVG(oi.freight_value) /
              NULLIF(AVG(oi.price), 0) * 100, 2) AS freight_ratio_pct,
        PERCENTILE_CONT(0.25) WITHIN GROUP
            (ORDER BY oi.price) AS q1_price,
        PERCENTILE_CONT(0.75) WITHIN GROUP
            (ORDER BY oi.price) AS q3_price
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
    ROUND(q3_price - q1_price, 2) AS iqr,
    ROUND(q1_price - 1.5 * (q3_price - q1_price), 2) AS price_lower_bound,
    ROUND(q3_price + 1.5 * (q3_price - q1_price), 2) AS price_upper_bound,
    CASE
        WHEN avg_price <= 50  THEN 'budget'
        WHEN avg_price <= 150 THEN 'mid_range'
        WHEN avg_price <= 500 THEN 'premium'
        ELSE 'luxury'
    END AS price_segment,
    CASE
        WHEN freight_ratio_pct > 30 THEN 'critical'
        WHEN freight_ratio_pct > 20 THEN 'attention'
        ELSE 'ok'
    END AS freight_risk_flag,
    CASE
        WHEN avg_price > q3_price + 1.5 * (q3_price - q1_price) THEN 'overpriced'
        WHEN avg_price < q1_price - 1.5 * (q3_price - q1_price) THEN 'underpriced'
        ELSE 'fair_price'
    END AS pricing_flag
FROM product_stats;

-- ============================================================
-- DIMENSÃO 4: DIM_SELLERS
-- ============================================================
-- Dimensão de sellers com métricas de performance e tier.
-- seller_tier habilita condições comerciais diferenciadas.
-- quality_tier correlaciona satisfação com poder de pricing.
-- ============================================================

CREATE OR REPLACE TABLE olist_db.marts.dim_sellers AS
WITH seller_metrics AS (
    SELECT
        s.seller_id,
        s.seller_city,
        s.seller_state,
        s.seller_zip_code_prefix,
        COUNT(DISTINCT oi.order_id) AS total_orders,
        COUNT(oi.order_item_id) AS total_items_sold,
        ROUND(SUM(oi.price), 2) AS total_revenue,
        ROUND(AVG(oi.price), 2) AS avg_ticket,
        ROUND(AVG(oi.freight_value), 2) AS avg_freight,
        ROUND(AVG(oi.freight_ratio_pct), 2) AS avg_freight_ratio,
        ROUND(AVG(ore.review_score), 2) AS avg_review_score,
        COUNT(DISTINCT CASE
            WHEN ore.review_score <= 2
            THEN oi.order_id END) AS low_score_orders,
        ROUND(SUM(oi.price) * 100.0 /
              SUM(SUM(oi.price)) OVER(), 2) AS revenue_share_pct
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
        WHEN total_revenue >= 100000 THEN 'platinum'               -- sellers de maior receita
        WHEN total_revenue >= 50000  THEN 'gold'                   -- sellers de alta receita
        WHEN total_revenue >= 10000  THEN 'silver'                 -- sellers de média receita
        ELSE 'bronze'                                               -- sellers de baixa receita
    END AS seller_tier,
    CASE
        WHEN avg_review_score >= 4.5 THEN 'excellent'              -- alta satisfação
        WHEN avg_review_score >= 3.5 THEN 'good'                   -- satisfação aceitável
        WHEN avg_review_score >= 2.5 THEN 'regular'                -- abaixo da média
        ELSE 'poor'                                                  -- baixa satisfação
    END AS quality_tier
FROM seller_metrics;

-- ============================================================
-- DIMENSÃO 5: DIM_PAYMENTS
-- ============================================================
-- Pagamentos agregados no nível do pedido.
-- Uma linha por pedido com resumo de forma de pagamento.
-- NOTA: MODE() retorna valor arbitrário em caso de empate
-- entre formas de pagamento — comportamento aceitável para BI.
-- ============================================================

CREATE OR REPLACE TABLE olist_db.marts.dim_payments AS
SELECT
    order_id,
    COUNT(payment_sequential) AS total_payments,
    SUM(payment_value) AS total_payment_value,
    MAX(payment_installments) AS max_installments,
    MODE(payment_type) AS primary_payment_type,                    -- em empate retorna valor arbitrário
    SUM(CASE WHEN payment_type = 'credit_card'
        THEN payment_value ELSE 0 END) AS credit_card_value,
    SUM(CASE WHEN payment_type = 'boleto'
        THEN payment_value ELSE 0 END) AS boleto_value,
    SUM(CASE WHEN payment_type = 'voucher'
        THEN payment_value ELSE 0 END) AS voucher_value,
    SUM(CASE WHEN payment_type = 'debit_card'
        THEN payment_value ELSE 0 END) AS debit_card_value
FROM olist_db.staging.order_payments
GROUP BY order_id;

-- ============================================================
-- TABELA FATO: FACT_ORDERS
-- ============================================================
-- Tabela central do Star Schema — uma linha por item de pedido.
-- AJUSTE v1.5: CTE reviews_dedup evita duplicação de linhas
-- causada por múltiplos reviews por pedido no dataset Olist.
-- Usa AVG(review_score) para consolidar múltiplos reviews.
--
-- AJUSTE v1.7: margin_alert sinaliza itens onde freight > price
-- Matematicamente correto — nota metodológica cobre limitação.
--
-- PRIORIDADE DO CASE em pricing_recommendation (intencional):
-- Frete crítico tem prioridade sobre pricing_flag.
-- Decisão de negócio: compensar frete é mais urgente que
-- ajuste de preço relativo ao mercado.
--
-- NOTA METODOLÓGICA:
-- net_value_after_freight = price - freight_value
-- Representa parcela da receita não consumida pelo frete.
-- NÃO é margem de lucro — COGS não disponível no dataset Olist.
-- ============================================================

CREATE OR REPLACE TABLE olist_db.marts.fact_orders AS
WITH reviews_dedup AS (
    -- v1.5: consolida múltiplos reviews por pedido em um único registro
    -- usa AVG para não perder informação quando há mais de um review
    -- evita duplicação de linhas na fact_orders
    SELECT
        order_id,
        ROUND(AVG(review_score), 1) AS review_score
    FROM olist_db.staging.order_reviews
    GROUP BY order_id
)
SELECT
    oi.order_id,
    oi.order_item_id,
    oi.product_id,
    oi.seller_id,
    o.customer_id,
    o.order_purchase_timestamp::DATE AS order_date,                -- chave para dim_date
    o.order_purchase_timestamp,
    o.order_delivered_customer_date,
    oi.price,
    oi.freight_value,
    oi.price AS gross_value,                                       -- receita bruta
    oi.price - oi.freight_value AS net_value_after_freight,        -- receita após frete (não é margem real)
    oi.total_item_value,                                           -- price + freight = custo total ao cliente
    oi.freight_ratio_pct,
    oi.freight_risk_flag,
    o.delivery_days,
    o.delivery_delay_days,
    o.delivery_status,
    r.review_score,                                                -- score consolidado via reviews_dedup
    p.product_category_name,
    p.product_category_english,
    p.price_segment,
    p.pricing_flag,
    s.seller_state,
    s.seller_tier,
    pay.primary_payment_type,
    pay.max_installments,
    DATE_PART('year', o.order_purchase_timestamp) AS order_year,
    DATE_PART('month', o.order_purchase_timestamp) AS order_month,
    DATE_PART('quarter', o.order_purchase_timestamp) AS order_quarter,
    -- MARGIN ALERT (v1.7)
    -- sinaliza itens onde frete supera o preço de venda
    CASE
        WHEN oi.price - oi.freight_value < 0 THEN 'negative_margin'  -- frete > preço: perda por item
        ELSE 'ok'
    END AS margin_alert,
    -- PRICING RECOMMENDATION (Decision Centric)
    -- PRIORIDADE INTENCIONAL: frete crítico avaliado antes de pricing_flag
    -- compensar frete é mais urgente que ajuste relativo ao mercado
    CASE
        WHEN oi.freight_risk_flag = 'critical'
             AND r.review_score <= 2
             THEN 'reduce_price_and_freight'                       -- frete crítico + review ruim
        WHEN oi.freight_risk_flag = 'critical'
             THEN 'review_freight_strategy'                        -- frete corroendo receita
        WHEN p.pricing_flag = 'overpriced'
             AND r.review_score <= 3
             THEN 'reduce_price'                                   -- acima do mercado + reviews ruins
        WHEN p.pricing_flag = 'underpriced'
             AND r.review_score >= 4
             THEN 'increase_price'                                 -- abaixo do mercado + reviews bons
        WHEN r.review_score = 5
             AND p.pricing_flag = 'fair_price'
             THEN 'maintain_pricing'                               -- pricing ótimo confirmado
        ELSE 'monitor'
    END AS pricing_recommendation,
    -- RECOMMENDED PRICE (v1.3 — motor de precificação)
    -- ajuste percentual baseado em pricing_flag e freight_risk_flag
    -- NOTA: percentuais são hipóteses analíticas
    -- em produção devem ser calibrados com elasticidade real
    ROUND(
        CASE
            WHEN p.pricing_flag = 'underpriced'
                 AND r.review_score >= 4
                 THEN oi.price * 1.10                              -- +10%: abaixo do mercado com boa satisfação
            WHEN p.pricing_flag = 'overpriced'
                 AND r.review_score <= 3
                 THEN oi.price * 0.90                              -- -10%: acima do mercado com má satisfação
            WHEN oi.freight_risk_flag = 'critical'
                 THEN oi.price * 1.15                              -- +15%: compensar frete crítico
            WHEN oi.freight_risk_flag = 'attention'
                 THEN oi.price * 1.08                              -- +8%: compensar frete sob atenção
            ELSE oi.price                                           -- manter preço atual
        END
    , 2) AS recommended_price
FROM olist_db.staging.order_items oi
LEFT JOIN olist_db.staging.orders o
    ON oi.order_id = o.order_id
LEFT JOIN olist_db.marts.dim_products p
    ON oi.product_id = p.product_id
LEFT JOIN olist_db.marts.dim_sellers s
    ON oi.seller_id = s.seller_id
LEFT JOIN reviews_dedup r                                          -- v1.5: usa CTE deduplicada
    ON oi.order_id = r.order_id
LEFT JOIN olist_db.marts.dim_payments pay
    ON oi.order_id = pay.order_id;

-- ============================================================
-- VALIDAÇÃO
-- ============================================================

SHOW TABLES IN SCHEMA olist_db.marts;