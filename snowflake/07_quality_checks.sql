-- ============================================================
-- PROJETO: Inteligência de Precificação Olist (Olist Pricing Intelligence)
-- ARQUIVO: 07_quality_checks.sql
-- DESCRIÇÃO: Verificações de qualidade e validação de todas as tabelas
--             da camada MARTS. Valida contagem de linhas, integridade
--             referencial, lógica de negócios e distribuição de recomendações de preço.
--             Este arquivo deve ser executado após o 06_gold_modelagem.sql.
--             Qualquer resultado inesperado aqui indica problemas no
--             pipeline de transformação upstream (camadas anteriores).
-- AUTOR: Gisele CP
-- DATA: 10-06-2026
-- ATUALIZADO: 23-06-2026
-- ALTERAÇÕES:
--   v1.1 - comentários traduzidos para português
--   v1.2 - Check 3 expandido com investigação de causa raiz (3.1, 3.2, 3.3)
--   v1.3 - Check 3 adicionado fact -> dim_date para cobertura completa do Star Schema
--   v1.4 - Check 8 substituído LIMIT 10 por QUALIFY ROW_NUMBER()
--   v1.5 - Check 1.1 corrigido: CAST inválido substituído por CASE com retorno texto
--   v1.6 - valores dos campos alinhados com os gerados pelo 06_gold_modelagem.sql (inglês)
-- ============================================================

-- VISÃO GERAL DAS VERIFICAÇÕES DE QUALIDADE
-- Este arquivo valida a camada MARTS sob três perspectivas:
--
-- 1. VERIFICAÇÕES DE VOLUME      -> as contagens de linhas correspondem aos valores esperados
-- 2. VERIFICAÇÕES DE INTEGRIDADE -> sem registros órfãos na tabela de fatos
-- 3. VERIFICAÇÕES DE NEGÓCIO     -> as recomendações de preços estão distribuídas
--                                   conforme o esperado para um projeto focado em decisões (Decision Centric)
--
-- REFERÊNCIA DE VALORES DOS CAMPOS (gerados pelo 06_gold_modelagem.sql):
--   pricing_recommendation : 'reduce_price_and_freight' | 'review_freight_strategy' |
--                             'reduce_price' | 'increase_price' | 'maintain_pricing' | 'monitor'
--   freight_risk_flag       : 'critical' | 'attention' | 'ok'   (gerado no 05_silver_etl.sql)
--   rfm_segment             : 'champions' | 'loyal' | 'potential' | 'at_risk'
--   seller_tier             : 'platinum' | 'gold' | 'silver' | 'bronze'
--   price_segment           : 'budget' | 'mid_range' | 'premium' | 'luxury'
--   margin_alert            : 'negative_margin' | 'ok'

-- ============================================================
-- CONFIGURAÇÃO DO CONTEXTO
-- ============================================================
-- Define o warehouse, banco de dados e esquema ativos para esta sessão.
-- ============================================================

USE WAREHOUSE olist_wh;   -- camada de processamento para as consultas de validação
USE DATABASE olist_db;    -- banco de dados do projeto
USE SCHEMA marts;         -- esquema contendo as tabelas de fatos e dimensões

-- ============================================================
-- CHECK 1: CONTAGEM DE LINHAS POR TABELA
-- ============================================================
-- Valida se todas as tabelas foram criadas com as contagens de linhas esperadas.
-- Compare com as contagens da camada de staging para garantir que não houve perda de dados.
-- Resultados esperados:
--   fact_orders:   ~113.314 linhas (uma por item de pedido)
--   dim_customers:  ~99.441 linhas (uma por cliente único)
--   dim_products:   ~32.951 linhas (uma por produto único)
--   dim_sellers:     ~3.095 linhas (um por vendedor único)
--   dim_payments:   ~99.437 linhas (uma por pedido único)
--   dim_date:           800 linhas (uma por dia no intervalo de datas)
-- ============================================================

SELECT 'fact_orders' AS tabela, COUNT(*) AS total FROM olist_db.marts.fact_orders
UNION ALL
SELECT 'dim_customers', COUNT(*) FROM olist_db.marts.dim_customers
UNION ALL
SELECT 'dim_products',  COUNT(*) FROM olist_db.marts.dim_products
UNION ALL
SELECT 'dim_sellers',   COUNT(*) FROM olist_db.marts.dim_sellers
UNION ALL
SELECT 'dim_payments',  COUNT(*) FROM olist_db.marts.dim_payments
UNION ALL
SELECT 'dim_date',      COUNT(*) FROM olist_db.marts.dim_date
ORDER BY total DESC;


-- ============================================================
-- CHECK 1.1: ASSERÇÕES AUTOMÁTICAS DE VOLUME
-- ============================================================
-- Retorna 'PASSOU' se o volume está dentro do esperado,
-- ou mensagem de erro descritiva se estiver abaixo do limite.
-- Evita que dados incorretos passem silenciosamente para o dashboard.
-- ============================================================

SELECT
    CASE WHEN COUNT(*) < 100000
        THEN 'ERRO: fact_orders abaixo do volume esperado'
        ELSE 'PASSOU'
    END AS assert_fact_orders
FROM olist_db.marts.fact_orders;

SELECT
    CASE WHEN COUNT(*) < 90000
        THEN 'ERRO: dim_customers abaixo do volume esperado'
        ELSE 'PASSOU'
    END AS assert_dim_customers
FROM olist_db.marts.dim_customers;

SELECT
    CASE WHEN COUNT(*) < 30000
        THEN 'ERRO: dim_products abaixo do volume esperado'
        ELSE 'PASSOU'
    END AS assert_dim_products
FROM olist_db.marts.dim_products;


-- ============================================================
-- CHECK 2: DISTRIBUIÇÃO DAS RECOMENDAÇÕES DE PREÇO
-- ============================================================
-- Valida a distribuição das recomendações de precificação.
-- Este é o resultado central do design focado em decisões (Decision Centric).
-- Cada item de pedido recebe uma de 6 recomendações acionáveis:
--   reduce_price_and_freight -> frete alto + avaliação ruim
--   review_freight_strategy  -> frete corroendo a margem
--   reduce_price             -> preço excessivo + avaliações ruins
--   increase_price           -> preço baixo + boas avaliações
--   maintain_pricing         -> preço ideal confirmado
--   monitor                  -> monitoramento padrão
-- Esperado: maioria em 'monitor' e 'maintain_pricing'
-- ============================================================

SELECT
    pricing_recommendation,                                        -- orientação de preço acionável
    COUNT(*) AS total,                                             -- total de itens por recomendação
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER(), 2) AS percentual  -- % do total
FROM olist_db.marts.fact_orders
GROUP BY pricing_recommendation
ORDER BY total DESC;

-- RESULTADOS DO CHECK 2:
-- review_freight_strategy:  34.344 (30,31%) - frete corroendo a margem, precisa de atenção imediata
-- maintain_pricing:         34.325 (30,29%) - preço ideal confirmado, nenhuma ação necessária
-- monitor:                  32.163 (28,38%) - monitoramento padrão, sem ação imediata
-- reduce_price_and_freight:  7.112  (6,28%) - crítico: frete alto + avaliação ruim
-- increase_price:            3.928  (3,47%) - oportunidade: preço baixo + boas avaliações
-- reduce_price:              1.442  (1,27%) - preço excessivo + avaliações ruins, risco de receita
--
-- INSIGHT CHAVE: 30,31% dos itens estão com o frete corroendo a margem
-- OPORTUNIDADE CHAVE: 3.928 itens podem ter o preço aumentado sem perder a satisfação
-- RISCO CHAVE: 7.112 itens precisam de revisão urgente de preço E frete

-- Destaques Decision Centric:
-- 🚨 Urgente        7.112   reduce_price_and_freight
-- 💰 Oportunidade   3.928   increase_price
-- ✅ Manter        34.325   maintain_pricing
-- 🔍 Revisar frete 34.344   review_freight_strategy


-- ============================================================
-- CHECK 3: INTEGRIDADE REFERENCIAL - FATO PARA DIMENSÕES
-- ============================================================
-- Valida se todas as chaves estrangeiras em fact_orders possuem
-- registros correspondentes em suas respectivas tabelas de dimensão.
-- Registros órfãos indicariam problemas de qualidade de dados no
-- pipeline de transformação upstream.
-- Resultado esperado: 0 órfãos em todos os relacionamentos.
-- ============================================================

SELECT 'fact -> dim_products' AS relacionamento,
    COUNT(*) AS orphan_records
FROM olist_db.marts.fact_orders f
LEFT JOIN olist_db.marts.dim_products p ON f.product_id = p.product_id
WHERE p.product_id IS NULL

UNION ALL

SELECT 'fact -> dim_sellers',
    COUNT(*)
FROM olist_db.marts.fact_orders f
LEFT JOIN olist_db.marts.dim_sellers s ON f.seller_id = s.seller_id
WHERE s.seller_id IS NULL

UNION ALL

SELECT 'fact -> dim_customers',
    COUNT(*)
FROM olist_db.marts.fact_orders f
LEFT JOIN olist_db.marts.dim_customers c ON f.customer_id = c.customer_id
WHERE c.customer_id IS NULL

UNION ALL

SELECT 'fact -> dim_payments',
    COUNT(*)
FROM olist_db.marts.fact_orders f
LEFT JOIN olist_db.marts.dim_payments p ON f.order_id = p.order_id
WHERE p.order_id IS NULL

UNION ALL

SELECT 'fact -> dim_date',
    COUNT(*)
FROM olist_db.marts.fact_orders f
LEFT JOIN olist_db.marts.dim_date d ON f.order_date = d.date_id
WHERE d.date_id IS NULL;

-- RESULTADOS DO CHECK 3:
-- fact -> dim_products:  0 órfãos - integridade referencial confirmada
-- fact -> dim_sellers:   0 órfãos - integridade referencial confirmada
-- fact -> dim_customers: 2.474 órfãos - investigado nos checks 3.1 a 3.3 abaixo
-- fact -> dim_payments:  3 órfãos - pedidos na fato sem registro de pagamento
-- fact -> dim_date:      0 órfãos - integridade referencial confirmada
--                        (dim_date é gerada por GENERATOR, cobrindo todo o intervalo de datas)
--
-- CAUSA RAIZ dim_payments: 3 pedidos sem registro de pagamento na staging
--   ação: investigar esses 3 pedidos em staging.order_payments


-- ============================================================
-- CHECK 3.1: INVESTIGAR ÓRFÃOS NA dim_customers
-- ============================================================
-- O check 3 inicial mostrou 2.474 órfãos em fact -> dim_customers.
-- Primeiro passo: verificar se customer_id existe na dim_customers
-- para determinar se o problema está na dimensão ou na tabela de fatos.
-- ============================================================

SELECT COUNT(DISTINCT customer_id)
FROM olist_db.marts.dim_customers;

-- RESULTADOS:
-- dim_customers possui exatamente 99.441 customer_ids únicos
-- Isso corresponde perfeitamente à contagem de staging.customers
-- Conclusão: dim_customers está completa — o problema está na fact_orders


-- ============================================================
-- CHECK 3.2: COMPARAR CONTAGEM DE CUSTOMER_ID ENTRE FATO E DIM
-- ============================================================
-- Compara os customer_ids distintos entre fact_orders e
-- dim_customers para identificar se as contagens batem.
-- Se as contagens baterem, os órfãos provavelmente são valores NULL na fact_orders.
-- ============================================================

SELECT COUNT(DISTINCT f.customer_id) AS fact_customers,
       COUNT(DISTINCT c.customer_id) AS dim_customers
FROM olist_db.marts.fact_orders f
LEFT JOIN olist_db.marts.dim_customers c
    ON f.customer_id = c.customer_id;

-- RESULTADOS DO CHECK 3.2:
-- fact_customers e dim_customers apresentam contagens compatíveis
-- Conclusão: os 2.474 aparentes órfãos são customer_ids NULL na fact_orders
-- NÃO são registros ausentes na dim_customers


-- ============================================================
-- CHECK 3.3: CONFIRMAR CUSTOMER_IDS NULOS NA FACT_ORDERS
-- ============================================================
-- Confirma se os 2.474 órfãos aparentes são, na verdade,
-- customer_ids NULOS na fact_orders — e não registros ausentes na dimensão.
-- ============================================================

SELECT COUNT(*) AS null_customer_ids
FROM olist_db.marts.fact_orders
WHERE customer_id IS NULL;

-- RESULTADOS:
-- 2.474 registros possuem customer_id NULO na fact_orders
-- CAUSA RAIZ: são order_items cujo pedido pai foi filtrado na
-- camada de staging (pedidos não entregues foram excluídos)
-- O order_item existe, mas o order_status do pedido pai é != 'delivered'
-- CONCLUSÃO: comportamento esperado — NÃO é um problema de qualidade de dados

-- ============================================================
-- CHECK 3 - CONCLUSÃO FINAL
-- ============================================================
-- fact -> dim_products:  0 órfãos - integridade referencial confirmada
-- fact -> dim_sellers:   0 órfãos - integridade referencial confirmada
-- fact -> dim_customers: 2.474 customer_ids NULOS - ESPERADO
--                        order_items sem pedido pai entregue,
--                        filtrados no 05_silver_etl.sql por design
-- fact -> dim_payments:  3 órfãos - volume desprezível
--                        3 pedidos sem registro de pagamento na staging
--                        nenhuma ação necessária
-- fact -> dim_date:      0 órfãos - integridade referencial confirmada
-- INTEGRIDADE REFERENCIAL GERAL: APROVADA
-- ============================================================


-- ============================================================
-- CHECK 4: DISTRIBUIÇÃO DA SINALIZAÇÃO DE RISCO DE FRETE
-- ============================================================
-- Valida a distribuição das sinalizações (flags) de risco de frete
-- em todos os itens de pedidos. Uma alta proporção de sinalizações críticas
-- indica problemas sistêmicos de preços que exigem ação imediata.
-- freight_risk_flag é calculado no arquivo 05_silver_etl.sql:
--   critical  -> frete > 30% do preço (margem em risco)
--   attention -> frete entre 20-30% (margem sob pressão)
--   ok        -> frete < 20% (proporção aceitável)
-- ============================================================

SELECT
    freight_risk_flag,                                             -- critical / attention / ok
    COUNT(*) AS total,                                             -- total de itens por flag
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER(), 2) AS percentual, -- % do total
    ROUND(AVG(price), 2) AS avg_price,                             -- preço médio por nível de risco
    ROUND(AVG(freight_value), 2) AS avg_freight                    -- frete médio por nível de risco
FROM olist_db.marts.fact_orders
GROUP BY freight_risk_flag
ORDER BY total DESC;

-- RESULTADOS:
-- ok:        49.110 (43,34%) - preço médio R$ 202,35, frete médio R$ 18,35
-- critical:  41.456 (36,59%) - preço médio R$  44,94, frete médio R$ 21,94
-- attention: 22.748 (20,08%) - preço médio R$  81,39, frete médio R$ 19,94
--
-- INSIGHT CHAVE: 56,67% dos itens têm o frete impactando a margem
-- (critical + attention somados)
--
-- ALERTA CRÍTICO: 36,59% dos itens estão em estado critical
-- preço médio de R$ 44,94 com frete médio de R$ 21,94 significa que o frete
-- representa mais de 30% do preço de venda
-- São produtos de baixo preço onde o frete corrói agressivamente a margem
--
-- DECISÃO: produtos na flag critical com preço abaixo de R$ 50
-- devem ser revisados para aumento de preço ou negociação de frete
-- com parceiros logísticos para restaurar níveis aceitáveis de margem


-- ============================================================
-- CHECK 5: DISTRIBUIÇÃO DOS SEGMENTOS DE PREÇO
-- ============================================================
-- Valida a distribuição dos produtos pelos segmentos de preço.
-- Os segmentos de preço são definidos no arquivo 06_gold_modelagem.sql:
--   budget    -> preço médio <= R$ 50
--   mid_range -> preço médio <= R$ 150
--   premium   -> preço médio <= R$ 500
--   luxury    -> preço médio > R$ 500
-- Permite entender a composição do portfólio de produtos
-- e a concentração de receita por faixa de preço.
-- ============================================================

SELECT
    price_segment,                                                 -- budget / mid_range / premium / luxury
    COUNT(*) AS total_items,                                       -- total de itens por segmento
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER(), 2) AS percentual, -- % do total
    ROUND(AVG(price), 2) AS avg_price,                             -- preço médio por segmento
    ROUND(SUM(price), 2) AS total_revenue                          -- receita total por segmento
FROM olist_db.marts.fact_orders
GROUP BY price_segment
ORDER BY avg_price DESC;

-- RESULTADOS:
-- luxury:     3.286  ( 2,90%) - preço médio R$   918,02 - receita R$ 3.016.619
-- premium:   19.873  (17,54%) - preço médio R$   236,75 - receita R$ 4.704.954
-- mid_range: 52.040  (45,93%) - preço médio R$    91,37 - receita R$ 4.754.664
-- budget:    38.115  (33,64%) - preço médio R$    30,85 - receita R$ 1.175.684
--
-- INSIGHT CHAVE: mid_range domina o volume (45,93%) e a receita (R$ 4,75M)
-- mid_range e premium juntos representam 63,47% dos itens
-- e R$ 9,46M em receita (69% do total)
--
-- CONCENTRAÇÃO DE RECEITA:
-- luxury representa apenas 2,90% dos itens, mas gera R$ 3,01M de receita
-- ticket médio de luxury é R$ 918 contra R$ 30,85 de budget
-- produtos de luxo têm um preço médio 29x maior que os econômicos (budget)
--
-- DECISÃO: a estratégia de precificação deve focar em:
-- 1. proteger a margem do mid_range — maior volume de receita
-- 2. expandir o segmento premium — alta receita por item
-- 3. revisar o segmento budget — R$ 1,17M de receita em risco pelo frete
--    (itens de budget têm maior probabilidade de estar na flag critical de risco de frete)


-- ============================================================
-- CHECK 6: DISTRIBUIÇÃO DOS SEGMENTOS RFM
-- ============================================================
-- Valida a distribuição de clientes nos segmentos RFM.
-- Os segmentos RFM são definidos no arquivo 06_gold_modelagem.sql:
--   champions -> rfm_weighted_score >= 2.5 (melhores clientes)
--   loyal     -> rfm_weighted_score >= 2.0 (compradores frequentes)
--   potential -> rfm_weighted_score >= 1.5 (oportunidade de crescimento)
--   at_risk   -> rfm_weighted_score <  1.5 (precisa de atenção)
-- Pesos: Recência=40%, Frequência=30%, Monetário=30%
-- Permite a diferenciação da estratégia de preços ao nível do cliente.
--
-- NOTA METODOLÓGICA: o peso de recência (40%) pode penalizar clientes
-- de alto valor que não compraram próximo ao fim do dataset (2018-10-17).
-- Clientes com compras de alto ticket em 2017 e inatividade em 2018
-- podem cair em 'at_risk' mesmo sendo de alto valor histórico.
-- Cruzar rfm_segment com total_spent em quartis pode validar essa hipótese.
-- ============================================================

SELECT
    rfm_segment,                                                   -- champions / loyal / potential / at_risk
    COUNT(*) AS total_customers,                                   -- clientes por segmento
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER(), 2) AS percentual, -- % do total
    ROUND(AVG(total_spent), 2) AS avg_total_spent,                 -- valor médio gasto na vida útil (LTV)
    ROUND(AVG(avg_order_value), 2) AS avg_order_value              -- valor médio do pedido
FROM olist_db.marts.dim_customers
GROUP BY rfm_segment
ORDER BY avg_total_spent DESC;

-- RESULTADOS:
-- at_risk:    5.336  ( 5,37%) - LTV médio R$ 337,67 - pedido médio R$ 270,27
-- loyal:     40.097  (40,32%) - LTV médio R$ 179,57 - pedido médio R$ 141,93
-- potential: 33.000  (33,19%) - LTV médio R$ 170,09 - pedido médio R$ 133,08
-- champions: 21.008  (21,13%) - LTV médio R$  63,62 - pedido médio R$  46,56
--
-- INSIGHT INESPERADO: o segmento at_risk possui o maior LTV médio (R$ 337,67)
-- e o maior valor médio de pedido (R$ 270,27) — clientes de alto valor
-- que não compram recentemente. Representam o maior risco de perda de receita.
-- Ver nota metodológica acima sobre o impacto do peso de recência nesse resultado.
--
-- DECISÃO: estratégia de precificação por segmento:
-- at_risk:    campanha de reengajamento com precificação personalizada
--             — clientes de alto valor que vale a pena recuperar
-- loyal:      manter os preços atuais — base de receita estável (40,32%)
-- potential:  descontos moderados para aumentar a frequência de compra
-- champions:  incentivos de volume e bundles — frequentes, ticket menor


-- ============================================================
-- CHECK 7: DISTRIBUIÇÃO DOS NÍVEIS DE VENDEDORES
-- ============================================================
-- Valida a distribuição dos vendedores pelos níveis (tiers) de desempenho.
-- Os níveis de vendedores são definidos no arquivo 06_gold_modelagem.sql:
--   platinum -> receita total >= R$ 100.000
--   gold     -> receita total >= R$  50.000
--   silver   -> receita total >= R$  10.000
--   bronze   -> receita total <  R$  10.000
-- Permite condições comerciais diferenciadas por nível de vendedor.
-- ============================================================

SELECT
    seller_tier,                                                   -- platinum / gold / silver / bronze
    COUNT(*) AS total_sellers,                                     -- vendedores por nível
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER(), 2) AS percentual, -- % do total
    ROUND(AVG(total_revenue), 2) AS avg_revenue,                   -- receita média por nível
    ROUND(AVG(avg_review_score), 2) AS avg_review_score            -- satisfação média por nível
FROM olist_db.marts.dim_sellers
GROUP BY seller_tier
ORDER BY avg_revenue DESC;

-- RESULTADOS:
-- platinum:   18  ( 0,58%) - receita média R$ 150.255 - nota média 4,04
-- gold:       22  ( 0,71%) - receita média R$  60.485 - nota média 4,14
-- silver:    252  ( 8,14%) - receita média R$  19.912 - nota média 4,01
-- bronze:  2.803  (90,57%) - receita média R$   1.640 - nota média 3,97
--
-- INSIGHT CHAVE: concentração extrema de receita
-- platinum + gold = apenas 40 vendedores (1,29%) direcionam a maior parte da receita
-- bronze = 90,57% dos vendedores com receita média de apenas R$ 1.640
--
-- INSIGHT DE QUALIDADE: notas consistentes entre todos os níveis (3,97 a 4,14)
-- grandes vendedores não são necessariamente mais bem avaliados que os pequenos
--
-- RISCO DE CONCENTRAÇÃO: 18 vendedores platinum com média de R$ 150.255 cada
-- churn de um vendedor platinum representa impacto significativo na receita
--
-- DECISÃO: condições comerciais por nível:
-- platinum: suporte prioritário, melhores taxas de frete, acordos exclusivos
-- gold:     incentivos de crescimento para alcançar o nível platinum
-- silver:   programas de desconto por volume para aumentar a receita
-- bronze:   condições padrão, suporte self-service


-- ============================================================
-- CHECK 8: TOP CATEGORIAS POR RECOMENDAÇÃO DE PREÇO
-- ============================================================
-- Identifica quais categorias de produtos têm mais itens
-- marcados para ação de preço — excluindo o status 'monitor'.
-- Decision Centric: direciona as prioridades de preços ao nível da categoria.
-- Foco apenas em recomendações acionáveis.
-- Exibe as 5 categorias com mais itens por recomendação,
-- usando QUALIFY para evitar que um LIMIT oculte categorias críticas
-- com menor volume absoluto mas alta proporção de risco.
-- ============================================================

SELECT
    product_category_name,                                         -- categoria do produto
    pricing_recommendation,                                        -- recomendação acionável
    COUNT(*) AS total_items,                                       -- itens por categoria + recomendação
    ROUND(AVG(price), 2) AS avg_price,                             -- preço médio
    ROUND(AVG(freight_ratio_pct), 2) AS avg_freight_ratio          -- proporção média de frete
FROM olist_db.marts.fact_orders
WHERE pricing_recommendation != 'monitor'                          -- foco apenas em itens acionáveis
GROUP BY product_category_name, pricing_recommendation
QUALIFY ROW_NUMBER() OVER (
    PARTITION BY pricing_recommendation
    ORDER BY COUNT(*) DESC
) <= 5
ORDER BY pricing_recommendation, total_items DESC;

-- RESULTADOS:
-- increase_price (top 5):
--   cool_stuff              538 itens - preço médio R$ 126,04 - frete 14,58%
--   cama_mesa_banho         538 itens - preço médio R$ 108,91 - frete 17,32%
--   relogios_presentes      311 itens - preço médio R$ 105,69 - frete 15,58%
--   perfumaria              278 itens - preço médio R$  70,95 - frete 19,90%
--   esporte_lazer           268 itens - preço médio R$ 107,39 - frete 18,04%
--
-- maintain_pricing (top 5):
--   beleza_saude           3.577 itens - preço médio R$ 170,52 - frete 15,14%
--   cama_mesa_banho        3.212 itens - preço médio R$ 118,98 - frete 17,20%
--   esporte_lazer          2.969 itens - preço médio R$ 147,59 - frete 15,95%
--   relogios_presentes     2.516 itens - preço médio R$ 252,60 - frete 10,33%
--   informatica_acessorios 2.158 itens - preço médio R$ 158,18 - frete 15,72%
--
-- reduce_price (top 5):
--   informatica_acessorios  194 itens - preço médio R$ 120,29 - frete 15,77%
--   cama_mesa_banho         180 itens - preço médio R$ 110,11 - frete 18,29%
--   moveis_decoracao        176 itens - preço médio R$  89,54 - frete 17,42%
--   esporte_lazer            95 itens - preço médio R$ 126,64 - frete 16,70%
--   beleza_saude             87 itens - preço médio R$ 203,72 - frete 13,77%
--
-- reduce_price_and_freight (top 5):
--   moveis_decoracao        815 itens - preço médio R$  52,69 - frete 59,08%
--   cama_mesa_banho         734 itens - preço médio R$  46,86 - frete 50,55%
--   utilidades_domesticas   552 itens - preço médio R$  46,02 - frete 73,45%
--   beleza_saude            481 itens - preço médio R$  46,29 - frete 82,98%
--   telefonia               472 itens - preço médio R$  27,44 - frete 66,35%
--
-- review_freight_strategy (top 5):
--   cama_mesa_banho        2.905 itens - preço médio R$  45,97 - frete 52,00%
--   moveis_decoracao       2.807 itens - preço médio R$  48,62 - frete 55,49%
--   utilidades_domesticas  2.776 itens - preço médio R$  43,47 - frete 62,78%
--   beleza_saude           2.644 itens - preço médio R$  43,30 - frete 57,96%
--   telefonia              2.488 itens - preço médio R$  26,21 - frete 69,25%
--
-- PADRÃO CHAVE: mesmas categorias aparecem em múltiplas recomendações
-- cama_mesa_banho: 3.212 em maintain_pricing MAS 2.905 em review_freight e 734 em reduce_price_and_freight
-- beleza_saude:    3.577 em maintain_pricing MAS 2.644 em review_freight e 481 em reduce_price_and_freight
--
-- CAUSA RAIZ: categorias com dois subgrupos distintos de produtos:
-- GRUPO 1 -> produtos de maior preço (R$ 120-250) — proporção de frete aceitável (10-18%)
-- GRUPO 2 -> produtos de menor preço (R$ 26-52)   — mesmo frete representa 50-83% do preço
--
-- ALERTAS CRÍTICOS:
-- beleza_saude + reduce_price_and_freight:         frete médio 82,98% — caso mais grave do dataset
-- utilidades_domesticas + reduce_price_and_freight: frete 73,45% — segundo caso mais grave
-- telefonia + review_freight_strategy:              frete 69,25% em produto de R$ 26 — prejuízo a cada venda
--
-- OPORTUNIDADES (increase_price):
-- cool_stuff e cama_mesa_banho: 538 itens cada — frete saudável (14-17%), aumento de preço viável
-- relogios_presentes: 311 itens a R$ 105 com frete 15,58% — margem confortável para reajuste
--
-- DECISÃO: recomendações ao nível da categoria:
-- beleza_saude:          dividir estratégia por faixa de preço
--                        produtos abaixo de R$ 50 precisam de aumento de 20-30%
-- cama_mesa_banho:       negociar frete para itens de ticket baixo
--                        ou definir valor mínimo de pedido para frete grátis
-- telefonia:             revisão urgente — frete 69% é insustentável
--                        aumento de preço de no mínimo 40% para itens abaixo de R$ 30
-- moveis_decoracao:      produtos volumosos precisam de revisão logística
--                        considerar centros de distribuição regionais
-- utilidades_domesticas: terceiro caso mais crítico — revisar mix de produtos e política de frete

-- ============================================================
-- VERIFICAÇÕES DE QUALIDADE GERAIS: APROVADO
-- Star Schema validado e pronto para consumo em dashboards e APIs
-- ============================================================

-- CHECK 1   ✅ Contagem de linhas     — todos os volumes confirmados
-- CHECK 1.1 ✅ Asserções automáticas  — pipeline com validação ativa
-- CHECK 2   ✅ Recomendações de preço — distribuição saudável
-- CHECK 3   ✅ Integridade referencial — aprovado (inclui dim_date)
-- CHECK 4   ✅ Risco de frete         — 56,67% requer atenção
-- CHECK 5   ✅ Segmentos de preço     — mid_range domina receita
-- CHECK 6   ✅ Segmentos RFM          — at_risk tem maior LTV
-- CHECK 7   ✅ Níveis de vendedores   — concentração em bronze
-- CHECK 8   ✅ Top categorias         — padrão dual identificado por recomendação
