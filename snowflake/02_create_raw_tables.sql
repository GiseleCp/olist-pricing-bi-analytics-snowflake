-- ============================================================
-- PROJETO: Olist Pricing Intelligence
-- ARQUIVO: 02_create_raw_tables.sql
-- DESCRIÇÃO: Cria todas as tabelas da camada RAW.
--             Todas as colunas são definidas como VARCHAR
--             intencionalmente — este é o padrão de Landing Zone.
--             Conversão de tipos e qualidade dos dados são
--             tratadas na camada STAGING.
--             O uso de CREATE OR REPLACE torna o script idempotente,
--             permitindo múltiplas execuções sem erros.
-- AUTORA: Gisele CP
-- DATA: 2026-06-06
-- ============================================================

-- PRINCÍPIOS DE MODELAGEM DA CAMADA RAW
-- 1. Todas as colunas são VARCHAR — preserva os dados exatamente como recebidos
-- 2. Sem constraints e sem chaves estrangeiras — dados brutos podem conter inconsistências
-- 3. Sem transformações — os dados de origem devem ser auditáveis
-- 4. CREATE OR REPLACE — idempotente e seguro para reexecução
-- 5. As tabelas refletem a estrutura dos arquivos CSV em uma relação 1:1

-- ============================================================
-- CONFIGURAÇÃO DE CONTEXTO
-- ============================================================
-- Define o warehouse, banco de dados e schema ativos
-- para esta sessão.
-- Todas as instruções subsequentes serão executadas
-- neste contexto.
-- ============================================================

USE WAREHOUSE olist_wh;   -- camada computacional para processamento de consultas
USE DATABASE olist_db;    -- contêiner principal de todos os objetos do projeto
USE SCHEMA raw;           -- schema de ingestão para dados brutos dos arquivos CSV


-- ============================================================
-- TABELA 1: CUSTOMERS
-- ============================================================
-- Armazena os dados cadastrais dos clientes.
-- customer_id: identificador em nível de transação (um por pedido)
-- customer_unique_id: identificador real do cliente ao longo do tempo
-- Observação: um customer_unique_id pode possuir múltiplos customer_ids
-- Fonte: olist_customers_dataset.csv | Linhas esperadas: ~99.441
-- ============================================================

CREATE OR REPLACE TABLE olist_db.raw.customers (
    customer_id VARCHAR,                -- identificador do cliente em nível de transação
    customer_unique_id VARCHAR,         -- identificador único do cliente em todos os pedidos
    customer_zip_code_prefix VARCHAR,   -- primeiros 5 dígitos do CEP
    customer_city VARCHAR,              -- cidade do cliente
    customer_state VARCHAR              -- sigla do estado (ex.: SP, RJ)
);

-- ============================================================
-- TABELA 2: GEOLOCATION
-- ============================================================
-- Relaciona CEPs brasileiros com coordenadas geográficas.
-- Utilizada para análises regionais de preços e índice de preços por região.
-- Contém latitude e longitude para análises geográficas e de distância.
-- Fonte: olist_geolocation_dataset.csv | Linhas esperadas: ~1.000.163
-- Observação: maior tabela do dataset — mais de 1 milhão de registros.
-- ============================================================

CREATE OR REPLACE TABLE olist_db.raw.geolocation (
    geolocation_zip_code_prefix VARCHAR,    -- primeiros 5 dígitos do CEP
    geolocation_lat VARCHAR,                -- latitude (armazenada como VARCHAR)
    geolocation_lng VARCHAR,                -- longitude (armazenada como VARCHAR)
    geolocation_city VARCHAR,               -- cidade associada ao CEP
    geolocation_state VARCHAR               -- sigla do estado associada ao CEP
);

-- ============================================================
-- TABELA 3: ORDER ITEMS
-- ============================================================
-- Tabela principal para análises de preço.
-- Contém preço e frete por item vendido.
-- Esta é a principal fonte para análises de:
-- markup, margem, proporção de frete e detecção de outliers de preço.
-- Um pedido pode conter múltiplos itens (sequência order_item_id).
-- Fonte: olist_order_items_dataset.csv | Linhas esperadas: ~112.650
-- ============================================================

CREATE OR REPLACE TABLE olist_db.raw.order_items (
    order_id VARCHAR,               -- chave estrangeira para a tabela orders
    order_item_id VARCHAR,          -- número sequencial do item dentro do pedido
    product_id VARCHAR,             -- chave estrangeira para a tabela products
    seller_id VARCHAR,              -- chave estrangeira para a tabela sellers
    shipping_limit_date VARCHAR,    -- prazo limite para envio pelo vendedor
    price VARCHAR,                  -- preço do item em BRL
    freight_value VARCHAR           -- valor do frete em BRL
);

-- ============================================================
-- TABELA 4: ORDER PAYMENTS
-- ============================================================
-- Contém os detalhes de pagamento por pedido.
-- Um pedido pode possuir múltiplos registros de pagamento
-- (parcelamentos).
-- Utilizada para análises de receita e segmentação por tipo
-- de pagamento.
-- Fonte: olist_order_payments_dataset.csv | Linhas esperadas: ~103.886
-- ============================================================

CREATE OR REPLACE TABLE olist_db.raw.order_payments (
    order_id             VARCHAR,   -- chave estrangeira para a tabela orders
    payment_sequential   VARCHAR,   -- sequência quando existem múltiplos pagamentos no pedido
    payment_type         VARCHAR,   -- credit_card, boleto, voucher, debit_card
    payment_installments VARCHAR,   -- quantidade de parcelas escolhida pelo cliente
    payment_value        VARCHAR    -- valor do pagamento em BRL
);

-- ============================================================
-- TABELA 5: ORDER REVIEWS
-- ============================================================
-- Dados de satisfação do cliente por pedido.
-- review_score é o principal campo — varia de 1 a 5 estrelas.
-- Utilizada para correlacionar preços com satisfação do cliente.
-- Observação: os campos de comentário possuem alta taxa de nulos
-- (~58-88%), o que é esperado, pois muitos clientes avaliam
-- o pedido sem deixar comentários escritos.
-- Fonte: olist_order_reviews_dataset.csv | Linhas esperadas: ~99.224
-- ============================================================

CREATE OR REPLACE TABLE olist_db.raw.order_reviews (
    review_id               VARCHAR,   -- identificador único da avaliação
    order_id                VARCHAR,   -- chave estrangeira para a tabela orders
    review_score            VARCHAR,   -- nota de satisfação de 1 a 5 estrelas
    review_comment_title    VARCHAR,   -- título opcional da avaliação (88% nulo)
    review_comment_message  VARCHAR,   -- mensagem opcional da avaliação (58% nulo)
    review_creation_date    VARCHAR,   -- data de criação da avaliação pelo sistema
    review_answer_timestamp VARCHAR    -- data em que o cliente enviou a avaliação
);

-- ============================================================
-- TABELA 6: ORDERS
-- ============================================================
-- Tabela mestre de pedidos — conecta todas as demais tabelas.
-- Principal tabela transacional utilizada na construção
-- do modelo dimensional da camada MARTS.
-- Contém os marcos temporais do ciclo de vida do pedido,
-- utilizados em análises de entrega.
-- Observação: order_delivered_customer_date possui 2.965 valores
-- nulos, o que é esperado para pedidos ainda não entregues
-- (em transporte ou processamento).
-- Fonte: olist_orders_dataset.csv | Linhas esperadas: ~99.441
-- ============================================================

CREATE OR REPLACE TABLE olist_db.raw.orders (
    order_id                      VARCHAR,   -- identificador único do pedido (chave primária)
    customer_id                   VARCHAR,   -- chave estrangeira para a tabela customers
    order_status                  VARCHAR,   -- delivered, shipped, canceled, etc.
    order_purchase_timestamp      VARCHAR,   -- momento em que o cliente realizou a compra
    order_approved_at             VARCHAR,   -- momento em que o pagamento foi aprovado
    order_delivered_carrier_date  VARCHAR,   -- momento em que o vendedor entregou ao transportador
    order_delivered_customer_date VARCHAR,   -- momento em que o cliente recebeu o pedido
    order_estimated_delivery_date VARCHAR    -- data estimada de entrega informada ao cliente
);


-- ============================================================
-- TABELA 7: PRODUCTS
-- ============================================================
-- Catálogo de produtos contendo categoria e dimensões físicas.
-- A categoria é fundamental para análises de segmentação de preços.
-- As dimensões físicas (peso e tamanho) impactam o cálculo do frete.
-- Observação: existem 610 valores nulos em product_category_name,
-- tratados na camada STAGING utilizando COALESCE como
-- 'uncategorized'.
-- Fonte: olist_products_dataset.csv | Linhas esperadas: ~32.951
-- ============================================================

CREATE OR REPLACE TABLE olist_db.raw.products (
    product_id                 VARCHAR,   -- identificador único do produto (chave primária)
    product_category_name      VARCHAR,   -- categoria do produto em português (610 nulos)
    product_name_lenght        VARCHAR,   -- quantidade de caracteres do nome do produto
    product_description_lenght VARCHAR,   -- quantidade de caracteres da descrição do produto
    product_photos_qty         VARCHAR,   -- quantidade de fotos do produto
    product_weight_g           VARCHAR,   -- peso do produto em gramas
    product_length_cm          VARCHAR,   -- comprimento do produto em centímetros
    product_height_cm          VARCHAR,   -- altura do produto em centímetros
    product_width_cm           VARCHAR    -- largura do produto em centímetros
);

-- ============================================================
-- TABELA 8: SELLERS
-- ============================================================
-- Dados cadastrais dos vendedores com informações de localização.
-- Utilizada para análises de desempenho de vendedores e
-- precificação regional.
-- Fonte: olist_sellers_dataset.csv | Linhas esperadas: ~3.095
-- ============================================================

CREATE OR REPLACE TABLE olist_db.raw.sellers (
    seller_id              VARCHAR,   -- identificador único do vendedor (chave primária)
    seller_zip_code_prefix VARCHAR,   -- primeiros 5 dígitos do CEP do vendedor
    seller_city            VARCHAR,   -- cidade do vendedor
    seller_state           VARCHAR    -- sigla do estado do vendedor
);

-- ============================================================
-- TABELA 9: CATEGORY TRANSLATION
-- ============================================================
-- Mapeia categorias em português para seus equivalentes em inglês.
-- Utilizada para padronização de categorias em relatórios
-- internacionais e dashboards.
-- Fonte: product_category_name_translation.csv | Linhas esperadas: 71
-- ============================================================

CREATE OR REPLACE TABLE olist_db.raw.category_translation (
    product_category_name         VARCHAR,   -- nome da categoria em português
    product_category_name_english VARCHAR    -- nome da categoria em inglês
);

-- ============================================================
-- VALIDAÇÃO
-- ============================================================
-- Confirma que as 9 tabelas foram criadas com sucesso
-- no schema RAW.
-- Resultado esperado:
-- 9 tabelas listadas com 0 registros.
-- Os dados serão carregados na próxima etapa:
-- 03_load_raw_data.sql
-- ============================================================

SHOW TABLES IN SCHEMA olist_db.raw;
