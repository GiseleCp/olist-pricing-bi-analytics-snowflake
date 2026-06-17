-- ============================================================
-- PROJETO: Olist Pricing Intelligence
-- ARQUIVO: 04_data_profiling.sql
-- DESCRIÇÃO: Perfilamento abrangente de dados de todas as tabelas RAW.
--            Investiga qualidade dos dados, valores nulos, duplicatas,
--            faixas de preço, integridade referencial e padrões de
--            negócio para orientar as decisões de tratamento da
--            camada STAGING. Todas as constatações estão documentadas
--            como itens de ação para o 05_silver_etl.sql.
-- AUTOR: Gisele CP
-- DATA: 2026-06-06
-- ============================================================

-- VISÃO GERAL DO PERFILAMENTO DE DADOS
-- O Perfilamento de Dados é o processo de examinar dados brutos para 
-- entender sua estrutura, conteúdo, qualidade e relacionamentos antes 
-- da transformação. Um analista sênior nunca transforma dados sem 
-- antes realizar o perfilamento.
--
-- Este arquivo cobre 22 etapas de análise organizadas em 5 categorias:
--
-- VOLUME      -> Etapa 1        (contagem de registros por tabela)
-- NULOS       -> Etapas 2-9     (análise de nulos por tabela)
-- DUPLICADAS  -> Etapa 10       (unicidade de chaves primárias)
-- FAIXAS      -> Etapas 11-15   (distribuições de preço, status, pagamentos)
-- INTEGRIDADE -> Etapas 16-22   (integridade referencial, datas, outliers)
--
-- TÉCNICAS SQL UTILIZADAS:
-- UNION ALL              -> combina resultados de múltiplas consultas em uma só
-- Agregação Condicional (CASE WHEN dentro de COUNT/SUM) -> conta linhas que correspondem a uma condição
-- Funções de Janela (COUNT() OVER()) -> calcula totais sem colapsar linhas
-- CTE (cláusula WITH)    -> cria conjunto de resultados temporário nomeado para reutilização
-- NULLIF()               -> previne erros de divisão por zero
-- CAST()                 -> converte tipos VARCHAR para numérico/data

-- ============================================================
-- CONFIGURAÇÃO DE CONTEXTO
-- ============================================================
-- Define o warehouse, banco de dados e schema ativos para esta sessão.
-- ============================================================


USE WAREHOUSE olist_wh;    -- camada de processamento para execução de consultas
USE DATABASE olist_db;     -- banco de dados do projeto
USE SCHEMA raw;            -- schema contendo as tabelas fonte originais (raw)


-- ============================================================
-- ETAPA 1: CONTAGEM DE REGISTROS
-- ============================================================
-- Primeira etapa de qualquer perfilamento de dados — valida se todas 
-- as tabelas foram carregadas com o número esperado de registros.
-- Utiliza UNION ALL para combinar as contagens de todas as 9 tabelas 
-- em uma única consulta.
-- UNION ALL é preferível ao UNION porque não remove duplicatas, o 
-- que é mais rápido e correto aqui, uma vez que cada linha possui um 
-- nome de tabela diferente.
-- Total esperado: ~1,6 milhão de registros em todas as tabelas.
-- ============================================================

-- Seleciona o nome da tabela e conta os registros da tabela customers
SELECT 'customers' AS tabela, COUNT(*) AS total_registros FROM olist_db.raw.customers
-- Une os resultados da próxima consulta, mantendo todas as linhas
UNION ALL
-- Seleciona o nome da tabela e conta os registros da tabela geolocation
SELECT 'geolocation', COUNT(*) FROM olist_db.raw.geolocation
-- Une os resultados da próxima consulta, mantendo todas as linhas
UNION ALL
-- Seleciona o nome da tabela e conta os registros da tabela order_items
SELECT 'order_items', COUNT(*) FROM olist_db.raw.order_items
-- Une os resultados da próxima consulta, mantendo todas as linhas
UNION ALL
-- Seleciona o nome da tabela e conta os registros da tabela order_payments
SELECT 'order_payments', COUNT(*) FROM olist_db.raw.order_payments
-- Une os resultados da próxima consulta, mantendo todas as linhas
UNION ALL
-- Seleciona o nome da tabela e conta os registros da tabela order_reviews
SELECT 'order_reviews', COUNT(*) FROM olist_db.raw.order_reviews
-- Une os resultados da próxima consulta, mantendo todas as linhas
UNION ALL
-- Seleciona o nome da tabela e conta os registros da tabela orders
SELECT 'orders', COUNT(*) FROM olist_db.raw.orders
-- Une os resultados da próxima consulta, mantendo todas as linhas
UNION ALL
-- Seleciona o nome da tabela e conta os registros da tabela products
SELECT 'products', COUNT(*) FROM olist_db.raw.products
-- Une os resultados da próxima consulta, mantendo todas as linhas
UNION ALL
-- Seleciona o nome da tabela e conta os registros da tabela sellers
SELECT 'sellers', COUNT(*) FROM olist_db.raw.sellers
-- Une os resultados da próxima consulta, mantendo todas as linhas
UNION ALL
-- Seleciona o nome da tabela e conta os registros da tabela category_translation
SELECT 'category_translation', COUNT(*) FROM olist_db.raw.category_translation
-- Ordena o resultado final pela coluna 'tabela' em ordem alfabética
ORDER BY tabela;

-- CONCLUSÕES:
-- geolocation: 1.000.163 registros - maior tabela do dataset
-- customers e orders possuem a mesma quantidade de registros (99.441),
-- porém isso não significa uma relação 1:1 entre cliente e pedido.
-- A validação correta deve considerar customer_unique_id.
-- order_items possui mais registros que orders, indicando múltiplos itens por pedido.
-- products: 32.951 produtos únicos.


-- ========================
-- ETAPA 2: ANÁLISE DE NULOS - ORDER_ITEMS
-- ========================
-- Esta consulta verifica a integridade dos dados na tabela order_items,
-- calculando a taxa de preenchimento e identificando registros nulos
-- em colunas críticas para o cálculo de preço e frete.

SELECT
    COUNT(*) AS total,                               -- Contagem total de linhas na tabela
    COUNT(order_id) AS order_id_preenchido,          -- Verifica valores não nulos (chaves estrangeiras)
    COUNT(product_id) AS product_id_preenchido,      -- Valida preenchimento dos produtos
    COUNT(price) AS price_preenchido,                -- Valida preenchimento dos preços
    COUNT(freight_value) AS freight_preenchido,      -- Valida preenchimento dos valores de frete
    SUM(CASE WHEN price IS NULL THEN 1 ELSE 0 END) AS price_nulo,      -- Agregação condicional para detectar falhas no preço
    SUM(CASE WHEN freight_value IS NULL THEN 1 ELSE 0 END) AS freight_nulo -- Agregação condicional para detectar falhas no frete
FROM olist_db.raw.order_items;

-- CONCLUSÕES:
-- order_items: 112.650 registros, sem valores nulos
-- price e freight_value possuem preenchimento de 100%
-- tabela íntegra e pronta para análises de precificação


-- ========================
-- ETAPA 3: ANÁLISE DE NULOS - CUSTOMERS
-- ========================

-- Conta o total de registros na tabela de clientes
SELECT COUNT(*) AS total,
-- Verifica se existem valores nulos na coluna de ID do cliente
SUM(CASE WHEN customer_id IS NULL THEN 1 ELSE 0 END) AS customer_id_nulo,
-- Verifica se existem valores nulos na coluna de ID único do cliente
SUM(CASE WHEN customer_unique_id IS NULL THEN 1 ELSE 0 END) AS unique_id_nulo,
-- Verifica se existem valores nulos na coluna de prefixo do código postal
SUM(CASE WHEN customer_zip_code_prefix IS NULL THEN 1 ELSE 0 END) AS zip_nulo,
-- Verifica se existem valores nulos na coluna da cidade do cliente
SUM(CASE WHEN customer_city IS NULL THEN 1 ELSE 0 END) AS city_nulo,
-- Verifica se existem valores nulos na coluna do estado do cliente
SUM(CASE WHEN customer_state IS NULL THEN 1 ELSE 0 END) AS state_nulo
-- Define a tabela de origem dos dados
FROM olist_db.raw.customers;

-- CONCLUSÕES:
-- customers: 99.441 registros, sem valores nulos
-- todos os campos apresentam preenchimento de 100%


-- ========================
-- ETAPA 4: ANÁLISE DE NULOS - GEOLOCATION
-- ========================

-- Conta o total de registros na tabela de geolocalização
SELECT COUNT(*) AS total,
-- Verifica se existem valores nulos no prefixo do código postal
SUM(CASE WHEN geolocation_zip_code_prefix IS NULL THEN 1 ELSE 0 END) AS zip_nulo,
-- Verifica se existem valores nulos na latitude
SUM(CASE WHEN geolocation_lat IS NULL THEN 1 ELSE 0 END) AS lat_nulo,
-- Verifica se existem valores nulos na longitude
SUM(CASE WHEN geolocation_lng IS NULL THEN 1 ELSE 0 END) AS lng_nulo,
-- Verifica se existem valores nulos no nome da cidade
SUM(CASE WHEN geolocation_city IS NULL THEN 1 ELSE 0 END) AS city_nulo,
-- Verifica se existem valores nulos no nome do estado
SUM(CASE WHEN geolocation_state IS NULL THEN 1 ELSE 0 END) AS state_nulo
-- Define a tabela de origem dos dados
FROM olist_db.raw.geolocation;

-- CONCLUSÕES:
-- geolocation: 1.000.163 registros, sem valores nulos
-- todos os campos apresentam preenchimento de 100%


-- ========================
-- ETAPA 5: ANÁLISE DE NULOS - ORDER_PAYMENTS
-- ========================

-- Conta o total de registros na tabela de pagamentos de pedidos
SELECT COUNT(*) AS total,
-- Verifica se existem valores nulos no ID do pedido
SUM(CASE WHEN order_id IS NULL THEN 1 ELSE 0 END) AS order_id_nulo,
-- Verifica se existem valores nulos na sequência de pagamento
SUM(CASE WHEN payment_sequential IS NULL THEN 1 ELSE 0 END) AS sequential_nulo,
-- Verifica se existem valores nulos no tipo de pagamento
SUM(CASE WHEN payment_type IS NULL THEN 1 ELSE 0 END) AS type_nulo,
-- Verifica se existem valores nulos na quantidade de parcelas
SUM(CASE WHEN payment_installments IS NULL THEN 1 ELSE 0 END) AS installments_nulo,
-- Verifica se existem valores nulos no valor do pagamento
SUM(CASE WHEN payment_value IS NULL THEN 1 ELSE 0 END) AS value_nulo
-- Define a tabela de origem dos dados
FROM olist_db.raw.order_payments;

-- CONCLUSÕES:
-- order_payments: 103.886 registros, sem valores nulos
-- todos os campos apresentam preenchimento de 100%


-- ========================
-- ETAPA 6: ANÁLISE DE NULOS - ORDER_REVIEWS
-- ========================

-- Conta o total de registros na tabela de avaliações de pedidos
SELECT COUNT(*) AS total,
-- Verifica se existem valores nulos no ID da avaliação
SUM(CASE WHEN review_id IS NULL THEN 1 ELSE 0 END) AS review_id_nulo,
-- Verifica se existem valores nulos no ID do pedido
SUM(CASE WHEN order_id IS NULL THEN 1 ELSE 0 END) AS order_id_nulo,
-- Verifica se existem valores nulos na pontuação (score)
SUM(CASE WHEN review_score IS NULL THEN 1 ELSE 0 END) AS score_nulo,
-- Verifica se existem valores nulos no título do comentário
SUM(CASE WHEN review_comment_title IS NULL THEN 1 ELSE 0 END) AS title_nulo,
-- Verifica se existem valores nulos na mensagem do comentário
SUM(CASE WHEN review_comment_message IS NULL THEN 1 ELSE 0 END) AS message_nulo,
-- Verifica se existem valores nulos na data de criação da avaliação
SUM(CASE WHEN review_creation_date IS NULL THEN 1 ELSE 0 END) AS creation_date_nulo,
-- Verifica se existem valores nulos na data de resposta da avaliação
SUM(CASE WHEN review_answer_timestamp IS NULL THEN 1 ELSE 0 END) AS answer_date_nulo
-- Define a tabela de origem dos dados
FROM olist_db.raw.order_reviews;

-- CONCLUSÕES:
-- order_reviews: 99.224 registros
-- review_comment_title: 87.656 nulos (88%) - esperado por ser campo opcional
-- review_comment_message: 58.247 nulos (59%) - esperado por ser campo opcional
-- review_score possui preenchimento de 100% e está apto para análises
-- ação: substituir comentários nulos por 'sem comentário' na camada STAGING


-- ========================
-- ETAPA 7: ANÁLISE DE NULOS - SELLERS
-- ========================

-- Conta o total de registros na tabela de vendedores
SELECT COUNT(*) AS total,
-- Verifica se existem valores nulos no ID do vendedor
SUM(CASE WHEN seller_id IS NULL THEN 1 ELSE 0 END) AS seller_id_nulo,
-- Verifica se existem valores nulos no prefixo do código postal do vendedor
SUM(CASE WHEN seller_zip_code_prefix IS NULL THEN 1 ELSE 0 END) AS zip_nulo,
-- Verifica se existem valores nulos na cidade do vendedor
SUM(CASE WHEN seller_city IS NULL THEN 1 ELSE 0 END) AS city_nulo,
-- Verifica se existem valores nulos no estado do vendedor
SUM(CASE WHEN seller_state IS NULL THEN 1 ELSE 0 END) AS state_nulo
-- Define a tabela de origem dos dados
FROM olist_db.raw.sellers;

-- CONCLUSÕES:
-- sellers: 3.095 registros, sem valores nulos
-- todos os campos apresentam preenchimento de 100%


-- ========================
-- ETAPA 8: ANÁLISE DE NULOS - ORDERS
-- ========================

-- Conta o total de registros na tabela de pedidos
SELECT COUNT(*) AS total,
-- Verifica se existem valores nulos no ID do pedido
SUM(CASE WHEN order_id IS NULL THEN 1 ELSE 0 END) AS order_id_nulo,
-- Verifica se existem valores nulos no ID do cliente
SUM(CASE WHEN customer_id IS NULL THEN 1 ELSE 0 END) AS customer_id_nulo,
-- Verifica se existem valores nulos no status do pedido
SUM(CASE WHEN order_status IS NULL THEN 1 ELSE 0 END) AS status_nulo,
-- Verifica se existem valores nulos na data de compra
SUM(CASE WHEN order_purchase_timestamp IS NULL THEN 1 ELSE 0 END) AS purchase_date_nulo,
-- Verifica se existem valores nulos na data de entrega ao cliente
SUM(CASE WHEN order_delivered_customer_date IS NULL THEN 1 ELSE 0 END) AS delivered_date_nulo,
-- Verifica se existem valores nulos na data estimada de entrega
SUM(CASE WHEN order_estimated_delivery_date IS NULL THEN 1 ELSE 0 END) AS estimated_date_nulo
-- Define a tabela de origem dos dados
FROM olist_db.raw.orders;

-- CONCLUSÕES:
-- orders: 99.441 registros
-- order_delivered_customer_date: 2.965 nulos - esperado para pedidos não entregues
-- todos os demais campos apresentam preenchimento completo


-- ========================
-- ETAPA 9: ANÁLISE DE NULOS - PRODUCTS
-- ========================

-- Conta o total de registros na tabela de produtos
SELECT COUNT(*) AS total,
-- Verifica se existem valores nulos no ID do produto
SUM(CASE WHEN product_id IS NULL THEN 1 ELSE 0 END) AS product_id_nulo,
-- Verifica se existem valores nulos no nome da categoria do produto
SUM(CASE WHEN product_category_name IS NULL THEN 1 ELSE 0 END) AS category_nulo,
-- Verifica se existem valores nulos no peso do produto (em gramas)
SUM(CASE WHEN product_weight_g IS NULL THEN 1 ELSE 0 END) AS weight_nulo,
-- Verifica se existem valores nulos no comprimento do produto (em centímetros)
SUM(CASE WHEN product_length_cm IS NULL THEN 1 ELSE 0 END) AS length_nulo,
-- Verifica se existem valores nulos na altura do produto (em centímetros)
SUM(CASE WHEN product_height_cm IS NULL THEN 1 ELSE 0 END) AS height_nulo,
-- Verifica se existem valores nulos na largura do produto (em centímetros)
SUM(CASE WHEN product_width_cm IS NULL THEN 1 ELSE 0 END) AS width_nulo
-- Define a tabela de origem dos dados
FROM olist_db.raw.products;

-- CONCLUSÕES:
-- products: 32.951 registros
-- product_category_name: 610 nulos - produtos sem categoria definida
-- peso e dimensões apresentam apenas 2 nulos por campo
-- ação: preencher categorias nulas com 'uncategorized' na camada STAGING


-- ========================
-- ETAPA 10: ANÁLISE DE DUPLICADAS
-- ========================

-- Seleciona a tabela de clientes e calcula o total de linhas vs. IDs únicos para identificar duplicatas
SELECT 'customers' AS tabela, COUNT(*) AS total, COUNT(DISTINCT customer_id) AS unique_ids, COUNT(*) - COUNT(DISTINCT customer_id) AS duplicatas FROM olist_db.raw.customers
-- Une os resultados das demais consultas abaixo
UNION ALL
-- Seleciona a tabela de pedidos e calcula a diferença entre o total e os IDs únicos
SELECT 'orders', COUNT(*), COUNT(DISTINCT order_id), COUNT(*) - COUNT(DISTINCT order_id) FROM olist_db.raw.orders
-- Une os resultados das demais consultas abaixo
UNION ALL
-- Seleciona a tabela de produtos e calcula a diferença entre o total e os IDs únicos
SELECT 'products', COUNT(*), COUNT(DISTINCT product_id), COUNT(*) - COUNT(DISTINCT product_id) FROM olist_db.raw.products
-- Une os resultados das demais consultas abaixo
UNION ALL
-- Seleciona a tabela de vendedores e calcula a diferença entre o total e os IDs únicos
SELECT 'sellers', COUNT(*), COUNT(DISTINCT seller_id), COUNT(*) - COUNT(DISTINCT seller_id) FROM olist_db.raw.sellers;

-- CONCLUSÕES:
-- customers: 99.441 registros, 0 duplicidades
-- orders: 99.441 registros, 0 duplicidades
-- products: 32.951 registros, 0 duplicidades
-- sellers: 3.095 registros, 0 duplicidades
-- todas as chaves analisadas são únicas e consistentes


-- ========================
-- ETAPA 11: ANÁLISE DE FAIXA DE PREÇO
-- ========================

-- Conta o total de registros na tabela de itens de pedido
SELECT COUNT(*) AS total,
-- Calcula o preço mínimo após converter a coluna para float
MIN(CAST(price AS FLOAT)) AS price_min,
-- Calcula o preço máximo após converter a coluna para float
MAX(CAST(price AS FLOAT)) AS price_max,
-- Calcula a média dos preços, arredondando para duas casas decimais
ROUND(AVG(CAST(price AS FLOAT)), 2) AS price_avg,
-- Calcula o desvio padrão dos preços para medir a dispersão
ROUND(STDDEV(CAST(price AS FLOAT)), 2) AS price_stddev,
-- Calcula o valor de frete mínimo após conversão
MIN(CAST(freight_value AS FLOAT)) AS freight_min,
-- Calcula o valor de frete máximo após conversão
MAX(CAST(freight_value AS FLOAT)) AS freight_max,
-- Calcula a média do frete, arredondando para duas casas decimais
ROUND(AVG(CAST(freight_value AS FLOAT)), 2) AS freight_avg,
-- Identifica quantos produtos possuem preço zero ou negativo
SUM(CASE WHEN CAST(price AS FLOAT) <= 0 THEN 1 ELSE 0 END) AS price_zero_negativo,
-- Identifica quantos registros de frete possuem valores negativos
SUM(CASE WHEN CAST(freight_value AS FLOAT) < 0 THEN 1 ELSE 0 END) AS freight_negativo
-- Define a tabela de origem dos dados
FROM olist_db.raw.order_items;

-- CONCLUSÕES:
-- faixa de preços: R$ 0,85 a R$ 6.735,00
-- preço médio: R$ 120,65
-- desvio padrão: R$ 183,63, indicando elevada dispersão de preços
-- faixa de frete: R$ 0,00 a R$ 409,68
-- frete médio: R$ 19,99
-- nenhum preço negativo identificado
-- dados aptos para análises de precificação
-- ação: segmentar análises por categoria de produto


-- ========================
-- ETAPA 12: DISTRIBUIÇÃO DO STATUS DO PEDIDO
-- ========================

-- Seleciona o status do pedido para agrupamento
SELECT order_status,
-- Conta o número de pedidos para cada status
COUNT(*) AS total,
-- Calcula o percentual de cada status em relação ao total, usando função de janela para somar o total global
ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER(), 2) AS percentual
-- Agrupa os resultados pela coluna de status
FROM olist_db.raw.orders
GROUP BY order_status
-- Ordena os resultados para mostrar os status mais frequentes primeiro
ORDER BY total DESC;

-- CONCLUSÕES:
-- 97,02% dos pedidos foram entregues
-- 0,63% dos pedidos foram cancelados
-- pedidos cancelados e indisponíveis devem ser excluídos das análises de preço
-- ação: filtrar order_status = 'delivered' na camada STAGING


-- ========================
-- ETAPA 13: DISTRIBUIÇÃO DOS TIPOS DE PAGAMENTO
-- ========================

-- Seleciona o tipo de pagamento para categorização
SELECT payment_type,
-- Conta a quantidade de transações por tipo de pagamento
COUNT(*) AS total,
-- Calcula o percentual de ocorrência de cada tipo em relação ao total de transações
ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER(), 2) AS percentual,
-- Calcula o valor médio da transação convertendo para float
ROUND(AVG(CAST(payment_value AS FLOAT)), 2) AS avg_payment_value,
-- Calcula o valor total de receita (soma) por tipo de pagamento
ROUND(SUM(CAST(payment_value AS FLOAT)), 2) AS total_revenue
-- Define a tabela de origem dos pagamentos
FROM olist_db.raw.order_payments
-- Agrupa os resultados pelo tipo de pagamento
GROUP BY payment_type
-- Ordena pela maior quantidade de transações
ORDER BY total DESC;

-- CONCLUSÕES:
-- credit_card representa 73,92% dos pagamentos e possui maior ticket médio
-- boleto representa 19,04% dos pagamentos
-- voucher apresenta ticket médio significativamente menor
-- not_defined possui apenas 3 registros
-- ação: utilizar payment_type como variável de segmentação


-- ========================
-- ETAPA 14: RECEITA POR CATEGORIA DE PRODUTO
-- ========================

-- Seleciona a categoria do produto (tabela products)
SELECT p.product_category_name,
-- Conta a quantidade de pedidos distintos (tabela order_items)
COUNT(DISTINCT oi.order_id) AS total_orders,
-- Conta o total de itens vendidos (tabela order_items)
COUNT(oi.order_item_id) AS total_items,
-- Calcula o preço médio dos produtos por categoria (conversão para float)
ROUND(AVG(CAST(oi.price AS FLOAT)), 2) AS avg_price,
-- Identifica o menor preço unitário na categoria
ROUND(MIN(CAST(oi.price AS FLOAT)), 2) AS min_price,
-- Identifica o maior preço unitário na categoria
ROUND(MAX(CAST(oi.price AS FLOAT)), 2) AS max_price,
-- Calcula a receita total por categoria (soma do preço dos itens)
ROUND(SUM(CAST(oi.price AS FLOAT)), 2) AS total_revenue,
-- Calcula o custo de frete médio para a categoria
ROUND(AVG(CAST(oi.freight_value AS FLOAT)), 2) AS avg_freight
-- Define a tabela de origem dos itens como alias 'oi'
FROM olist_db.raw.order_items oi
-- Faz a junção com a tabela de produtos usando o ID do produto
LEFT JOIN olist_db.raw.products p ON oi.product_id = p.product_id
-- Agrupa os indicadores pelo nome da categoria
GROUP BY p.product_category_name
-- Ordena pela categoria que gerou mais receita total
ORDER BY total_revenue DESC
-- Limita aos 20 principais registros para visualização
LIMIT 20;

-- CONCLUSÕES:
-- Categoria com maior faturamento: beleza_saude (R$ 1.258.681)
-- Maior preço médio: pcs (R$ 1.098), indicando produtos de alto valor e baixo volume
-- Categorias com maior frete médio: pcs (R$ 48) e moveis_escritorio (R$ 40)
-- Preço mínimo potencialmente atípico em beleza_saude (R$ 1,20)
-- utilidades_domesticas apresenta elevada dispersão de preços
-- (R$ 3,06 a R$ 6.735,00)
-- ação: analisar outliers de preço por categoria na etapa 22
-- ação: incluir frete nos cálculos de margem, especialmente em pcs e moveis_escritorio


-- ========================
-- ETAPA 15: ANÁLISE DA RAZÃO FRETE/PREÇO
-- ========================

-- Seleciona a categoria do produto (tabela products)
SELECT p.product_category_name,
-- Conta o total de itens vendidos na categoria
COUNT(oi.order_item_id) AS total_items,
-- Calcula o preço médio do item (conversão para float)
ROUND(AVG(CAST(oi.price AS FLOAT)), 2) AS avg_price,
-- Calcula o valor médio do frete para a categoria
ROUND(AVG(CAST(oi.freight_value AS FLOAT)), 2) AS avg_freight,
-- Calcula a proporção percentual do frete sobre o preço, usando NULLIF para evitar divisão por zero
ROUND(AVG(CAST(oi.freight_value AS FLOAT)) / 
        NULLIF(AVG(CAST(oi.price AS FLOAT)), 0) * 100, 2) AS freight_price_ratio_pct
-- Define a tabela de origem dos itens como alias 'oi'
FROM olist_db.raw.order_items oi
-- Faz a junção com a tabela de produtos
LEFT JOIN olist_db.raw.products p ON oi.product_id = p.product_id
-- Agrupa os indicadores pelo nome da categoria
GROUP BY p.product_category_name
-- Ordena pela maior proporção de frete em relação ao preço
ORDER BY freight_price_ratio_pct DESC
-- Limita aos 20 casos onde o frete é mais significativo proporcionalmente
LIMIT 20;

--  FINDINGS (CONSTATAÇÕES):
--  1. 'casa_conforto_2': Proporção de 53.97%. O frete supera metade do preço do produto.
--  2. 'flores': Proporção de 44.04%. O frete elevado sobre um produto de baixo preço 
--     sugere margem de contribuição possivelmente negativa.
--  3. 'moveis' e 'eletronicos': Apresentam alta proporção, correlacionada ao maior 
--     peso e dimensões dos produtos.
--  4. Categorias com proporção > 30% são candidatas prioritárias para ajuste de preço.

-- ACTIONS (AÇÕES SUGERIDAS):
-- AÇÃO 01: Incluir o custo do frete no cálculo de margem para todas as categorias.
-- AÇÃO 02: Criar flag (alerta) para categorias com razão frete/preço > 25% 
-- nas recomendações de precificação (Pricing Engine).



-- ========================
-- ETAPA 16: ANÁLISE DE INTEGRIDADE REFERENCIAL
-- ========================

-- Identifica registros órfãos entre itens de pedido e pedidos principais
SELECT 'order_items -> orders' AS relacionamento, COUNT(*) AS registros_orfaos
FROM olist_db.raw.order_items oi
LEFT JOIN olist_db.raw.orders o ON oi.order_id = o.order_id
WHERE o.order_id IS NULL -- Filtra apenas o que não encontrou par na tabela destino

UNION ALL

-- Verifica se há itens de pedido vinculados a produtos inexistentes
SELECT 'order_items -> products', COUNT(*)
FROM olist_db.raw.order_items oi
LEFT JOIN olist_db.raw.products p ON oi.product_id = p.product_id
WHERE p.product_id IS NULL

UNION ALL

-- Verifica se há itens de pedido vinculados a vendedores inexistentes
SELECT 'order_items -> sellers', COUNT(*)
FROM olist_db.raw.order_items oi
LEFT JOIN olist_db.raw.sellers s ON oi.seller_id = s.seller_id
WHERE s.seller_id IS NULL

UNION ALL

-- Verifica pagamentos que não possuem um pedido correspondente
SELECT 'order_payments -> orders', COUNT(*)
FROM olist_db.raw.order_payments op
LEFT JOIN olist_db.raw.orders o ON op.order_id = o.order_id
WHERE o.order_id IS NULL

UNION ALL

-- Verifica avaliações de pedidos que não possuem um pedido correspondente
SELECT 'order_reviews -> orders', COUNT(*)
FROM olist_db.raw.order_reviews ore
LEFT JOIN olist_db.raw.orders o ON ore.order_id = o.order_id
WHERE o.order_id IS NULL

UNION ALL

-- Verifica pedidos vinculados a clientes que não existem na tabela de clientes
SELECT 'orders -> customers', COUNT(*)
FROM olist_db.raw.orders o
LEFT JOIN olist_db.raw.customers c ON o.customer_id = c.customer_id
WHERE c.customer_id IS NULL;

-- AUDITORIA DE CONSISTÊNCIA:
-- 'order_items -> orders': 0 órfãos (Relacionamento entre itens e pedidos íntegro)
-- 'order_items -> products': 0 órfãos (Todos os itens possuem produtos válidos)
-- 'order_items -> sellers': 0 órfãos (Todos os itens possuem vendedores válidos)
-- 'order_payments -> orders': 0 órfãos (Pagamentos vinculados corretamente a pedidos)
-- 'order_reviews -> orders': 0 órfãos (Avaliações vinculadas corretamente a pedidos)
-- 'orders -> customers': 0 órfãos (Pedidos vinculados a clientes existentes)

-- STATUS FINAL:
-- Integridade referencial: 100% consistente.
-- Conclusão: O dataset está validado e pronto para a modelagem em STAR SCHEMA.


-- ========================
-- ETAPA 17: VALIDAÇÃO DE INTERVALO DE DATAS (TEMPORAL)
-- ========================

-- Identifica o marco inicial e final, e verifica anomalias cronológicas nas datas de pedido
SELECT 
-- Data da primeira compra registrada
MIN(CAST(order_purchase_timestamp AS TIMESTAMP)) AS first_order,
-- Data da última compra registrada
MAX(CAST(order_purchase_timestamp AS TIMESTAMP)) AS last_order,
-- Conta registros com data de compra no futuro (potencial erro de sistema/inserção)
COUNT(CASE WHEN CAST(order_purchase_timestamp AS TIMESTAMP) > CURRENT_TIMESTAMP() 
          THEN 1 END) AS future_dates,
-- Conta registros onde a data de entrega é anterior à data de compra (erro lógico)
COUNT(CASE WHEN CAST(order_delivered_customer_date AS TIMESTAMP) < 
             CAST(order_purchase_timestamp AS TIMESTAMP) 
          THEN 1 END) AS delivered_before_purchase,
-- Conta registros onde a data de aprovação é anterior à data de compra (erro lógico)
COUNT(CASE WHEN CAST(order_approved_at AS TIMESTAMP) < 
             CAST(order_purchase_timestamp AS TIMESTAMP) 
          THEN 1 END) AS approved_before_purchase
-- Define a tabela de origem dos dados
FROM olist_db.raw.orders;

-- AUDITORIA CRONOLÓGICA:
-- Intervalo de datas: 2016-09-04 a 2018-10-17 (abrangência de ~2 anos).
-- Futuro: 0 registros (nenhum dado com data superior ao tempo atual).
-- Entrega antes da compra: 0 registros (consistência lógica confirmada).
-- Aprovação antes da compra: 0 registros (ordem cronológica validada).

-- STATUS FINAL:
-- O intervalo de tempo é suficiente para análises de sazonalidade e tendências de preço.
-- A integridade temporal está garantida para análises de performance e séries temporais.



-- ========================
-- ETAPA 18: VALIDAÇÃO DE GEOLOCALIZAÇÃO
-- ========================

-- Conta registros e verifica a consistência geográfica das coordenadas e siglas de estados
SELECT 
-- Total de registros na tabela de geolocalização
COUNT(*) AS total,
-- Quantidade de estados distintos presentes
COUNT(DISTINCT geolocation_state) AS total_states,
-- Quantidade de cidades distintas presentes
COUNT(DISTINCT geolocation_city) AS total_cities,
-- Identifica latidudes fora do limite geográfico do Brasil (aprox. 5.27° N a 33.75° S)
SUM(CASE WHEN CAST(geolocation_lat AS FLOAT) > 5.27 
             OR CAST(geolocation_lat AS FLOAT) < -33.75 
             THEN 1 END) AS invalid_lat,
-- Identifica longitudes fora do limite geográfico do Brasil (aprox. 34.79° W a 73.98° W)
SUM(CASE WHEN CAST(geolocation_lng AS FLOAT) > -34.79 
             OR CAST(geolocation_lng AS FLOAT) < -73.98 
             THEN 1 END) AS invalid_lng,
-- Valida se a sigla do estado pertence à lista oficial de 27 unidades federativas brasileiras
SUM(CASE WHEN geolocation_state NOT IN (
        'AC','AL','AM','AP','BA','CE','DF','ES','GO',
        'MA','MG','MS','MT','PA','PB','PE','PI','PR',
        'RJ','RN','RO','RR','RS','SC','SE','SP','TO')
        THEN 1 END) AS invalid_states
-- Define a tabela de origem
FROM olist_db.raw.geolocation;


-- ========================
-- ETAPA 19: ANÁLISE DE DISTRIBUIÇÃO DAS AVALIAÇÕES
-- ========================

-- Seleciona a pontuação da avaliação
SELECT ore.review_score,
-- Conta o total de avaliações por nota
COUNT(*) AS total,
-- Calcula o percentual de cada nota em relação ao total de avaliações (usando janela)
ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER(), 2) AS percentual,
-- Calcula o preço médio dos produtos associados a cada nota
ROUND(AVG(CAST(oi.price AS FLOAT)), 2) AS avg_price,
-- Calcula o valor médio do frete associado a cada nota
ROUND(AVG(CAST(oi.freight_value AS FLOAT)), 2) AS avg_freight
-- Define a tabela de avaliações como origem
FROM olist_db.raw.order_reviews ore
-- Faz o join com itens de pedido para acessar dados de preço e frete
LEFT JOIN olist_db.raw.order_items oi ON ore.order_id = oi.order_id
-- Agrupa pela nota da avaliação
GROUP BY ore.review_score
-- Ordena da maior para a menor nota
ORDER BY ore.review_score DESC;

-- FINDINGS (CONSTATAÇÕES):
-- 56.21% das avaliações são 5 estrelas: alta satisfação geral.
-- Score 1 apresenta o ticket médio mais alto (R$ 127.35): produtos caros geram maior nível de insatisfação (expectativa vs. realidade).
-- Score 3 possui o ticket médio mais baixo (R$ 110.06): produtos de entrada/intermediários são bem precificados.
-- Frete: Correlação positiva observada entre fretes mais altos e notas mais baixas.

-- ACTIONS (AÇÕES SUGERIDAS):
-- AÇÃO 01: Incluir 'review_score' como variável explicativa no modelo de precificação.
-- AÇÃO 02: Criar flag de monitoramento para produtos com ticket alto e 'review_score' baixo (análise de revisão de preço/qualidade).


-- ========================
-- ETAPA 20: ANÁLISE DOS PRINCIPAIS VENDEDORES (TOP SELLERS)
-- ========================

-- Seleciona dados do vendedor e agrega métricas de performance de vendas
SELECT s.seller_id, s.seller_city, s.seller_state,
-- Conta total de pedidos distintos associados ao vendedor
COUNT(DISTINCT oi.order_id) AS total_orders,
-- Conta o volume total de itens vendidos
COUNT(oi.order_item_id) AS total_items,
-- Soma a receita gerada pelo vendedor
ROUND(SUM(CAST(oi.price AS FLOAT)), 2) AS total_revenue,
-- Calcula o ticket médio por item vendido pelo vendedor
ROUND(AVG(CAST(oi.price AS FLOAT)), 2) AS avg_price,
-- Calcula a participação percentual deste vendedor na receita total global
ROUND(SUM(CAST(oi.price AS FLOAT)) * 100.0 / 
        SUM(SUM(CAST(oi.price AS FLOAT))) OVER(), 2) AS revenue_share_pct
-- Define a tabela de vendedores como base
FROM olist_db.raw.sellers s
-- Join com itens de pedido para buscar dados de vendas
LEFT JOIN olist_db.raw.order_items oi ON s.seller_id = oi.seller_id
-- Agrupa pelos dados do vendedor
GROUP BY s.seller_id, s.seller_city, s.seller_state
-- Ordena pela maior receita acumulada
ORDER BY total_revenue DESC
-- Foca nos 20 maiores vendedores
LIMIT 20;

-- FINDINGS (CONSTATAÇÕES):
-- Top seller: Localizado em Guariba/SP, com receita de R$ 229.472.
-- Estratégia Premium: Vendedores em Lauro de Freitas/BA possuem o maior ticket médio (R$ 543).
-- Concentração: Observada alta densidade de vendedores no estado de São Paulo.
-- Pareto: Os top 20 vendedores representam aproximadamente 18% da receita total.

-- ACTIONS (AÇÕES SUGERIDAS):
-- AÇÃO 01: Analisar a estratégia de precificação e mix de produtos por concentração geográfica (Silver Layer).
-- AÇÃO 02: Segmentar vendedores por "Performance de Vendas" para identificar padrões de sucesso.


-- ========================
-- ETAPA 21: ANÁLISE DE PRODUTOS SEM CATEGORIA
-- ========================

-- Calcula métricas de impacto para produtos que possuem categoria indefinida
SELECT 
-- Total de produtos no catálogo (tabela products)
COUNT(*) AS total_products,
-- Contagem de produtos sem nome de categoria atribuído
SUM(CASE WHEN product_category_name IS NULL 
        THEN 1 ELSE 0 END) AS no_category,
-- Percentual de representatividade dos produtos sem categoria
ROUND(SUM(CASE WHEN product_category_name IS NULL 
        THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 2) AS no_category_pct,
-- Preço médio dos produtos sem categoria
ROUND(AVG(CASE WHEN product_category_name IS NULL 
        THEN CAST(oi.price AS FLOAT) END), 2) AS avg_price_no_category,
-- Preço médio dos produtos com categoria (para comparação)
ROUND(AVG(CASE WHEN product_category_name IS NOT NULL 
        THEN CAST(oi.price AS FLOAT) END), 2) AS avg_price_with_category,
-- Total de itens vendidos que pertencem a produtos sem categoria
SUM(CASE WHEN product_category_name IS NULL 
        THEN 1 ELSE 0 END) AS total_items_no_category,
-- Receita total gerada por itens sem categoria atribuída
ROUND(SUM(CASE WHEN product_category_name IS NULL 
        THEN CAST(oi.price AS FLOAT) ELSE 0 END), 2) AS revenue_no_category
-- Define a tabela de produtos como base
FROM olist_db.raw.products p
-- Join com itens de pedido para capturar o preço de venda real
LEFT JOIN olist_db.raw.order_items oi ON p.product_id = oi.product_id;

-- FINDINGS (CONSTATAÇÕES):
-- Foram identificados 1.603 itens sem categoria, representando 1,42% dos produtos analisados.
-- Esses itens somam aproximadamente R$ 179.535 em receita potencialmente excluída de análises segmentadas por categoria.
-- O preço médio dos produtos sem categoria é de R$ 112,00, enquanto produtos categorizados apresentam média de R$ 120,78.
-- Embora a representatividade seja relativamente baixa, a ausência de categorização gera perda de visibilidade analítica e pode distorcer indicadores por categoria.

-- ACTIONS (AÇÕES SUGERIDAS):
-- AÇÃO 01: Investigar a origem dos registros sem categoria na camada RAW.
-- AÇÃO 02: Implementar tratamento na camada STAGING atribuindo a categoria 'uncategorized' para evitar perda de registros nas análises.
-- AÇÃO 03: Avaliar possibilidade de recategorização dos produtos utilizando descrição, nome ou regras de negócio.
-- AÇÃO 04: Monitorar periodicamente a ocorrência de produtos sem categoria como indicador de qualidade de dados.


-- ========================
-- ETAPA 22: IDENTIFICAÇÃO DE OUTLIERS DE PREÇO POR CATEGORIA
-- ========================

-- Utiliza uma CTE para calcular a média e desvio padrão por categoria antes da contagem final
WITH category_stats AS (
    SELECT 
        p.product_category_name,
        oi.order_item_id,
        CAST(oi.price AS FLOAT) AS price,
        -- Calcula a média da categoria usando Window Function
        AVG(CAST(oi.price AS FLOAT)) OVER(PARTITION BY p.product_category_name) AS avg_price,
        -- Calcula o desvio padrão da categoria para definir o intervalo de normalidade
        STDDEV(CAST(oi.price AS FLOAT)) OVER(PARTITION BY p.product_category_name) AS stddev_price
    FROM olist_db.raw.order_items oi
    LEFT JOIN olist_db.raw.products p ON oi.product_id = p.product_id
)
-- Consulta final para agregar os indicadores de outliers
SELECT 
    product_category_name,
    COUNT(order_item_id) AS total_items,
    ROUND(AVG(price), 2) AS avg_price,
    ROUND(AVG(stddev_price), 2) AS stddev_price,
    ROUND(MIN(price), 2) AS min_price,
    ROUND(MAX(price), 2) AS max_price,
    -- Define o limite inferior de preço (média - 2 desvios padrão)
    ROUND(AVG(price) - 2 * AVG(stddev_price), 2) AS lower_bound,
    -- Define o limite superior de preço (média + 2 desvios padrão)
    ROUND(AVG(price) + 2 * AVG(stddev_price), 2) AS upper_bound,
    -- Conta quantos itens estão acima do limite superior
    SUM(CASE WHEN price > avg_price + 2 * stddev_price THEN 1 ELSE 0 END) AS outliers_above,
    -- Conta quantos itens estão abaixo do limite inferior
    SUM(CASE WHEN price < avg_price - 2 * stddev_price THEN 1 ELSE 0 END) AS outliers_below
FROM category_stats
GROUP BY product_category_name
ORDER BY outliers_above DESC
LIMIT 20;

-- FINDINGS (CONSTATAÇÕES):
-- 1. Detecção de Preços Anômalos: Identificação de produtos cujo preço está 2 desvios padrão acima ou abaixo da média.
-- 2. beleza_saude: 395 outliers com preços elevados (maior concentração).
-- 3. moveis_decoracao: 291 outliers (alta dispersão de preços na categoria).
-- 4. relogios_presentes: Ticket médio de R$ 201 com limite superior de R$ 714 (característica de categoria premium).
-- 5. Limites Inferiores: Todos os limites calculados são negativos, indicando que não houve detecção de outliers de preço baixo com o método de 2 desvios padrão.
-- ACTIONS (AÇÕES SUGERIDAS):
-- AÇÃO 01: Auditar os produtos classificados como 'outliers_above' para diferenciar erros de cadastro de produtos de luxo.
-- AÇÃO 02: Aplicar o método IQR (Intervalo Interquartil) na Camada Silver para uma detecção de outliers mais robusta (especialmente para preços baixos).
-- AÇÃO 03: Marcar produtos identificados como 'outliers_above' para revisão de precificação na Camada Marts.





-- ============================================================
-- RESUMO DO PERFIL DE DADOS
-- PROJETO: Olist Pricing Intelligence
-- AUTOR: Gisele CP
-- DATA: 2026-06-06
-- ============================================================

-- VISÃO GERAL DO CONJUNTO DE DADOS
-- customers:            99.441 registros
-- geolocation:       1.000.163 registros
-- order_items:         112.650 registros
-- order_payments:      103.886 registros
-- order_reviews:        99.224 registros
-- orders:               99.441 registros
-- products:             32.951 registros
-- sellers:               3.095 registros
-- category_translation:     71 registros

-- ANÁLISE DE NULOS
-- order_items:    zero nulos - limpo para análise de precificação
-- customers:      zero nulos - limpo
-- geolocation:    zero nulos - limpo
-- order_payments: zero nulos - limpo
-- sellers:        zero nulos - limpo
-- orders:         2.965 nulos em delivered_date - esperado, pedidos não entregues
-- order_reviews:  87.656 nulos em comment_title, 58.247 em comment_message - esperado
-- products:       610 nulos em category_name, 2 nulos em dimensões

-- ANÁLISE DE DUPLICADAS
-- customers, orders, products, sellers: zero duplicadas
-- todas as chaves primárias únicas e válidas

-- ANÁLISE DE PREÇO
-- faixa de preço: R$ 0,85 a R$ 6.735
-- preço médio: R$ 120,65, desvio padrão: R$ 183,63 - alta dispersão
-- faixa de frete: R$ 0 a R$ 409,68, média: R$ 19,99
-- zero preços negativos ou zero

-- STATUS DO PEDIDO
-- 97,02% entregues, 0,63% cancelados
-- ação: filtrar pedidos entregues para análise de precificação

-- TIPOS DE PAGAMENTO
-- cartão de crédito: 73,92%, ticket médio R$ 163,32
-- boleto: 19,04%, ticket médio R$ 145,03
-- voucher: 5,56%, ticket médio R$ 65,70

-- PRINCIPAIS CATEGORIAS POR RECEITA
-- 1. beleza_saude:       R$ 1.258.681
-- 2. relogios_presentes: R$ 1.205.005
-- 3. cama_mesa_banho:    R$ 1.036.988

-- TAXA DE FRETE VS PREÇO
-- casa_conforto_2: 53,97% - crítico
-- flores: 44,04% - crítico
-- ação: marcar categorias com taxa acima de 25%

-- INTEGRIDADE REFERENCIAL
-- todos os relacionamentos 100% consistentes - zero registros órfãos

-- VALIDAÇÃO DE DATA
-- intervalo de datas: 2016-09-04 a 2018-10-17
-- zero datas inválidas ou futuras

-- VALIDAÇÃO DE GEOLOCALIZAÇÃO
-- 27 estados - cobertura nacional completa
-- 31 latitudes inválidas, 37 longitudes inválidas
-- ação: remover coordenadas inválidas na camada silver

-- PONTUAÇÃO DE AVALIAÇÃO
-- 56,21% pontuação 5 estrelas
-- nota 1 tem o maior preço médio R$ 127,35
-- ação: incluir pontuação de avaliação no modelo de precificação

-- PRINCIPAIS VENDEDORES
-- vendedor principal: guariba/SP R$ 229.472
-- forte concentração no estado de São Paulo

-- PRODUTOS SEM CATEGORIA
-- 1.603 itens (1,42%) sem categoria
-- R$ 179.535 de receita em risco
-- ação: atribuir "sem categoria" na camada silver

-- OUTLIERS DE PREÇO
-- beleza_saude: 395 outliers com preços elevados
-- moveis_decoracao: 291 outliers
-- todos os limites inferiores negativos - aplicar método IQR na camada silver

-- ITENS DE AÇÃO DA CAMADA SILVER
-- 1. filtrar order_status = entregue
-- 2. converter todos os campos numéricos de VARCHAR
-- 3. atribuir "sem categoria" para categorias nulas
-- 4. remover coordenadas de geolocalização inválidas
-- 5. tratar comentários de avaliação nulos como "sem comentário"
-- 6. aplicar método IQR para detecção de outliers
-- 7. calcular taxa de frete por categoria
-- 8. marcar produtos com nota de avaliação 1 e preço alto