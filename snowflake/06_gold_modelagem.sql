-- ============================================================
-- PROJECT: Olist Pricing Intelligence
-- FILE: 06_gold_modelagem.sql
-- DESCRIPTION: Modelagem Star Schema na camada MARTS.
--              Cria tabelas fato e dimensão para consumo de BI
--              e suporte a decisões de pricing.
--              Esta é a camada Gold da Medallion Architecture.
-- AUTHOR: Gisele CP
-- DATE: 2026-06-10
-- UPDATED: 2026-06-23
-- CHANGES:
--   v1.1 - RFM com pesos (R=0.4, F=0.3, M=0.3)
--   v1.2 - métricas financeiras no fact_orders
--          gross_value e net_value_after_freight adicionados
--   v1.3 - recommended_price adicionado ao fact_orders
--          transforma análise em motor de precificação
--   v1.4 - comentários padronizados em português
-- MELHORIAS FUTURAS (fora do escopo atual):
--   - surrogate keys (customer_key, product_key) para SCD Type 2
--   - dim_categories separada com margin_target por categoria
--   - estimated_margin real quando COGS estiver disponível
-- ============================================================

-- VISÃO GERAL DO STAR SCHEMA
-- Um Star Schema organiza dados em uma tabela FATO central
-- cercada por tabelas DIMENSÃO. Otimizado para queries analíticas
-- e ferramentas de BI como Power BI e Looker Studio.
--
-- TABELA FATO (métricas — o que aconteceu):
--   fact_orders -> uma linha por item de pedido com todas as métricas
--
-- TABELAS DIMENSÃO (contexto — quem, o quê, onde, quando):
--   dim_customers  -> segmentação de clientes com RFM ponderado
--   dim_products   -> detalhes do produto com flags de pricing
--   dim_sellers    -> métricas de performance dos sellers
--   dim_payments   -> agregados de pagamento por pedido
--   dim_date       -> dimensão de data para inteligência temporal
--
-- DESIGN DECISION CENTRIC:
-- Cada tabela inclui flags e recomendações que suportam decisões:
--   freight_risk_flag:       identifica erosão de margem pelo frete
--   price_segment:           classifica produtos por faixa de preço
--   rfm_segment:             classifica clientes por comportamento
--   seller_tier:             classifica sellers por performance
--   pricing_recommendation:  recomendação acionável por item
--   recommended_price:       preço sugerido calculado automaticamente

-- ============================================================
-- CONFIGURAÇÃO DO CONTEXTO
-- ============================================================

USE WAREHOUSE olist_wh;
USE DATABASE olist_db;
USE SCHEMA marts;

-- ============================================================
-- DIMENSÃO 1: DIM_DATE
-- ============================================================
-- Dimensão de data para análise de inteligência temporal.
-- Habilita análise de sazonalidade, comparações ano a ano
-- e identificação de tendências mensais e trimestrais de preço.
-- Gerada a partir do range de datas dos pedidos: 2016-09-04 a 2018-10-17.
-- Usa a função GENERATOR do Snowflake para criar sequência de datas.
-- ============================================================

CREATE OR REPLACE TABLE olist_db.marts.dim_date AS
WITH date_spine AS (
    SELECT
        DATEADD('day', SEQ4(), '2016-09-01'::DATE) AS date_day   -- gera uma linha por dia
    FROM TABLE(GENERATOR(ROWCOUNT => 800))                         -- 800 dias cobre todo o range do dataset
)
SELECT
    date_day AS date_id,                                           -- chave primária — a própria data
    DATE_PART('year', date_day) AS year,                           -- número do ano
    DATE_PART('month', date_day) AS month_number,                  -- número do mês 1-12
    MONTHNAME(date_day) AS month_name,                             -- nome do mês (Jan, Fev...)
    DATE_PART('quarter', date_day) AS quarter,                     -- trimestre 1-4
    DATE_PART('week', date_day) AS week_number,                    -- número da semana 1-52
    DATE_PART('dayofweek', date_day) AS day_of_week,               -- dia da semana 0=Domingo
    DAYNAME(date_day) AS day_name,                                 -- nome do dia (Seg, Ter...)
    CASE
        WHEN DATE_PART('month', date_day) IN (11, 12) THEN 'alta_temporada'    -- Nov-Dez: Black Friday e Natal
        WHEN DATE_PART('month', date_day) IN (1, 2)   THEN 'pos_temporada'     -- Jan-Fev: desaceleração pós-férias
        ELSE 'temporada_regular'                                                -- restante do ano
    END AS season_flag,                                            -- classificação de temporada para pricing
    CASE
        WHEN DATE_PART('dayofweek', date_day) IN (0, 6) THEN TRUE
        ELSE FALSE
    END AS is_weekend                                              -- flag de fim de semana para análise de entrega
FROM date_spine;

-- ============================================================
-- DIMENSÃO 2: DIM_CUSTOMERS
-- ============================================================
-- Dimensão de clientes com scores RFM ponderados.
-- RFM (Recência, Frequência, Monetário) é o framework padrão
-- para segmentação de clientes em estratégia de pricing.
--
-- RECÊNCIA:   quando foi a última compra?
--             Clientes recentes têm maior probabilidade de recompra.
-- FREQUÊNCIA: quantos pedidos o cliente fez?
--             Clientes frequentes são menos sensíveis a preço.
-- MONETÁRIO:  quanto o cliente gastou no total?
--             Clientes de alto valor merecem estratégia premium.
--
-- RFM PONDERADO (v1.1):
-- Pesos aplicados refletem importância relativa para pricing:
--   Recência   = 40% (maior peso — comportamento mais recente)
--   Frequência = 30% (fidelidade ao canal)
--   Monetário  = 30% (valor gerado ao negócio)
-- Score final varia de 1.0 a 3.0
--
-- NOTA SOBRE SURROGATE KEYS:
-- customer_id é usado como chave neste projeto.
-- Em DW corporativo seria adicionado customer_key INT
-- para suportar SCD Type 2 e melhor performance.
-- Documentado como melhoria futura.
-- ============================================================

CREATE OR REPLACE TABLE olist_db.marts.dim_customers AS
WITH customer_orders AS (
    SELECT
        c.customer_unique_id,                                      -- identificador real do cliente
        c.customer_id,                                             -- identificador de transação
        c.customer_city,
        c.customer_state,
        c.customer_zip_code_prefix,
        COUNT(DISTINCT o.order_id) AS total_orders,                -- métrica de frequência
        SUM(oi.price + oi.freight_value) AS total_spent,           -- métrica monetária
        MAX(o.order_purchase_timestamp) AS last_order_date,        -- data da última compra
        DATEDIFF('day',
            MAX(o.order_purchase_timestamp),
            '2018-10-17'::TIMESTAMP) AS days_since_last_order,     -- métrica de recência em dias
        ROUND(AVG(oi.price), 2) AS avg_order_value,                -- ticket médio
        ROUND(AVG(oi.freight_value), 2) AS avg_freight_paid        -- frete médio pago
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
        -- scores individuais usando NTILE(3) — divide clientes em 3 grupos iguais
        NTILE(3) OVER (ORDER BY days_since_last_order ASC) AS recency_score,    -- 3=mais recente
        NTILE(3) OVER (ORDER BY total_orders DESC) AS frequency_score,           -- 3=mais frequente
        NTILE(3) OVER (ORDER BY total_spent DESC) AS monetary_score              -- 3=maior gasto
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
    recency_score,                                                  -- score de recência 1-3
    frequency_score,                                                -- score de frequência 1-3
    monetary_score,                                                 -- score monetário 1-3
    recency_score + frequency_score + monetary_score AS rfm_score,  -- score combinado 3-9
    -- RFM PONDERADO (v1.1): pesos refletem importância para pricing
    -- recência=40%, frequência=30%, monetário=30%
    ROUND(
        (recency_score * 0.4) +
        (frequency_score * 0.3) +
        (monetary_score * 0.3)
    , 2) AS rfm_weighted_score,                                     -- score ponderado 1.0-3.0
    CASE
        WHEN (recency_score * 0.4) + (frequency_score * 0.3) + (monetary_score * 0.3) >= 2.5
            THEN 'campeoes'                                         -- melhores clientes
        WHEN (recency_score * 0.4) + (frequency_score * 0.3) + (monetary_score * 0.3) >= 2.0
            THEN 'fieis'                                            -- compradores regulares
        WHEN (recency_score * 0.4) + (frequency_score * 0.3) + (monetary_score * 0.3) >= 1.5
            THEN 'potenciais'                                       -- oportunidade de crescimento
        ELSE 'em_risco'                                             -- necessita atenção
    END AS rfm_segment                                              -- decisão: estratégia de pricing por segmento
FROM rfm_scores;

-- ============================================================
-- DIMENSÃO 3: DIM_PRODUCTS
-- ============================================================
-- Dimensão de produtos com inteligência de pricing.
-- Inclui detecção de outliers de preço via método IQR —
-- mais robusto que desvio padrão para dados assimétricos.
-- price_segment classifica produtos para estratégia de pricing em tiers.
--
-- NOTA SOBRE DIM_CATEGORIES:
-- Em modelo maior seria criada dim_categories separada com
-- margin_target e pricing_strategy por categoria.
-- Documentado como melhoria futura.
-- ============================================================

CREATE OR REPLACE TABLE olist_db.marts.dim_products AS
WITH product_stats AS (
    SELECT
        p.product_id,
        p.product_category_name,
        ct.product_category_name_english,                          -- nome em inglês para dashboards
        p.product_weight_g,
        p.product_length_cm,
        p.product_height_cm,
        p.product_width_cm,
        p.product_volume_cm3,
        ROUND(AVG(oi.price), 2) AS avg_price,                      -- preço médio de venda
        ROUND(MIN(oi.price), 2) AS min_price,                      -- preço mínimo vendido
        ROUND(MAX(oi.price), 2) AS max_price,                      -- preço máximo vendido
        ROUND(AVG(oi.freight_value), 2) AS avg_freight,            -- frete médio cobrado
        ROUND(AVG(oi.freight_ratio_pct), 2) AS avg_freight_ratio,  -- ratio frete/preço médio
        COUNT(oi.order_item_id) AS total_items_sold,               -- total de unidades vendidas
        ROUND(SUM(oi.price), 2) AS total_revenue,                  -- receita total gerada
        ROUND(AVG(oi.freight_value) /
              NULLIF(AVG(oi.price), 0) * 100, 2) AS freight_ratio_pct, -- ratio calculado para classificação
        PERCENTILE_CONT(0.25) WITHIN GROUP
            (ORDER BY oi.price) AS q1_price,                       -- primeiro quartil para IQR
        PERCENTILE_CONT(0.75) WITHIN GROUP
            (ORDER BY oi.price) AS q3_price                        -- terceiro quartil para IQR
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
    ROUND(q3_price - q1_price, 2) AS iqr,                          -- intervalo interquartil
    ROUND(q1_price - 1.5 * (q3_price - q1_price), 2) AS price_lower_bound, -- limite inferior IQR
    ROUND(q3_price + 1.5 * (q3_price - q1_price), 2) AS price_upper_bound, -- limite superior IQR
    CASE
        WHEN avg_price <= 50  THEN 'budget'                        -- segmento econômico
        WHEN avg_price <= 150 THEN 'mid_range'                     -- segmento intermediário
        WHEN avg_price <= 500 THEN 'premium'                       -- segmento premium
        ELSE 'luxury'                                               -- segmento luxo
    END AS price_segment,                                           -- decisão: estratégia de pricing por tier
    CASE
        WHEN freight_ratio_pct > 30 THEN 'critico'                 -- frete corrói receita
        WHEN freight_ratio_pct > 20 THEN 'atencao'                 -- receita sob pressão
        ELSE 'ok'                                                   -- ratio aceitável
    END AS freight_risk_flag,                                       -- decisão: ajuste de preço necessário
    CASE
        WHEN avg_price > q3_price + 1.5 * (q3_price - q1_price) THEN 'acima_do_mercado'  -- acima do limite IQR
        WHEN avg_price < q1_price - 1.5 * (q3_price - q1_price) THEN 'abaixo_do_mercado' -- abaixo do limite IQR
        ELSE 'preco_justo'                                                                  -- dentro do range normal
    END AS pricing_flag                                             -- decisão: revisão de preço necessária
FROM product_stats;

-- ============================================================
-- DIMENSÃO 4: DIM_SELLERS
-- ============================================================
-- Dimensão de sellers com métricas de performance e classificação por tier.
-- seller_tier habilita estratégia de pricing diferenciada por seller.
-- avg_review_score correlaciona qualidade do seller com poder de pricing.
-- ============================================================

CREATE OR REPLACE TABLE olist_db.marts.dim_sellers AS
WITH seller_metrics AS (
    SELECT
        s.seller_id,
        s.seller_city,
        s.seller_state,
        s.seller_zip_code_prefix,
        COUNT(DISTINCT oi.order_id) AS total_orders,               -- pedidos únicos atendidos
        COUNT(oi.order_item_id) AS total_items_sold,               -- total de unidades vendidas
        ROUND(SUM(oi.price), 2) AS total_revenue,                  -- receita total gerada
        ROUND(AVG(oi.price), 2) AS avg_ticket,                     -- ticket médio de venda
        ROUND(AVG(oi.freight_value), 2) AS avg_freight,            -- frete médio cobrado
        ROUND(AVG(oi.freight_ratio_pct), 2) AS avg_freight_ratio,  -- ratio frete/preço médio
        ROUND(AVG(ore.review_score), 2) AS avg_review_score,       -- satisfação média dos clientes
        COUNT(DISTINCT CASE
            WHEN ore.review_score <= 2
            THEN oi.order_id END) AS low_score_orders,             -- pedidos com avaliação ruim
        ROUND(SUM(oi.price) * 100.0 /
              SUM(SUM(oi.price)) OVER(), 2) AS revenue_share_pct   -- participação na receita total
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
        WHEN total_revenue >= 100000 THEN 'platina'                -- sellers de maior receita
        WHEN total_revenue >= 50000  THEN 'ouro'                   -- sellers de alta receita
        WHEN total_revenue >= 10000  THEN 'prata'                  -- sellers de média receita
        ELSE 'bronze'                                               -- sellers de baixa receita
    END AS seller_tier,                                             -- decisão: condições comerciais por tier
    CASE
        WHEN avg_review_score >= 4.5 THEN 'excelente'              -- alta satisfação
        WHEN avg_review_score >= 3.5 THEN 'bom'                    -- satisfação aceitável
        WHEN avg_review_score >= 2.5 THEN 'regular'                -- abaixo da média
        ELSE 'ruim'                                                  -- baixa satisfação — risco de pricing
    END AS quality_tier                                             -- decisão: classificação de qualidade do seller
FROM seller_metrics;

-- ============================================================
-- DIMENSÃO 5: DIM_PAYMENTS
-- ============================================================
-- Dimensão de pagamentos agregada no nível do pedido.
-- Uma linha por pedido com resumo de pagamento.
-- Habilita segmentação por tipo de pagamento na análise de pricing.
-- ============================================================

CREATE OR REPLACE TABLE olist_db.marts.dim_payments AS
SELECT
    order_id,                                                       -- chave estrangeira para fact_orders
    COUNT(payment_sequential) AS total_payments,                    -- número de registros de pagamento
    SUM(payment_value) AS total_payment_value,                      -- valor total pago
    MAX(payment_installments) AS max_installments,                  -- máximo de parcelas utilizadas
    MODE(payment_type) AS primary_payment_type,                     -- forma de pagamento mais usada
    SUM(CASE WHEN payment_type = 'credit_card'
        THEN payment_value ELSE 0 END) AS credit_card_value,        -- valor pago no cartão de crédito
    SUM(CASE WHEN payment_type = 'boleto'
        THEN payment_value ELSE 0 END) AS boleto_value,             -- valor pago no boleto
    SUM(CASE WHEN payment_type = 'voucher'
        THEN payment_value ELSE 0 END) AS voucher_value,            -- valor pago com voucher
    SUM(CASE WHEN payment_type = 'debit_card'
        THEN payment_value ELSE 0 END) AS debit_card_value          -- valor pago no cartão de débito
FROM olist_db.staging.order_payments
GROUP BY order_id;

-- ============================================================
-- TABELA FATO: FACT_ORDERS
-- ============================================================
-- Tabela central do Star Schema.
-- Uma linha por item de pedido — nível mais granular de análise.
-- Conecta todas as dimensões para contexto completo de cada transação.
--
-- MÉTRICAS FINANCEIRAS (v1.2):
--   price:                  preço bruto do item
--   freight_value:          frete cobrado do cliente
--   gross_value:            receita bruta = price (sem descontos)
--   net_value_after_freight: receita líquida = price - freight_value
--   NOTA METODOLÓGICA: net_value_after_freight representa a parcela
--   da receita não consumida pelo frete — NÃO é margem de lucro real.
--   COGS não está disponível no dataset Olist.
--
-- MOTOR DE PRECIFICAÇÃO (v1.3):
--   recommended_price: preço sugerido calculado automaticamente
--   Transforma o projeto de análise em motor de precificação.
--   Metodologia: ajuste percentual baseado em pricing_flag e review_score.
-- ============================================================

CREATE OR REPLACE TABLE olist_db.marts.fact_orders AS
SELECT
    oi.order_id,                                                    -- identificador do pedido
    oi.order_item_id,                                               -- sequência do item no pedido
    oi.product_id,                                                  -- chave estrangeira para dim_products
    oi.seller_id,                                                   -- chave estrangeira para dim_sellers
    o.customer_id,                                                  -- chave estrangeira para dim_customers
    o.order_purchase_timestamp::DATE AS order_date,                 -- chave estrangeira para dim_date
    o.order_purchase_timestamp,                                     -- timestamp completo da compra
    o.order_delivered_customer_date,                                -- timestamp de entrega
    oi.price,                                                       -- preço de venda do item
    oi.freight_value,                                               -- frete cobrado do cliente
    oi.price AS gross_value,                                        -- receita bruta (= price neste dataset)
    oi.price - oi.freight_value AS net_value_after_freight,         -- receita após frete (não é margem real)
    oi.total_item_value,                                            -- price + freight = custo total ao cliente
    oi.freight_ratio_pct,                                           -- frete como % do preço
    oi.freight_risk_flag,                                           -- critico / atencao / ok
    o.delivery_days,                                                -- dias reais de entrega
    o.delivery_delay_days,                                          -- atraso vs prazo estimado
    o.delivery_status,                                              -- entregue_no_prazo / entregue_com_atraso
    ore.review_score,                                               -- satisfação do cliente 1-5
    p.product_category_name,                                        -- categoria do produto em português
    p.product_category_english,                                     -- categoria do produto em inglês
    p.price_segment,                                                -- budget / mid_range / premium / luxury
    p.pricing_flag,                                                 -- acima_do_mercado / abaixo_do_mercado / preco_justo
    s.seller_state,                                                 -- estado do seller
    s.seller_tier,                                                  -- platina / ouro / prata / bronze
    pay.primary_payment_type,                                       -- forma de pagamento principal
    pay.max_installments,                                           -- parcelas utilizadas
    DATE_PART('year', o.order_purchase_timestamp) AS order_year,    -- ano para análise temporal
    DATE_PART('month', o.order_purchase_timestamp) AS order_month,  -- mês para sazonalidade
    DATE_PART('quarter', o.order_purchase_timestamp) AS order_quarter, -- trimestre para tendência
    -- RECOMENDAÇÃO DE PRICING (Decision Centric)
    CASE
        WHEN oi.freight_risk_flag = 'critico'
             AND ore.review_score <= 2
             THEN 'reduzir_preco_e_frete'                           -- preço alto + review ruim + frete crítico
        WHEN oi.freight_risk_flag = 'critico'
             THEN 'revisar_estrategia_frete'                        -- frete corroendo receita
        WHEN p.pricing_flag = 'acima_do_mercado'
             AND ore.review_score <= 3
             THEN 'reduzir_preco'                                   -- acima do mercado com reviews ruins
        WHEN p.pricing_flag = 'abaixo_do_mercado'
             AND ore.review_score >= 4
             THEN 'aumentar_preco'                                  -- abaixo do mercado com reviews bons
        WHEN ore.review_score = 5
             AND p.pricing_flag = 'preco_justo'
             THEN 'manter_pricing'                                  -- pricing ótimo confirmado
        ELSE 'monitorar'                                            -- monitoramento padrão
    END AS pricing_recommendation,                                  -- DECISION CENTRIC: orientação acionável
    -- PREÇO RECOMENDADO (v1.3 — motor de precificação)
    -- Metodologia: ajuste percentual baseado em pricing_flag e review_score
    -- NOTA: estes percentuais são hipóteses analíticas
    -- Em produção devem ser calibrados com elasticidade real e dados de concorrência
    ROUND(
        CASE
            WHEN p.pricing_flag = 'abaixo_do_mercado'
                 AND ore.review_score >= 4
                 THEN oi.price * 1.10                               -- +10%: abaixo do mercado com boa satisfação
            WHEN p.pricing_flag = 'acima_do_mercado'
                 AND ore.review_score <= 3
                 THEN oi.price * 0.90                               -- -10%: acima do mercado com má satisfação
            WHEN oi.freight_risk_flag = 'critico'
                 THEN oi.price * 1.15                               -- +15%: compensar frete crítico
            WHEN oi.freight_risk_flag = 'atencao'
                 THEN oi.price * 1.08                               -- +8%: compensar frete sob atenção
            ELSE oi.price                                            -- manter preço atual
        END
    , 2) AS recommended_price                                       -- preço sugerido pelo motor de precificação
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
-- VALIDAÇÃO
-- ============================================================
-- Confirma que todas as tabelas foram criadas no schema MARTS.
-- Tabelas esperadas: dim_date, dim_customers, dim_products,
--                   dim_sellers, dim_payments, fact_orders
-- ============================================================

SHOW TABLES IN SCHEMA olist_db.marts;