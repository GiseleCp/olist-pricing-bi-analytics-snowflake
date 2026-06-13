-- ============================================================
-- PROJETO: Olist Pricing Intelligence
-- ARQUIVO: 03_load_raw_data.sql
-- DESCRIÇÃO: Carrega os 9 arquivos CSV do stage interno do
--             Snowflake (raw_stage) para as tabelas da camada RAW.
--             Utiliza o comando COPY INTO — mecanismo nativo de
--             carga em massa do Snowflake.
-------------------------------------------

--             Pré-requisitos:
--             - 01_setup_environment.sql executado
--             - 02_create_raw_tables.sql executado
--             - Arquivos CSV enviados para o raw_stage
-- AUTORA: Gisele CP
-- DATA: 2026-06-06
-- ============================================================

-- VISÃO GERAL DO COPY INTO
-- COPY INTO é o comando nativo de carga em massa do Snowflake.
-- Ele lê arquivos de um stage e os carrega para uma tabela.
------------------------------------------------------------

-- Parâmetros FILE_FORMAT:
--   TYPE = CSV -> formato do arquivo
--   FIELD_OPTIONALLY_ENCLOSED_BY = '"' -> trata campos envolvidos por aspas
--   SKIP_HEADER = 1 -> ignora a primeira linha (cabeçalho)
-----------------------------------------------------------

-- O stage @olist_db.raw.raw_stage foi criado manualmente
-- pela interface do Snowflake e contém os 9 arquivos CSV.

-- ============================================================
-- CONFIGURAÇÃO DE CONTEXTO
-- ============================================================
-- Define o warehouse, banco de dados e schema ativos
-- para esta sessão.
-- ============================================================

USE WAREHOUSE olist_wh;   -- camada computacional para carga de dados
USE DATABASE olist_db;    -- banco de dados do projeto
USE SCHEMA raw;           -- schema de destino para os dados brutos

-- ============================================================
-- CARGA 1: CUSTOMERS
-- ============================================================
-- Carrega os dados cadastrais dos clientes.
-- Linhas esperadas: ~99.441
-- ============================================================

COPY INTO olist_db.raw.customers
FROM @olist_db.raw.raw_stage/olist_customers_dataset.csv
FILE_FORMAT = (TYPE = 'CSV' FIELD_OPTIONALLY_ENCLOSED_BY = '"' SKIP_HEADER = 1);

-- ============================================================
-- CARGA 2: GEOLOCATION
-- ============================================================
-- Carrega o mapeamento entre CEPs e coordenadas geográficas.
-- Linhas esperadas: ~1.000.163 — maior arquivo do dataset.
-- Pode levar um pouco mais de tempo devido ao volume.
-- ============================================================

COPY INTO olist_db.raw.geolocation
FROM @olist_db.raw.raw_stage/olist_geolocation_dataset.csv
FILE_FORMAT = (TYPE = 'CSV' FIELD_OPTIONALLY_ENCLOSED_BY = '"' SKIP_HEADER = 1);

-- ============================================================
-- CARGA 3: ORDER ITEMS
-- ============================================================
-- Carrega os dados dos itens dos pedidos, incluindo preço e frete.
-- Esta é a tabela mais importante para as análises de precificação.
-- Linhas esperadas: ~112.650
-- ============================================================

COPY INTO olist_db.raw.order_items
FROM @olist_db.raw.raw_stage/olist_order_items_dataset.csv
FILE_FORMAT = (TYPE = 'CSV' FIELD_OPTIONALLY_ENCLOSED_BY = '"' SKIP_HEADER = 1);

-- ============================================================
-- CARGA 4: ORDER PAYMENTS
-- ============================================================
-- Carrega os detalhes de pagamento dos pedidos.
-- Linhas esperadas: ~103.886
-- Observação: existem mais registros do que pedidos porque
-- um pedido pode possuir múltiplos pagamentos
-- (parcelamentos ou pagamentos divididos).
-- ============================================================

COPY INTO olist_db.raw.order_payments
FROM @olist_db.raw.raw_stage/olist_order_payments_dataset.csv
FILE_FORMAT = (TYPE = 'CSV' FIELD_OPTIONALLY_ENCLOSED_BY = '"' SKIP_HEADER = 1);

-- ============================================================
-- CARGA 5: ORDER REVIEWS
-- ============================================================
-- Carrega as avaliações de satisfação dos clientes.
-- Linhas esperadas: ~99.224
-- Observação: os campos de comentário possuem alta taxa de nulos,
-- o que é esperado.
-- ============================================================

COPY INTO olist_db.raw.order_reviews
FROM @olist_db.raw.raw_stage/olist_order_reviews_dataset.csv
FILE_FORMAT = (TYPE = 'CSV' FIELD_OPTIONALLY_ENCLOSED_BY = '"' SKIP_HEADER = 1);

-- ============================================================
-- CARGA 6: ORDERS
-- ============================================================
-- Carrega os dados principais dos pedidos.
-- Principal fonte transacional para construção do modelo analítico.
-- Linhas esperadas: ~99.441
-- ============================================================

COPY INTO olist_db.raw.orders
FROM @olist_db.raw.raw_stage/olist_orders_dataset.csv
FILE_FORMAT = (TYPE = 'CSV' FIELD_OPTIONALLY_ENCLOSED_BY = '"' SKIP_HEADER = 1);

-- ============================================================
-- CARGA 7: PRODUCTS
-- ============================================================
-- Carrega o catálogo de produtos com categorias e dimensões.
-- Linhas esperadas: ~32.951
-- Observação: existem 610 valores nulos em product_category_name.
-- O tratamento será realizado posteriormente na camada STAGING.
-- ============================================================

COPY INTO olist_db.raw.products
FROM @olist_db.raw.raw_stage/olist_products_dataset.csv
FILE_FORMAT = (TYPE = 'CSV' FIELD_OPTIONALLY_ENCLOSED_BY = '"' SKIP_HEADER = 1);

-- ============================================================
-- CARGA 8: SELLERS
-- ============================================================
-- Carrega os dados cadastrais dos vendedores.
-- Linhas esperadas: ~3.095
-- ============================================================

COPY INTO olist_db.raw.sellers
FROM @olist_db.raw.raw_stage/olist_sellers_dataset.csv
FILE_FORMAT = (TYPE = 'CSV' FIELD_OPTIONALLY_ENCLOSED_BY = '"' SKIP_HEADER = 1);

-- ============================================================
-- CARGA 9: CATEGORY TRANSLATION
-- ============================================================
-- Carrega o mapeamento de categorias do português para inglês.
-- Linhas esperadas: 71
-- Utilizado nas camadas STAGING e MARTS para padronização
-- dos nomes das categorias.
-- ============================================================

COPY INTO olist_db.raw.category_translation
FROM @olist_db.raw.raw_stage/product_category_name_translation.csv
FILE_FORMAT = (TYPE = 'CSV' FIELD_OPTIONALLY_ENCLOSED_BY = '"' SKIP_HEADER = 1);

-- ============================================================
-- VALIDAÇÃO
-- ============================================================
-- Confirma que todas as tabelas foram carregadas com as
-- quantidades esperadas de registros.
--------------------------------------

-- Resultados esperados:
--   customers:   99.441 registros
--   orders:      99.441 registros
--   order_items: 112.650 registros
--   products:    32.951 registros
----------------------------------

-- Diferenças significativas em relação aos volumes esperados
-- devem ser investigadas antes de prosseguir para a camada STAGING.
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
