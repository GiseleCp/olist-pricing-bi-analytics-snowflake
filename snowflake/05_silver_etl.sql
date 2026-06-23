-- ============================================================
-- PROJECT: Olist Pricing Intelligence
-- FILE: 05_silver_etl.sql
-- DESCRIPTION: Transformação ETL da camada RAW para STAGING.
--              Aplica todos os tratamentos de qualidade identificados
--              em 04_data_profiling.sql. Esta é a camada Silver da
--              Medallion Architecture — dados limpos, tipados,
--              enriquecidos e prontos para modelagem.
--              Pré-requisitos:
--              - 03_load_raw_data.sql deve ter sido executado
--              - findings do 04_data_profiling.sql devem ser revisados
-- AUTHOR: Gisele CP
-- DATE: 2026-05-25
-- UPDATED: 2026-06-23
-- CHANGES:
--   v1.1 - corrigido cálculo de product_volume_cm3
--          removido product_weight_g da fórmula de volume
--          fórmula correta: comprimento * altura * largura
--   v1.2 - refatorado freight_ratio_pct usando CTE
--          eliminada repetição de cálculo em staging.order_items
--   v1.3 - padronização de comentários para português
-- ============================================================

-- PRINCÍPIOS DA CAMADA SILVER
-- 1. Todos os campos VARCHAR convertidos para tipos corretos
-- 2. Valores nulos tratados com COALESCE
-- 3. Apenas pedidos entregues — cancelados e pendentes excluídos
-- 4. Campos derivados calculados uma única vez via CTE
-- 5. Dados padronizados — cidades em title case, estados em maiúsculo
-- 6. Registros inválidos removidos — coordenadas fora do Brasil
-- 7. CREATE OR REPLACE — idempotente, seguro para reexecução

-- TRATAMENTOS APLICADOS (action items do data profiling):
-- ação 1: filtrar order_status = delivered
-- ação 2: converter todos os campos numéricos de VARCHAR
-- ação 3: atribuir uncategorized para categorias nulas
-- ação 4: remover coordenadas inválidas fora do Brasil
-- ação 5: tratar comentários nulos de reviews
-- ação 6: calcular freight_ratio_pct uma única vez via CTE
-- ação 7: sinalizar produtos com alto ratio de frete

-- ============================================================
-- CONFIGURAÇÃO DO CONTEXTO
-- ============================================================

USE WAREHOUSE olist_wh;
USE DATABASE olist_db;
USE SCHEMA staging;

-- ============================================================
-- TABELA 1: STAGING.ORDERS
-- ============================================================
-- Fonte: olist_db.raw.orders
-- Tratamentos aplicados:
--   - Filtro: apenas order_status = 'delivered' (97.02% dos pedidos)
--     Pedidos cancelados e pendentes excluídos da análise de pricing
--   - Cast: todos os campos de timestamp de VARCHAR para TIMESTAMP
--   - Derivado: delivery_days — tempo real de entrega em dias
--   - Derivado: delivery_delay_days — diferença entre entrega real
--     e estimada. Negativo = entregue antes, positivo = atrasado
--   - Derivado: delivery_status — classificação do prazo de entrega
-- Registros esperados: ~96.478 (apenas pedidos entregues)
-- ============================================================

CREATE OR REPLACE TABLE olist_db.staging.orders AS
SELECT
    order_id,                                                               -- identificador único do pedido
    customer_id,                                                            -- chave estrangeira para customers
    order_status,                                                           -- sempre 'delivered' após o filtro
    CAST(order_purchase_timestamp AS TIMESTAMP) AS order_purchase_timestamp,       -- quando o pedido foi feito
    CAST(order_approved_at AS TIMESTAMP) AS order_approved_at,                     -- quando o pagamento foi aprovado
    CAST(order_delivered_carrier_date AS TIMESTAMP) AS order_delivered_carrier_date, -- entregue à transportadora
    CAST(order_delivered_customer_date AS TIMESTAMP) AS order_delivered_customer_date, -- recebido pelo cliente
    CAST(order_estimated_delivery_date AS TIMESTAMP) AS order_estimated_delivery_date, -- prazo prometido ao cliente
    DATEDIFF('day',
        CAST(order_purchase_timestamp AS TIMESTAMP),
        CAST(order_delivered_customer_date AS TIMESTAMP)) AS delivery_days,        -- dias reais de entrega
    DATEDIFF('day',
        CAST(order_delivered_customer_date AS TIMESTAMP),
        CAST(order_estimated_delivery_date AS TIMESTAMP)) AS delivery_delay_days,  -- negativo=adiantado, positivo=atrasado
    CASE
        WHEN order_delivered_customer_date <= order_estimated_delivery_date THEN 'entregue_no_prazo'  -- dentro do prazo
        WHEN order_delivered_customer_date > order_estimated_delivery_date  THEN 'entregue_com_atraso' -- após o prazo
        ELSE 'pendente'                                                             -- ainda não entregue
    END AS delivery_status
FROM olist_db.raw.orders
WHERE order_status = 'delivered'               -- ação 1: excluir pedidos não entregues
AND order_purchase_timestamp IS NOT NULL;      -- excluir pedidos sem data de compra

-- ============================================================
-- TABELA 2: STAGING.ORDER_ITEMS
-- ============================================================
-- Fonte: olist_db.raw.order_items
-- Tratamentos aplicados:
--   - Cast: price e freight_value de VARCHAR para FLOAT
--   - CTE base_items: calcula freight_ratio_pct uma única vez
--     evitando repetição de cálculo no SELECT final
--   - Derivado: total_item_value = price + freight_value
--     representa o custo total ao cliente por item
--   - Derivado: freight_ratio_pct = freight / price * 100
--     métrica chave de pricing — ratio alto indica erosão de receita
--     NULLIF evita divisão por zero quando price = 0
--   - Derivado: freight_risk_flag — classificação de risco:
--     critico (>30%): frete > 30% do preço, margem em risco
--     atencao (>20%): frete entre 20-30%, margem sob pressão
--     ok (<20%): ratio aceitável de frete
-- Registros esperados: ~112.650
-- ============================================================

CREATE OR REPLACE TABLE olist_db.staging.order_items AS
WITH base_items AS (
    -- CTE calcula freight_ratio_pct uma única vez para reutilização
    -- evita repetição de código e garante consistência do cálculo
    SELECT
        order_id,
        order_item_id,
        product_id,
        seller_id,
        shipping_limit_date,
        CAST(price AS FLOAT) AS price,                                      -- preço do item em BRL
        CAST(freight_value AS FLOAT) AS freight_value,                      -- valor do frete em BRL
        ROUND(
            CAST(freight_value AS FLOAT) /
            NULLIF(CAST(price AS FLOAT), 0) * 100
        , 2) AS freight_ratio_pct                                           -- frete como % do preço
    FROM olist_db.raw.order_items
    WHERE price IS NOT NULL                                                  -- excluir itens sem preço
    AND freight_value IS NOT NULL                                            -- excluir itens sem frete
)
SELECT
    order_id,                                                               -- chave estrangeira para orders
    order_item_id,                                                          -- sequência do item no pedido
    product_id,                                                             -- chave estrangeira para products
    seller_id,                                                              -- chave estrangeira para sellers
    CAST(shipping_limit_date AS TIMESTAMP) AS shipping_limit_date,          -- prazo de envio pelo seller
    price,                                                                  -- preço do item em BRL
    freight_value,                                                          -- valor do frete em BRL
    price + freight_value AS total_item_value,                              -- custo total ao cliente
    freight_ratio_pct,                                                      -- frete como % do preço (calculado na CTE)
    CASE
        WHEN freight_ratio_pct > 30 THEN 'critico'                         -- frete corrói receita
        WHEN freight_ratio_pct > 20 THEN 'atencao'                         -- receita sob pressão
        ELSE 'ok'                                                           -- ratio aceitável
    END AS freight_risk_flag                                                -- decisão: ajuste de preço necessário
FROM base_items;

-- ============================================================
-- TABELA 3: STAGING.PRODUCTS
-- ============================================================
-- Fonte: olist_db.raw.products
-- Tratamentos aplicados:
--   - Nulo: COALESCE atribui 'uncategorized' para category nula
--     (610 nulos identificados no profiling)
--     Evita que R$ 179.535 de receita fique fora da análise
--   - Cast: todos os campos numéricos de VARCHAR para tipos corretos
--   - Nulo: COALESCE atribui 0 para dimensões nulas (2 nulos)
--   - Derivado: product_volume_cm3 = comprimento * altura * largura
--     NOTA: peso NÃO faz parte do cálculo de volume cúbico
--     corrigido em v1.1 — fórmula anterior incluía weight_g por engano
--     volume é usado para estimar custo logístico de produtos grandes
-- Registros esperados: ~32.951
-- ============================================================

CREATE OR REPLACE TABLE olist_db.staging.products AS
SELECT
    product_id,                                                                        -- identificador único do produto
    COALESCE(product_category_name, 'uncategorized') AS product_category_name,        -- ação 3: preenche categoria nula
    CAST(product_name_lenght AS INT) AS product_name_length,                          -- tamanho do nome em caracteres
    CAST(product_description_lenght AS INT) AS product_description_length,            -- tamanho da descrição em caracteres
    CAST(product_photos_qty AS INT) AS product_photos_qty,                            -- quantidade de fotos do produto
    COALESCE(CAST(product_weight_g AS FLOAT), 0) AS product_weight_g,                 -- peso em gramas (0 se nulo)
    COALESCE(CAST(product_length_cm AS FLOAT), 0) AS product_length_cm,               -- comprimento em cm (0 se nulo)
    COALESCE(CAST(product_height_cm AS FLOAT), 0) AS product_height_cm,               -- altura em cm (0 se nulo)
    COALESCE(CAST(product_width_cm AS FLOAT), 0) AS product_width_cm,                 -- largura em cm (0 se nulo)
    COALESCE(CAST(product_length_cm AS FLOAT), 0) *
    COALESCE(CAST(product_height_cm AS FLOAT), 0) *
    COALESCE(CAST(product_width_cm AS FLOAT), 0) AS product_volume_cm3                -- volume cúbico: comprimento * altura * largura
FROM olist_db.raw.products;

-- ============================================================
-- TABELA 4: STAGING.CUSTOMERS
-- ============================================================
-- Fonte: olist_db.raw.customers
-- Tratamentos aplicados:
--   - INITCAP: padroniza nomes de cidades para Title Case
--     ex: 'sao paulo' -> 'Sao Paulo'
--   - UPPER: padroniza códigos de estado para maiúsculo
--     ex: 'sp' -> 'SP'
-- Registros esperados: ~99.441 (zero nulos confirmados no profiling)
-- ============================================================

CREATE OR REPLACE TABLE olist_db.staging.customers AS
SELECT
    customer_id,                                        -- identificador de transação do cliente
    customer_unique_id,                                 -- identificador único real do cliente
    customer_zip_code_prefix,                           -- primeiros 5 dígitos do CEP
    INITCAP(customer_city) AS customer_city,            -- cidade padronizada em Title Case
    UPPER(customer_state) AS customer_state             -- estado padronizado em maiúsculo
FROM olist_db.raw.customers;

-- ============================================================
-- TABELA 5: STAGING.SELLERS
-- ============================================================
-- Fonte: olist_db.raw.sellers
-- Tratamentos aplicados:
--   - INITCAP: padroniza nomes de cidades para Title Case
--   - UPPER: padroniza códigos de estado para maiúsculo
-- Registros esperados: ~3.095 (zero nulos confirmados no profiling)
-- ============================================================

CREATE OR REPLACE TABLE olist_db.staging.sellers AS
SELECT
    seller_id,                                          -- identificador único do seller
    seller_zip_code_prefix,                             -- primeiros 5 dígitos do CEP do seller
    INITCAP(seller_city) AS seller_city,                -- cidade padronizada em Title Case
    UPPER(seller_state) AS seller_state                 -- estado padronizado em maiúsculo
FROM olist_db.raw.sellers;

-- ============================================================
-- TABELA 6: STAGING.ORDER_PAYMENTS
-- ============================================================
-- Fonte: olist_db.raw.order_payments
-- Tratamentos aplicados:
--   - Filtro: remove payment_type = 'not_defined' (3 registros)
--     Esses registros têm payment_value = 0 e tipo inválido
--   - Cast: payment_sequential e payment_installments para INT
--   - Cast: payment_value para FLOAT
-- Registros esperados: ~103.883 (3 registros not_defined removidos)
-- ============================================================

CREATE OR REPLACE TABLE olist_db.staging.order_payments AS
SELECT
    order_id,                                                           -- chave estrangeira para orders
    CAST(payment_sequential AS INT) AS payment_sequential,             -- sequência do pagamento (split payments)
    payment_type,                                                       -- credit_card, boleto, voucher, debit_card
    CAST(payment_installments AS INT) AS payment_installments,         -- número de parcelas
    CAST(payment_value AS FLOAT) AS payment_value                      -- valor do pagamento em BRL
FROM olist_db.raw.order_payments
WHERE payment_type != 'not_defined';               -- remove 3 registros com tipo de pagamento indefinido

-- ============================================================
-- TABELA 7: STAGING.ORDER_REVIEWS
-- ============================================================
-- Fonte: olist_db.raw.order_reviews
-- Tratamentos aplicados:
--   - Cast: review_score de VARCHAR para INT
--   - COALESCE: substitui títulos nulos por 'sem_titulo'
--     (87.656 nulos = 88% dos registros — todos tratados)
--   - COALESCE: substitui mensagens nulas por 'sem_comentario'
--     (58.247 nulos = 59% dos registros — todos tratados)
--   - Cast: campos de data de VARCHAR para TIMESTAMP
-- Registros esperados: ~99.224
-- ============================================================

CREATE OR REPLACE TABLE olist_db.staging.order_reviews AS
SELECT
    review_id,                                                                  -- identificador único do review
    order_id,                                                                   -- chave estrangeira para orders
    CAST(review_score AS INT) AS review_score,                                  -- nota de satisfação 1-5
    COALESCE(review_comment_title, 'sem_titulo') AS review_comment_title,       -- ação 5: preenche título nulo
    COALESCE(review_comment_message, 'sem_comentario') AS review_comment_message, -- preenche mensagem nula
    CAST(review_creation_date AS TIMESTAMP) AS review_creation_date,            -- quando o review foi criado
    CAST(review_answer_timestamp AS TIMESTAMP) AS review_answer_timestamp       -- quando o cliente enviou
FROM olist_db.raw.order_reviews;

-- ============================================================
-- TABELA 8: STAGING.GEOLOCATION
-- ============================================================
-- Fonte: olist_db.raw.geolocation
-- Tratamentos aplicados:
--   - Filtro: remove coordenadas fora dos limites geográficos do Brasil
--     Limites de latitude:  -33.75 (sul) a +5.27 (norte)
--     Limites de longitude: -73.98 (oeste) a -34.79 (leste)
--     31 latitudes e 37 longitudes inválidas removidas
--   - Cast: lat e lng de VARCHAR para FLOAT
--   - INITCAP: padroniza nomes de cidades para Title Case
--   - UPPER: padroniza códigos de estado para maiúsculo
-- Registros esperados: ~1.000.121 (42 coordenadas inválidas removidas)
-- ============================================================

CREATE OR REPLACE TABLE olist_db.staging.geolocation AS
SELECT
    geolocation_zip_code_prefix,                                        -- primeiros 5 dígitos do CEP
    CAST(geolocation_lat AS FLOAT) AS geolocation_lat,                  -- coordenada de latitude
    CAST(geolocation_lng AS FLOAT) AS geolocation_lng,                  -- coordenada de longitude
    INITCAP(geolocation_city) AS geolocation_city,                      -- cidade padronizada em Title Case
    UPPER(geolocation_state) AS geolocation_state                       -- estado padronizado em maiúsculo
FROM olist_db.raw.geolocation
WHERE CAST(geolocation_lat AS FLOAT) BETWEEN -33.75 AND 5.27            -- ação 4: limites de latitude do Brasil
AND CAST(geolocation_lng AS FLOAT) BETWEEN -73.98 AND -34.79;           -- ação 4: limites de longitude do Brasil

-- ============================================================
-- TABELA 9: STAGING.CATEGORY_TRANSLATION
-- ============================================================
-- Fonte: olist_db.raw.category_translation
-- Nenhum tratamento necessário — 71 registros, zero nulos confirmados
-- Usada nas camadas MARTS para exibir nomes de categorias em inglês
-- nos dashboards e relatórios
-- Registros esperados: 71
-- ============================================================

CREATE OR REPLACE TABLE olist_db.staging.category_translation AS
SELECT
    product_category_name,          -- nome da categoria em português
    product_category_name_english   -- nome da categoria em inglês
FROM olist_db.raw.category_translation;

-- ============================================================
-- VALIDAÇÃO
-- ============================================================
-- Confirma que todas as 9 tabelas foram criadas no schema STAGING.
-- Compare os totais com a camada RAW para validar os tratamentos:
--   orders:         96.478 vs 99.441 raw (-2.963 não entregues)
--   order_payments: 103.883 vs 103.886 raw (-3 not_defined)
--   geolocation:  1.000.121 vs 1.000.163 raw (-42 coords inválidas)
--   demais tabelas: mesmo total que o RAW
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