-- ============================================================
-- PROJETO: Inteligência de Precificação Olist
-- ARQUIVO: 05_silver_etl.sql
-- DESCRIÇÃO: Transformação ETL da camada RAW para STAGING.
--            Aplica todos os tratamentos de qualidade identificados
--            em 04_data_profiling.sql. Esta é a camada Silver
--            da Arquitetura Medallion — dados limpos, tipados,
--            enriquecidos e prontos para modelagem.
--            Pré-requisitos:
--            - 03_load_raw_data.sql deve ter sido executado
--            - Constatações de 04_data_profiling.sql devem ser revisadas
-- AUTOR: Gisele CP
-- DATA: 06/06/2026
-- ============================================================

-- PRINCÍPIOS DE DESIGN DA CAMADA SILVER
-- 1. Todos os campos VARCHAR convertidos para tipos corretos (FLOAT, INT, TIMESTAMP)
-- 2. Valores nulos tratados com COALESCE — sem nulos em campos críticos
-- 3. Apenas pedidos entregues — cancelados/pendentes excluídos da análise de preço
-- 4. Campos derivados adicionados — métricas de negócio calculadas uma vez, reutilizadas em todo o projeto
-- 5. Dados padronizados — nomes de cidades em Title Case, estados em maiúsculas
-- 6. Registros inválidos removidos — coordenadas fora do Brasil, tipos de pagamento indefinidos
-- 7. CREATE OR REPLACE — idempotente, seguro para reexecutar após atualizações de dados brutos
--
-- TRATAMENTOS APLICADOS (baseado nos itens de ação do data profiling):
-- ação 1: filtrar order_status = 'delivered'
-- ação 2: converter todos os campos numéricos de VARCHAR
-- ação 3: atribuir 'uncategorized' para categorias nulas
-- ação 4: remover coordenadas de geolocalização inválidas
-- ação 5: tratar comentários de avaliação nulos como 'no_comment'
-- ação 6: calculada a proporção de frete por categoria
-- ação 7: sinalizar produtos com alta proporção de frete

-- ============================================================
-- CONFIGURAÇÃO DE CONTEXTO
-- ============================================================
-- Define o warehouse, database e schema ativos para esta sessão.
-- ============================================================

USE WAREHOUSE olist_wh;   -- Camada computacional para processamento da transformação
USE DATABASE olist_db;    -- Banco de dados do projeto
USE SCHEMA staging;       -- Schema de destino para dados limpos e enriquecidos

-- ============================================================
-- TABELA 1: STAGING.ORDERS
-- ============================================================
-- Origem: olist_db.raw.orders
-- Tratamentos aplicados:
--   - Filtro: apenas order_status = 'delivered' (97.02% dos pedidos)
--     Pedidos cancelados e pendentes são excluídos da análise de preço
--     pois não representam transações comerciais concluídas.
--   - Cast: todos os campos de timestamp de VARCHAR para TIMESTAMP
--   - Derivado: delivery_days — tempo real de entrega em dias
--     Usado para correlacionar velocidade de entrega com satisfação do cliente.
--   - Derivado: delivery_delay_days — diferença entre entrega real e
--     estimada. Negativo = entregue antes, positivo = atrasado.
--   - Derivado: delivery_status — on_time / late / pending
--     Sinalizador de negócio para monitoramento de SLA e impacto no preço.
-- Linhas esperadas: ~96,478 (apenas pedidos entregues)
-- ============================================================

CREATE OR REPLACE TABLE olist_db.staging.orders AS
SELECT
    order_id,                                                               -- identificador único do pedido
    customer_id,                                                            -- chave estrangeira para clientes
    order_status,                                                           -- sempre 'delivered' após o filtro
    CAST(order_purchase_timestamp AS TIMESTAMP) AS order_purchase_timestamp, -- quando o pedido foi feito
    CAST(order_approved_at AS TIMESTAMP) AS order_approved_at,              -- quando o pagamento foi aprovado
    CAST(order_delivered_carrier_date AS TIMESTAMP) AS order_delivered_carrier_date, -- enviado à transportadora
    CAST(order_delivered_customer_date AS TIMESTAMP) AS order_delivered_customer_date, -- recebido pelo cliente
    CAST(order_estimated_delivery_date AS TIMESTAMP) AS order_estimated_delivery_date, -- data de entrega prometida
    DATEDIFF('day',
        CAST(order_purchase_timestamp AS TIMESTAMP),
        CAST(order_delivered_customer_date AS TIMESTAMP)) AS delivery_days,   -- dias reais para entregar
    DATEDIFF('day',
        CAST(order_delivered_customer_date AS TIMESTAMP),
        CAST(order_estimated_delivery_date AS TIMESTAMP)) AS delivery_delay_days, -- negativo=adiantado, positivo=atrasado
    CASE
        WHEN order_delivered_customer_date <= order_estimated_delivery_date THEN 'on_time' -- entregue no prazo ou antes
        WHEN order_delivered_customer_date > order_estimated_delivery_date THEN 'late'     -- entregue após o prazo
        ELSE 'pending'                                                                    -- ainda não entregue
    END AS delivery_status
FROM olist_db.raw.orders
WHERE order_status = 'delivered'              -- ação 1: excluir pedidos não entregues
AND order_purchase_timestamp IS NOT NULL;     -- excluir pedidos sem data de compra

-- ============================================================
-- TABELA 2: STAGING.ORDER_ITEMS
-- ============================================================
-- Origem: olist_db.raw.order_items
-- Tratamentos aplicados:
--   - Cast: price e freight_value de VARCHAR para FLOAT
--   - Derivado: total_item_value = price + freight
--     Representa o custo real para o cliente por item.
--   - Derivado: freight_ratio_pct = freight / price * 100
--     Métrica chave de preço — alta proporção indica erosão de margem.
--     NULLIF previne divisão por zero quando o preço é 0.
--