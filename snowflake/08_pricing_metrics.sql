-- ============================================================
-- PROJETO: Olist Pricing Intelligence
-- ARQUIVO: 08_pricing_analysis.sql
-- DESCRIÇÃO: Análises avançadas de pricing usando a camada MARTS.
--            Entrega recomendações acionáveis de precificação
--            baseadas em margem, impacto do frete, price index,
--            segmentação de clientes e oportunidades de pricing.
--            Este é o núcleo analítico do projeto Decision Centric.
--            Pré-requisitos:
--            - 06_gold_modelagem.sql deve ter sido executado
--            - 07_quality_checks.sql deve ter sido aprovado
-- AUTOR: Gisele CP
-- DATA: 2026-06-23
-- ============================================================

-- VISÃO GERAL DAS ANÁLISES
-- Este arquivo cobre 8 análises avançadas de pricing:
--
-- ANALYSIS 1: Receita líquida e margem de frete por categoria
-- ANALYSIS 2: Proxy de elasticidade-preço por categoria
-- ANALYSIS 3: Price Index por região (estado)
-- ANALYSIS 4: Detecção de produtos subprecificados
-- ANALYSIS 5: Detecção de produtos sobrepreçados
-- ANALYSIS 6: Impacto do frete na receita por categoria
-- ANALYSIS 7: Oportunidade de receita por segmento RFM
-- ANALYSIS 8: Resumo executivo de recomendações de pricing

-- NOTA METODOLÓGICA GERAL:
-- freight_value no dataset Olist representa o valor do frete
-- cobrado DO cliente — não o custo logístico real.
-- Portanto, (price - freight_value) representa receita líquida
-- após frete, NÃO margem de lucro real.
-- COGS não está disponível neste dataset.
-- Todos os thresholds são hipóteses analíticas que devem ser
-- calibrados com dados reais de negócio em produção.

-- ============================================================
-- CONTEXT SETUP
-- ============================================================

USE WAREHOUSE olist_wh;
USE DATABASE olist_db;
USE SCHEMA marts;

-- ============================================================
-- BASE FILTER VIEW (usar em todas as analyses)
-- ============================================================
-- Filtro base reutilizável para garantir consistência em todas
-- as análises. Elimina registros com preço inválido, frete
-- negativo e categoria nula sem repetir filtros em cada query.
-- ============================================================
CREATE OR REPLACE VIEW olist_db.marts.v_fact_orders_clean AS
SELECT *
FROM olist_db.marts.fact_orders
WHERE price > 0                             -- elimina registros com preço inválido
AND freight_value >= 0                      -- elimina frete negativo
AND product_category_name IS NOT NULL;      -- elimina registros sem categoria

-- ============================================================
-- ANALYSIS 1: NET REVENUE AND FREIGHT MARGIN BY CATEGORY
-- ============================================================


-- ============================================================
-- ANALYSIS 1: NET REVENUE AND FREIGHT MARGIN BY CATEGORY
-- ============================================================
-- Calcula receita líquida após frete por categoria.
-- Ordena pelas piores categorias primeiro — foco em ação imediata.
--
-- FÓRMULAS:
-- net_revenue_after_freight = price - freight_value
-- freight_margin_pct = (price - freight_value) / price * 100
--
-- CLASSIFICAÇÃO DE SAÚDE (impacto do frete na receita):
-- healthy        -> frete < 30% do preço (freight_margin_pct >= 70%)
-- acceptable     -> frete 30-50% do preço (freight_margin_pct >= 50%)
-- under_pressure -> frete 50-100% do preço (freight_margin_pct >= 0%)
-- freight_exceeds_price -> frete > preço (freight_margin_pct < 0%)
-- ============================================================

SELECT
    product_category_name,                                              -- categoria do produto
    COUNT(*) AS total_items,                                            -- total de itens vendidos
    ROUND(AVG(price), 2) AS avg_price,                                  -- preço médio de venda
    ROUND(AVG(freight_value), 2) AS avg_freight,                        -- frete médio cobrado ao cliente
    ROUND(AVG(price - freight_value), 2) AS avg_net_revenue,            -- receita média após frete
    ROUND(AVG((price - freight_value) /
          NULLIF(price, 0) * 100), 2) AS freight_margin_pct,            -- % da receita não consumida pelo frete
    ROUND(AVG((price - freight_value) /
          NULLIF(freight_value, 0) * 100), 2) AS freight_markup_pct,    -- receita líquida como múltiplo do frete
    ROUND(SUM(price), 2) AS total_revenue,                              -- receita bruta total
    ROUND(SUM(price - freight_value), 2) AS total_net_revenue,          -- receita total após frete
    COUNT(CASE WHEN (price - freight_value) < 0
        THEN 1 END) AS negative_margin_items,                           -- corrigido: CASE inline — itens onde frete > preço
    CASE
        WHEN AVG((price - freight_value) /
             NULLIF(price, 0) * 100) >= 70 THEN 'healthy'               -- frete < 30% da receita
        WHEN AVG((price - freight_value) /
             NULLIF(price, 0) * 100) >= 50 THEN 'acceptable'            -- frete 30-50% da receita
        WHEN AVG((price - freight_value) /
             NULLIF(price, 0) * 100) >= 0  THEN 'under_pressure'        -- frete 50-100% da receita
        ELSE 'freight_exceeds_price'                                     -- frete > preço de venda
    END AS margin_health
FROM olist_db.marts.v_fact_orders_clean                                  -- corrigido: view com filtro base
WHERE product_category_name IS NOT NULL
GROUP BY product_category_name
ORDER BY freight_margin_pct ASC                                          -- piores casos primeiro
LIMIT 20;

-- FINDINGS ANALYSIS 1:
-- nenhuma categoria em freight_exceeds_price — positivo
-- under_pressure: telefonia (4.545 itens), eletronicos (2.767 itens)
-- negative_margin: eletronicos 611 itens, telefonia 430, utilidades 385
-- telefonia: R$ 71.216 consumidos pelo frete em R$ 323.667 de receita
-- DECISÃO: priorizar revisão de preço mínimo em eletronicos e telefonia
-- PRÓXIMO PASSO: analysis 2 — elasticidade para validar se aumento
-- de preço impacta volume antes de recomendar ação


-- ============================================================
-- ANALYSIS 2: PROXY DE ELASTICIDADE-PREÇO POR CATEGORIA
-- ============================================================
-- Elasticidade real requer experimentos controlados de preço
-- (testes A/B) com série temporal — não disponível neste dataset.
--
-- ABORDAGEM PROXY:
-- Usamos coeficiente de variação (CV) e correlação preço-volume
-- como indicadores de sensibilidade ao preço por categoria.
-- CV = desvio padrão / média — mede dispersão relativa do preço.
-- Alto CV indica grande variação de preço dentro da categoria,
-- sugerindo que clientes são expostos a diferentes faixas de preço.
-- Correlação negativa entre preço e review_score sugere que
-- produtos mais caros geram menor satisfação (comportamento elástico).
--
-- CLASSIFICAÇÃO:
-- elastic  -> clientes sensíveis a variações de preço
--             aumento de preço pode reduzir demanda significativamente
-- inelastic -> clientes menos sensíveis a variações de preço
--              preço pode ser aumentado sem grande perda de demanda
-- neutral  -> sem correlação clara entre preço e satisfação
--
-- NOTA METODOLÓGICA:
-- Este é um proxy, não elasticidade real.
-- Resultados devem ser interpretados como indicadores de
-- sensibilidade ao preço e validados com testes A/B controlados.
-- Mínimo de 100 itens por categoria para significância estatística.
-- ============================================================

SELECT
    product_category_name,                                              -- categoria do produto
    COUNT(*) AS total_items,                                            -- total de itens vendidos
    ROUND(AVG(price), 2) AS avg_price,                                  -- preço médio
    ROUND(STDDEV(price), 2) AS stddev_price,                            -- desvio padrão do preço
    ROUND(MIN(price), 2) AS min_price,                                  -- preço mínimo
    ROUND(MAX(price), 2) AS max_price,                                  -- preço máximo
    ROUND(STDDEV(price) / NULLIF(AVG(price), 0) * 100, 2) AS cv_pct,   -- coeficiente de variação %
    ROUND(AVG(review_score), 2) AS avg_review_score,                    -- satisfação média
    ROUND(CORR(price, review_score), 4) AS price_score_correlation,     -- correlação preço x satisfação
    CASE
        WHEN STDDEV(price) / NULLIF(AVG(price), 0) > 1.0 THEN 'high_dispersion'    -- alta dispersão de preço
        WHEN STDDEV(price) / NULLIF(AVG(price), 0) > 0.5 THEN 'medium_dispersion'  -- dispersão média
        ELSE 'low_dispersion'                                                        -- baixa dispersão
    END AS price_dispersion_flag,                                       -- classificação de dispersão
    CASE
        WHEN CORR(price, review_score) < -0.1 THEN 'elastic'           -- preço alto reduz satisfação
        WHEN CORR(price, review_score) > 0.1  THEN 'inelastic'         -- preço alto aumenta satisfação
        ELSE 'neutral'                                                   -- sem correlação clara
    END AS elasticity_proxy                                             -- indicador de sensibilidade ao preço
FROM olist_db.marts.v_fact_orders_clean                                  -- corrigido: view com filtro base
WHERE review_score IS NOT NULL
GROUP BY product_category_name
HAVING COUNT(*) >= 100
ORDER BY cv_pct DESC, total_items DESC                                   -- corrigido: desempate por volume
LIMIT 20;

-- FINDINGS ANALYSIS 2:
-- todas as categorias com high_dispersion — categorias amplas e heterogêneas
-- apenas 2 categorias elastic: telefonia_fixa (-0.37) e automotivo (-0.11)
-- alta dispersão generalizada indica limitação do dataset
-- categorias misturam produtos de faixas de preço muito diferentes
-- DECISÃO: análise de elasticidade deve ser feita por faixa de preço
-- dentro da categoria, não pela categoria como um todo
-- PRÓXIMO PASSO: analysis 3 — price index por região
-- NOTA: total_items difere da Analysis 1 — filtro review_score IS NOT NULL
-- descarta itens sem avaliação (~0.7% do dataset em eletronicos)


-- ============================================================
-- ANALYSIS 3: PRICE INDEX POR REGIÃO (ESTADO)
-- ============================================================
-- Price Index mede o preço médio de cada região em relação
-- à média nacional — identifica regiões com preços acima ou
-- abaixo do mercado.
--
-- FÓRMULA:
-- price_index = avg_price_estado / avg_price_nacional * 100
-- price_index > 110 -> região cobra acima da média nacional
-- price_index 90-110 -> região alinhada com média nacional
-- price_index < 90  -> região cobra abaixo da média nacional
--
-- DECISÃO DE NEGÓCIO:
-- Regiões com price_index baixo podem ter oportunidade de
-- aumento de preço sem perda de competitividade local.
-- Regiões com price_index alto podem indicar menor elasticidade
-- ou menor concorrência — oportunidade de pricing premium.
--
-- NOTA: price_index calculado sobre preço médio de venda
-- não considera poder aquisitivo regional nem concorrência local.
-- Em produção deve ser complementado com dados externos.
-- ============================================================

WITH national_avg AS (
    -- média nacional de preço como referência base
    SELECT ROUND(AVG(price), 2) AS avg_price_national
    FROM olist_db.marts.fact_orders
    WHERE price IS NOT NULL
),
state_metrics AS (
    SELECT
        s.seller_state,                                                 -- estado do seller
        COUNT(*) AS total_items,                                        -- total de itens vendidos
        COUNT(DISTINCT f.order_id) AS total_orders,                     -- pedidos únicos
        ROUND(AVG(f.price), 2) AS avg_price,                            -- preço médio do estado
        ROUND(AVG(f.freight_value), 2) AS avg_freight,                  -- frete médio do estado
        ROUND(AVG(f.freight_ratio_pct), 2) AS avg_freight_ratio,        -- ratio frete/preço médio
        ROUND(SUM(f.price), 2) AS total_revenue,                        -- receita total do estado
        ROUND(AVG(f.review_score), 2) AS avg_review_score,              -- satisfação média do estado
        ROUND(SUM(f.price) * 100.0 /
              SUM(SUM(f.price)) OVER(), 2) AS revenue_share_pct         -- participação na receita total
    FROM olist_db.marts.fact_orders f
    LEFT JOIN olist_db.marts.dim_sellers s
        ON f.seller_id = s.seller_id
    WHERE f.price IS NOT NULL
    AND s.seller_state IS NOT NULL
    GROUP BY s.seller_state
)
SELECT
    sm.seller_state,
    sm.total_items,
    sm.total_orders,
    sm.avg_price,
    sm.avg_freight,
    sm.avg_freight_ratio,
    sm.total_revenue,
    sm.avg_review_score,
    sm.revenue_share_pct,
    na.avg_price_national,                                              -- média nacional para referência
    ROUND(sm.avg_price / NULLIF(na.avg_price_national, 0) * 100, 2) AS price_index, -- index vs nacional
    CASE
        WHEN sm.avg_price / NULLIF(na.avg_price_national, 0) * 100 > 110
            THEN 'above_market'                                         -- acima da média nacional
        WHEN sm.avg_price / NULLIF(na.avg_price_national, 0) * 100 >= 90
            THEN 'aligned'                                              -- alinhado com média nacional
        ELSE 'below_market'                                             -- abaixo da média nacional
    END AS price_index_flag                                             -- classificação de posicionamento
FROM state_metrics sm
CROSS JOIN national_avg na                                              -- traz média nacional para cada linha
ORDER BY price_index DESC;                                              -- estados com maior index primeiro

-- FINDINGS ANALYSIS 3:
-- média nacional: R$ 120,65
-- SP: 64.4% da receita, price_index 90.3 (below national avg)
--   causa provável: maior concorrência, sellers com estratégia de volume
-- MA: único below_market com volume relevante (405 itens, index 74.5)
--   oportunidade: espaço de ~25% de aumento antes de atingir média
-- estados com < 50 itens: desconsiderar para decisão de pricing
--   volume insuficiente para significância estatística
-- DECISÃO: price index deve ser analisado por categoria dentro do estado
--   não apenas por estado — mix de produtos distorce a comparação
-- ALERTA: PB e BA com price_index > 350 mas volume < 700 itens
-- alta probabilidade de distorção por mix — não interpretar como
-- oportunidade de pricing sem análise por categoria dentro do estado
-- estados com volume < 50 itens: AM, RO, AC, PI, SE, PA — descartar
-- para decisão de pricing (insuficiente para significância estatística)


-- ============================================================
-- ANALYSIS 4: DETECÇÃO DE PRODUTOS SUBPRECIFICADOS
-- ============================================================
-- Identifica produtos com preço abaixo do limite inferior IQR
-- da sua categoria — candidatos a aumento de preço.
--
-- CRITÉRIOS DE SUBPRECIFICAÇÃO:
-- 1. pricing_flag = 'underpriced' (abaixo do limite IQR)
-- 2. review_score >= 4 (boa satisfação — clientes aceitam o produto)
-- 3. total_items_sold >= 10 (volume mínimo para relevância)
--
-- LÓGICA DECISION CENTRIC:
-- Produto subprecificado + boa satisfação = oportunidade de
-- aumentar preço sem risco de perda de demanda.
-- Produto subprecificado + satisfação baixa = problema de
-- qualidade, não de preço — não recomendar aumento.
--
-- NOTA METODOLÓGICA:
-- Subprecificação é detectada via método IQR calculado na
-- dim_products (06_gold_modelagem.sql).
-- Limites IQR são calculados por categoria — produto é
-- comparado com seus pares na mesma categoria.
-- ============================================================

SELECT
    f.product_category_name,                                            -- categoria do produto
    f.product_id,                                                       -- identificador do produto
    p.avg_price AS product_avg_price,                                   -- preço médio histórico do produto
    p.min_price,                                                        -- preço mínimo registrado
    p.max_price,                                                        -- preço máximo registrado
    p.q1_price,                                                         -- 1º quartil de preço
    p.q3_price,                                                         -- corrigido: adicionado ao SELECT — 3º quartil de preço
    p.price_lower_bound,                                                -- limite inferior de preço (IQR)
    p.price_upper_bound,                                                -- limite superior de preço (IQR)
    p.pricing_flag,                                                     -- classificação de pricing do produto
    p.total_items_sold,                                                 -- total de unidades vendidas
    p.total_revenue,                                                    -- receita total do produto
    ROUND(AVG(f.review_score), 2) AS avg_review_score,                  -- satisfação média do produto
    ROUND(AVG(f.freight_ratio_pct), 2) AS avg_freight_ratio,            -- ratio frete/preço médio
    ROUND((p.q1_price + p.q3_price) / 2, 2) AS recommended_price,      -- preço recomendado (mediana IQR)
    ROUND(((p.q1_price + p.q3_price) / 2) - p.avg_price, 2) AS price_gap,           -- diferença preço atual vs recomendado
    ROUND((((p.q1_price + p.q3_price) / 2) - p.avg_price) /
          NULLIF(p.avg_price, 0) * 100, 2) AS price_gap_pct,           -- gap percentual
    ROUND((((p.q1_price + p.q3_price) / 2) - p.avg_price) *
          p.total_items_sold, 2) AS revenue_opportunity                 -- oportunidade de receita incremental
FROM olist_db.marts.v_fact_orders_clean f                               -- corrigido: view com filtro base
LEFT JOIN olist_db.marts.dim_products p
    ON f.product_id = p.product_id
WHERE p.pricing_flag = 'underpriced'                                    -- apenas produtos subprecificados
AND f.review_score >= 4                                                 -- apenas produtos bem avaliados
AND p.total_items_sold >= 10                                            -- volume mínimo para significância
AND p.q1_price != p.q3_price                                            -- corrigido: remove produtos com IQR = 0 (preço fixo)
GROUP BY
    f.product_category_name,
    f.product_id,
    p.avg_price,
    p.min_price,
    p.max_price,
    p.q1_price,
    p.q3_price,                                                         -- corrigido: adicionado ao GROUP BY
    p.price_lower_bound,
    p.price_upper_bound,
    p.pricing_flag,
    p.total_items_sold,
    p.total_revenue
HAVING AVG(f.review_score) >= 4                                         -- reforço do filtro de satisfação
ORDER BY revenue_opportunity DESC                                        -- maior oportunidade primeiro
LIMIT 20;

-- FINDINGS ANALYSIS 4 (revisado):
-- filtro q1_price != q3_price removeu 13 produtos com IQR = 0 (preço fixo)
-- resultado limpo: 7 produtos com variação real de preço e subprecificação confirmada
-- revenue_opportunity real (universo limpo): ~R$ 1.050
-- ferramentas_jardim mantém maior oportunidade: R$ 684,99
-- categorias remanescentes: ferramentas_jardim, relogios_presentes,
--   informatica_acessorios (2x), pet_shop, utilidades_domesticas, telefonia
-- DECISÃO: priorizar ferramentas_jardim e relogios_presentes
--   menor risco: alto review (4.76-4.80) + gap percentual moderado (3-5%)
-- PRÓXIMO PASSO: analysis 5 — produtos sobrepreçados


-- ============================================================
-- ANALYSIS 5: DETECÇÃO DE PRODUTOS SOBREPREÇADOS
-- ============================================================
-- Identifica produtos com preço acima do limite superior do IQR
-- combinado com baixa satisfação do cliente — sinal de que o
-- preço elevado está gerando insatisfação e risco de perda de
-- demanda.
--
-- LÓGICA:
-- pricing_flag = 'overpriced' -> preço > price_upper_bound (IQR)
-- review_score < 4 -> satisfação abaixo do esperado
-- Combinação sugere que o preço alto está impactando negativamente
-- a percepção de valor pelo cliente.
--
-- FÓRMULAS:
-- recommended_price = (q1_price + q3_price) / 2 (mediana do IQR)
-- price_gap = avg_price - recommended_price (excesso de preço)
-- price_gap_pct = price_gap / avg_price * 100
-- revenue_at_risk = price_gap * total_items_sold
--   -> receita em risco se cliente migrar para concorrente
--
-- FILTROS:
-- pricing_flag = 'overpriced'  -> produtos acima do limite IQR
-- review_score < 4             -> insatisfação associada ao preço
-- total_items_sold >= 10       -> volume mínimo para significância
-- q1_price != q3_price         -> remove produtos com IQR = 0
--
-- NOTA METODOLÓGICA:
-- revenue_at_risk é uma estimativa conservadora — assume que
-- 100% dos itens seriam perdidos se o preço não for ajustado.
-- Em produção calibrar com taxa de churn real por categoria.
-- ============================================================

SELECT
    f.product_category_name,                                            -- categoria do produto
    f.product_id,                                                       -- identificador do produto
    p.avg_price AS product_avg_price,                                   -- preço médio histórico do produto
    p.min_price,                                                        -- preço mínimo registrado
    p.max_price,                                                        -- preço máximo registrado
    p.q1_price,                                                         -- 1º quartil de preço
    p.q3_price,                                                         -- 3º quartil de preço
    p.price_lower_bound,                                                -- limite inferior de preço (IQR)
    p.price_upper_bound,                                                -- limite superior de preço (IQR)
    p.pricing_flag,                                                     -- classificação de pricing do produto
    p.total_items_sold,                                                 -- total de unidades vendidas
    p.total_revenue,                                                    -- receita total do produto
    ROUND(AVG(f.review_score), 2) AS avg_review_score,                  -- satisfação média do produto
    ROUND(AVG(f.freight_ratio_pct), 2) AS avg_freight_ratio,            -- ratio frete/preço médio
    ROUND((p.q1_price + p.q3_price) / 2, 2) AS recommended_price,      -- preço recomendado (mediana IQR)
    ROUND(p.avg_price - ((p.q1_price + p.q3_price) / 2), 2) AS price_gap,           -- excesso de preço vs recomendado
    ROUND((p.avg_price - ((p.q1_price + p.q3_price) / 2)) /
          NULLIF(p.avg_price, 0) * 100, 2) AS price_gap_pct,           -- gap percentual acima do recomendado
    ROUND((p.avg_price - ((p.q1_price + p.q3_price) / 2)) *
          p.total_items_sold, 2) AS revenue_at_risk                     -- receita em risco por sobrepreço
FROM olist_db.marts.v_fact_orders_clean f
LEFT JOIN olist_db.marts.dim_products p
    ON f.product_id = p.product_id
WHERE p.pricing_flag = 'overpriced'                                     -- apenas produtos sobrepreçados
AND f.review_score < 4                                                  -- apenas produtos mal avaliados
AND p.total_items_sold >= 10                                            -- volume mínimo para significância
AND p.q1_price != p.q3_price                                            -- remove produtos com IQR = 0
GROUP BY
    f.product_category_name,
    f.product_id,
    p.avg_price,
    p.min_price,
    p.max_price,
    p.q1_price,
    p.q3_price,
    p.price_lower_bound,
    p.price_upper_bound,
    p.pricing_flag,
    p.total_items_sold,
    p.total_revenue
HAVING AVG(f.review_score) < 4                                          -- reforço do filtro de insatisfação
ORDER BY revenue_at_risk DESC                                           -- maior risco primeiro
LIMIT 20;

-- FINDINGS ANALYSIS 5:
-- 21 produtos sobrepreçados com review < 4 e volume >= 10 itens
-- revenue_at_risk total top 21: ~R$ 1.836
--
-- CASOS CRÍTICOS (review <= 2.0 + revenue_at_risk alto):
-- relogios_presentes (41c24b8c): review 1.67 — pior satisfação do dataset
--   price_gap_pct 5.2% mas 63 itens vendidos — risco de churn alto
-- malas_acessorios: review 1.86, R$ 216 em risco, frete ratio alto (27.22%)
--   combinação preço alto + frete pesado explica insatisfação
-- informatica_acessorios (dc9471): review 2.00, price_gap R$ 6.44
--
-- PADRÃO IDENTIFICADO:
-- informatica_acessorios aparece 5x — categoria com problema sistêmico
--   de sobrepreçamento (maior frequência no top 21)
-- telefonia (41db6d): freight_ratio 103.93% — frete maior que o preço!
--   outlier crítico: sobrepreço + frete absurdo + review 2.60
--
-- CRUZAMENTO COM ANALYSIS 4:
-- nenhuma categoria aparece simultaneamente em under e overpriced
--   com os mesmos filtros — sinal de consistência metodológica
--
-- COMPARATIVO:
-- revenue_opportunity (A4): ~R$ 1.050 (subprecificados)
-- revenue_at_risk (A5):     ~R$ 1.836 (sobrepreçados)
-- risco de perda supera oportunidade de ganho — priorizar A5
--
-- DECISÃO: priorizar redução de preço em informatica_acessorios
--   e investigar telefonia (41db6d) — possível erro de cadastro
--   frete 103.93% do preço é anomalia operacional, não pricing
-- PRÓXIMO PASSO: analysis 6 — impacto do frete na receita por categoria


-- ============================================================
-- ANALYSIS 6: IMPACTO DO FRETE NA RECEITA POR CATEGORIA
-- ============================================================
-- Analisa como o frete impacta a receita por categoria,
-- identificando categorias onde o frete é um fator crítico
-- de decisão de compra e possível inibidor de demanda.
--
-- FÓRMULAS:
-- freight_ratio_pct = freight_value / price * 100
-- freight_revenue_impact = SUM(freight_value) / SUM(price) * 100
-- net_revenue_pct = 100 - freight_revenue_impact
-- avg_order_value = SUM(price) / COUNT(DISTINCT order_id)
--
-- CLASSIFICAÇÃO DE IMPACTO DO FRETE:
-- critical  -> frete > 40% da receita bruta — inibidor de demanda
-- high      -> frete 25-40% da receita bruta — risco relevante
-- moderate  -> frete 15-25% da receita bruta — monitorar
-- low       -> frete < 15% da receita bruta — saudável
--
-- DECISÃO DE NEGÓCIO:
-- categorias critical: candidatas a frete grátis subsidiado
--   ou revisão de política de frete para estimular conversão
-- categorias high: avaliar negociação logística ou bundling
--   para diluir impacto do frete no ticket médio
--
-- NOTA METODOLÓGICA:
-- freight_value = valor cobrado DO cliente, não custo logístico.
-- Categorias com itens grandes/pesados naturalmente terão
-- freight_ratio alto — comparar com avg_product_weight
-- se disponível na dim_products.
-- ============================================================

SELECT
    f.product_category_name,                                            -- categoria do produto
    COUNT(*) AS total_items,                                            -- total de itens vendidos
    COUNT(DISTINCT f.order_id) AS total_orders,                         -- pedidos únicos
    ROUND(AVG(f.price), 2) AS avg_price,                                -- preço médio de venda
    ROUND(AVG(f.freight_value), 2) AS avg_freight,                      -- frete médio cobrado ao cliente
    ROUND(SUM(f.freight_value) / NULLIF(SUM(f.price), 0) * 100, 2)
        AS freight_revenue_impact_pct,                                  -- % da receita bruta consumida pelo frete
    ROUND(100 - SUM(f.freight_value) /
          NULLIF(SUM(f.price), 0) * 100, 2) AS net_revenue_pct,        -- % da receita retida após frete
    ROUND(SUM(f.price), 2) AS total_revenue,                            -- receita bruta total
    ROUND(SUM(f.freight_value), 2) AS total_freight_cost,               -- total cobrado em frete
    ROUND(SUM(f.price) - SUM(f.freight_value), 2) AS total_net_revenue, -- receita líquida total
    ROUND(SUM(f.price) / NULLIF(COUNT(DISTINCT f.order_id), 0), 2)
        AS avg_order_value,                                             -- ticket médio por pedido
    ROUND(AVG(f.review_score), 2) AS avg_review_score,                  -- satisfação média da categoria
    ROUND(CORR(f.freight_value, f.review_score), 4)
        AS freight_review_correlation,                                  -- correlação frete x satisfação
    CASE
        WHEN SUM(f.freight_value) /
             NULLIF(SUM(f.price), 0) * 100 > 40 THEN 'critical'        -- frete > 40% da receita
        WHEN SUM(f.freight_value) /
             NULLIF(SUM(f.price), 0) * 100 > 25 THEN 'high'            -- frete 25-40% da receita
        WHEN SUM(f.freight_value) /
             NULLIF(SUM(f.price), 0) * 100 > 15 THEN 'moderate'        -- frete 15-25% da receita
        ELSE 'low'                                                       -- frete < 15% da receita
    END AS freight_impact_flag                                          -- classificação de impacto do frete
FROM olist_db.marts.v_fact_orders_clean f
WHERE f.product_category_name IS NOT NULL
AND f.freight_value IS NOT NULL
GROUP BY f.product_category_name
HAVING COUNT(*) >= 50                                                   -- volume mínimo para significância
ORDER BY freight_revenue_impact_pct DESC                                -- maior impacto primeiro
LIMIT 25;

-- FINDINGS ANALYSIS 6:
-- 25 categorias com volume >= 50 itens analisadas
-- nenhuma categoria em 'critical' (frete > 40%) — positivo
-- 8 categorias em 'high' (frete 25-40%): artigos_de_natal, sinalizacao,
--   alimentos_bebidas, eletronicos, moveis_sala, moveis_cozinha,
--   bebidas, moveis_escritorio
-- 17 categorias em 'moderate' (frete 15-25%)
--
-- CRUZAMENTO COM ANALYSIS 1 (under_pressure):
-- eletronicos: under_pressure (A1) + high freight impact (A6)
--   duplo problema confirmado — prioridade máxima
-- artigos_de_natal: under_pressure (A1) + high (A6) — mesmo padrão
--
-- CORRELAÇÃO FRETE x SATISFAÇÃO (freight_review_correlation):
-- moveis_sala: -0.1398 — frete alto inibindo satisfação
-- fashion_underwear: -0.2886 — correlação negativa mais forte
-- moveis_quarto: -0.2510 — segundo maior impacto negativo
-- moveis_escritorio: review médio 3.49 — pior satisfação do resultado
--   combinado com high freight impact — candidata a política de frete grátis
--
-- OUTLIER POSITIVO:
-- dvds_blu_ray: correlação +0.1187 — frete alto associado a
--   maior satisfação — possível perfil de comprador menos sensível a frete
--
-- DECISÃO:
-- priorizar moveis_escritorio: review 3.49 + high freight + correlação negativa
-- investigar fashion_underwear: maior correlação negativa frete x satisfação
-- eletronicos: ação dupla — revisar preço mínimo (A1) + negociar logística
-- PRÓXIMO PASSO: analysis 7 — oportunidade de receita por segmento RFM


-- ============================================================
-- ANALYSIS 7: OPORTUNIDADE DE RECEITA POR SEGMENTO RFM
-- ============================================================
-- Cruza segmentação RFM de clientes com comportamento de pricing
-- para identificar em quais segmentos há maior oportunidade de
-- aumento de receita via ajuste de preço ou estratégia comercial.
--
-- SEGMENTOS RFM (esperados da dim_customers):
-- champions        -> compradores recentes, frequentes e alto valor
-- loyal_customers  -> frequentes mas não necessariamente recentes
-- potential        -> recentes mas baixa frequência/valor
-- at_risk          -> compraram bem antes mas sumiram
-- lost             -> inativos há muito tempo
--
-- FÓRMULAS:
-- avg_ticket = SUM(price) / COUNT(DISTINCT order_id)
-- revenue_per_customer = SUM(price) / COUNT(DISTINCT customer_id)
-- freight_burden_pct = SUM(freight_value) / SUM(price) * 100
-- upsell_opportunity = (avg_ticket_champions - avg_ticket_segment)
--                      * total_orders_segment
--   -> receita incremental se segmento atingir ticket de champions
--
-- DECISÃO DE NEGÓCIO:
-- champions: proteger — não aumentar preço de forma agressiva
-- loyal + potential: upsell — aumentar ticket médio gradualmente
-- at_risk + lost: reativação — promoção ou desconto estratégico
--
-- NOTA METODOLÓGICA:
-- upsell_opportunity assume que todos os clientes do segmento
-- podem atingir o ticket médio de champions — estimativa otimista.
-- Em produção calibrar com taxa de conversão real por segmento.
-- ============================================================

WITH segment_metrics AS (
    SELECT
        c.rfm_segment,                                                      -- segmento RFM do cliente
        COUNT(DISTINCT f.customer_id) AS total_customers,                   -- clientes únicos no segmento
        COUNT(DISTINCT f.order_id) AS total_orders,                         -- pedidos únicos no segmento
        COUNT(*) AS total_items,                                            -- total de itens vendidos
        ROUND(AVG(f.price), 2) AS avg_price,                                -- preço médio do segmento
        ROUND(SUM(f.price), 2) AS total_revenue,                            -- receita total do segmento
        ROUND(SUM(f.price) /
              NULLIF(COUNT(DISTINCT f.order_id), 0), 2) AS avg_ticket,      -- ticket médio por pedido
        ROUND(SUM(f.price) /
              NULLIF(COUNT(DISTINCT f.customer_id), 0), 2)
              AS revenue_per_customer,                                      -- receita média por cliente
        ROUND(SUM(f.freight_value) /
              NULLIF(SUM(f.price), 0) * 100, 2) AS freight_burden_pct,     -- % da receita consumida pelo frete
        ROUND(AVG(f.review_score), 2) AS avg_review_score                   -- satisfação média do segmento
    FROM olist_db.marts.v_fact_orders_clean f
    LEFT JOIN olist_db.marts.dim_customers c
        ON f.customer_id = c.customer_id
    WHERE c.rfm_segment IS NOT NULL
    GROUP BY c.rfm_segment
),
champions_ticket AS (
    -- ticket médio de champions como benchmark de upsell
    SELECT avg_ticket AS champions_avg_ticket
    FROM segment_metrics
    WHERE rfm_segment = 'champions'
)
SELECT
    sm.rfm_segment,                                                         -- segmento RFM
    sm.total_customers,                                                     -- clientes únicos
    sm.total_orders,                                                        -- pedidos únicos
    sm.total_items,                                                         -- itens vendidos
    sm.avg_price,                                                           -- preço médio
    sm.avg_ticket,                                                          -- ticket médio por pedido
    sm.revenue_per_customer,                                                -- receita por cliente
    sm.total_revenue,                                                       -- receita total
    sm.freight_burden_pct,                                                  -- % frete na receita
    sm.avg_review_score,                                                    -- satisfação média
    ct.champions_avg_ticket,                                                -- benchmark champions
    ROUND(ct.champions_avg_ticket - sm.avg_ticket, 2) AS ticket_gap,       -- gap vs champions
    ROUND((ct.champions_avg_ticket - sm.avg_ticket) *
          sm.total_orders, 2) AS upsell_opportunity                        -- oportunidade incremental de receita
FROM segment_metrics sm
CROSS JOIN champions_ticket ct
ORDER BY sm.total_revenue DESC;                                             -- maior receita primeiro

-- FINDINGS ANALYSIS 7:
-- ALERTA CRÍTICO: resultados indicam problema na segmentação RFM
--   em dim_customers — revisar antes de usar para decisão
--
-- ANOMALIAS IDENTIFICADAS:
-- 1. champions (32 clientes) tem avg_ticket R$ 36.45 — o MENOR do dataset
--    champions deveria ter o maior ticket médio por definição RFM
--    resultado invertido indica erro na classificação do segmento
--
-- 2. potential (42.864 clientes) avg_ticket R$ 238.61
--    loyal (53.552 clientes) avg_ticket R$ 55.70
--    potential com ticket maior que loyal — inconsistente com RFM padrão
--
-- 3. total_customers = total_orders em potential e loyal (42864 = 42864)
--    indica que cada cliente tem exatamente 1 pedido — possível erro
--    no JOIN ou na granularidade da dim_customers
--
-- 4. upsell_opportunity negativo em todos os segmentos
--    consequência direta do champions_avg_ticket ser o menor —
--    o benchmark está invertido
--
-- 5. at_risk (30) e champions (32) com volume irrisório
--    insuficiente para qualquer decisão de pricing
--
-- DIAGNÓSTICO:
-- provável problema na lógica de scoring RFM em dim_customers
-- revisar cálculo de R (recency), F (frequency) e M (monetary)
--   e reclassificação dos segmentos no 06_gold_modelagem.sql
--
-- DECISÃO: Analysis 7 suspensa até correção do RFM
--   não usar upsell_opportunity para recomendações na Analysis 8
-- PRÓXIMO PASSO: analysis 8 — resumo executivo (sem dados de RFM)
--   + tarefa adicional: revisão do RFM em dim_customers


-- ============================================================
-- ANALYSIS 8: RESUMO EXECUTIVO DE RECOMENDAÇÕES DE PRICING
-- ============================================================
-- Consolida os principais insights das analyses 1 a 6 em um
-- resumo executivo orientado a decisão — Decision Centric Analytics.
-- Cada recomendação tem prioridade, ação sugerida e impacto estimado.
--
-- ANÁLISES BASE:
-- A1: receita líquida e margem de frete por categoria
-- A2: proxy de elasticidade-preço por categoria
-- A3: price index por região
-- A4: produtos subprecificados (revenue_opportunity)
-- A5: produtos sobrepreçados (revenue_at_risk)
-- A6: impacto do frete na receita por categoria
-- A7: suspensa — revisão de RFM pendente (06_gold_modelagem.sql)
--
-- ESTRUTURA DA RECOMENDAÇÃO:
-- priority     -> P1 (crítico), P2 (alto), P3 (monitorar)
-- action       -> ação recomendada de negócio
-- impact       -> estimativa de impacto financeiro ou operacional
-- evidence     -> análise de origem do insight
-- ============================================================

-- ============================================================
-- PARTE 1: VISÃO CONSOLIDADA POR CATEGORIA
-- Agrega os principais indicadores de pricing por categoria
-- cruzando dados de margem, frete, elasticidade e pricing_flag
-- ============================================================

WITH category_summary AS (
    SELECT
        f.product_category_name,                                        -- categoria do produto
        COUNT(*) AS total_items,                                        -- total de itens vendidos
        ROUND(AVG(f.price), 2) AS avg_price,                            -- preço médio
        ROUND(AVG(f.freight_value), 2) AS avg_freight,                  -- frete médio
        ROUND(SUM(f.freight_value) /
              NULLIF(SUM(f.price), 0) * 100, 2) AS freight_impact_pct, -- % frete na receita
        ROUND(AVG((f.price - f.freight_value) /
              NULLIF(f.price, 0) * 100), 2) AS freight_margin_pct,      -- margem após frete %
        ROUND(SUM(f.price), 2) AS total_revenue,                        -- receita bruta total
        ROUND(AVG(f.review_score), 2) AS avg_review_score,              -- satisfação média
        COUNT(CASE WHEN p.pricing_flag = 'overpriced'
            THEN 1 END) AS overpriced_items,                            -- itens sobrepreçados
        COUNT(CASE WHEN p.pricing_flag = 'underpriced'
            THEN 1 END) AS underpriced_items,                           -- itens subprecificados
        -- classificação de margem (da analysis 1)
        CASE
            WHEN AVG((f.price - f.freight_value) /
                 NULLIF(f.price, 0) * 100) >= 70 THEN 'healthy'
            WHEN AVG((f.price - f.freight_value) /
                 NULLIF(f.price, 0) * 100) >= 50 THEN 'acceptable'
            WHEN AVG((f.price - f.freight_value) /
                 NULLIF(f.price, 0) * 100) >= 0  THEN 'under_pressure'
            ELSE 'freight_exceeds_price'
        END AS margin_health,                                           -- saúde da margem
        -- classificação de impacto do frete (da analysis 6)
        CASE
            WHEN SUM(f.freight_value) /
                 NULLIF(SUM(f.price), 0) * 100 > 40 THEN 'critical'
            WHEN SUM(f.freight_value) /
                 NULLIF(SUM(f.price), 0) * 100 > 25 THEN 'high'
            WHEN SUM(f.freight_value) /
                 NULLIF(SUM(f.price), 0) * 100 > 15 THEN 'moderate'
            ELSE 'low'
        END AS freight_impact_flag                                      -- impacto do frete
    FROM olist_db.marts.v_fact_orders_clean f
    LEFT JOIN olist_db.marts.dim_products p
        ON f.product_id = p.product_id
    WHERE f.product_category_name IS NOT NULL
    GROUP BY f.product_category_name
    HAVING COUNT(*) >= 50                                               -- volume mínimo para significância
)
SELECT
    product_category_name,
    total_items,
    avg_price,
    avg_freight,
    freight_impact_pct,
    freight_margin_pct,
    total_revenue,
    avg_review_score,
    overpriced_items,
    underpriced_items,
    margin_health,
    freight_impact_flag,
    -- SCORE DE PRIORIDADE: combina margem + frete + satisfação
    CASE
        WHEN margin_health = 'under_pressure'
         AND freight_impact_flag IN ('critical', 'high')
         AND avg_review_score < 4    THEN 'P1_critical'                 -- triplo problema
        WHEN margin_health = 'under_pressure'
         AND freight_impact_flag IN ('critical', 'high') THEN 'P1_critical' -- margem + frete
        WHEN margin_health = 'under_pressure'
          OR freight_impact_flag IN ('critical', 'high') THEN 'P2_high' -- problema isolado
        WHEN avg_review_score < 3.8
          OR overpriced_items > 0    THEN 'P2_high'                     -- satisfação baixa
        ELSE 'P3_monitor'                                               -- monitorar
    END AS pricing_priority                                             -- prioridade de ação
FROM category_summary
ORDER BY
    CASE pricing_priority
        WHEN 'P1_critical' THEN 1
        WHEN 'P2_high'     THEN 2
        ELSE 3
    END,
    total_revenue DESC;                                                 -- dentro da prioridade, maior receita primeiro

-- ============================================================
-- PARTE 2: RECOMENDAÇÕES EXECUTIVAS CONSOLIDADAS
-- Tabela estática de recomendações baseada nos findings
-- das analyses 1 a 6 — orientada a decisão de negócio
-- ============================================================

SELECT * FROM VALUES

-- P1: CRÍTICOS — ação imediata
('P1', 'eletronicos',
    'revisar_preco_minimo',
    'Categoria under_pressure (A1) + high freight impact (A6) + 611 itens com margem negativa. Definir preço mínimo que cubra freight_value médio de R$16.83.',
    'Recuperar margem em ~22% dos 2.767 itens vendidos',
    'A1, A6'),

('P1', 'moveis_escritorio',
    'politica_frete_gratis',
    'Pior review do dataset (3.49) + high freight impact (A6) + correlação negativa frete-satisfação. Subsidiar frete para pedidos acima de R$150.',
    'Reduzir churn e melhorar NPS da categoria',
    'A6'),

('P1', 'telefonia',
    'revisar_preco_minimo_e_anomalia',
    'under_pressure (A1) + 430 itens margem negativa + produto 41db6d com freight_ratio 103.93% (A5). Investigar anomalia operacional e revisar preço mínimo.',
    'Recuperar margem em ~9.5% dos 4.545 itens + corrigir anomalia cadastral',
    'A1, A5'),

-- P2: ALTO — ação planejada
('P2', 'informatica_acessorios',
    'reducao_de_preco_overpriced',
    '5 produtos sobrepreçados com review médio 2.0 (A5). Reduzir preço dos SKUs identificados para mediana do IQR. Revenue at risk: ~R$418.',
    'Recuperar satisfação e reduzir risco de churn nos SKUs críticos',
    'A5'),

('P2', 'fashion_underwear_e_moda_praia',
    'negociacao_logistica',
    'Maior correlação negativa frete x satisfação do dataset: -0.2886 (A6). Negociar contrato logístico ou oferecer frete grátis acima de ticket mínimo.',
    'Reduzir impacto do frete na satisfação da categoria',
    'A6'),

('P2', 'ferramentas_jardim',
    'ajuste_preco_subprecificado',
    'Produto 52c80ced com revenue_opportunity R$684.99 (A4). Review 4.76, gap 3.34%. Ajuste cirúrgico de baixo risco.',
    'Incremento de ~R$685 na receita com risco mínimo de perda de demanda',
    'A4'),

('P2', 'MA_below_market',
    'teste_aumento_preco_regional',
    'Único estado below_market com volume relevante (405 itens, price_index 74.51 — A3). Espaço de ~25% de aumento antes de atingir média nacional.',
    'Oportunidade de pricing regional sem perda de competitividade',
    'A3'),

-- P3: MONITORAR
('P3', 'telefonia_fixa',
    'monitorar_elasticidade',
    'Única categoria com correlação elástica forte (-0.3733 — A2). Qualquer aumento de preço deve ser testado com cautela via A/B.',
    'Evitar perda de demanda em categoria sensível a preço',
    'A2'),

('P3', 'RFM_segmentation',
    'corrigir_rfm_em_gold_modelagem',
    'Analysis 7 suspensa por inconsistência na segmentação RFM (champions com menor ticket). Revisar scoring em 06_gold_modelagem.sql.',
    'Habilitar análise de upsell por segmento de cliente',
    'A7')

AS recommendations (priority, category, action, rationale, expected_impact, source_analysis)
ORDER BY priority, category;

-- FINDINGS ANALYSIS 8 — RESUMO EXECUTIVO:
--
-- PARTE 1 — VISÃO POR CATEGORIA:
-- 4 categorias P1_critical: eletronicos, sinalizacao_e_seguranca,
--   artigos_de_natal — todas under_pressure + high freight
-- NOTA: sinalizacao e artigos_de_natal entraram como P1_critical
--   pela lógica do score mas têm volume baixo (199 e 153 itens)
--   — tratar com cautela, priorizar eletronicos e telefonia
-- telefonia classificada P2_high na parte 1 (under_pressure + moderate)
--   mas P1 na parte 2 (evidência adicional de anomalia A5)
--   — manter como P1 na decisão final
-- moveis_escritorio: healthy margin mas high freight + review 3.49
--   score capturou corretamente como P2_high via avg_review_score
--
-- PARTE 2 — RECOMENDAÇÕES EXECUTIVAS:
-- 3 ações P1 confirmadas: eletronicos, moveis_escritorio, telefonia
-- 4 ações P2: MA regional, fashion_underwear, ferramentas_jardim,
--   informatica_acessorios
-- 2 itens P3: RFM pendente + monitoramento telefonia_fixa
--
-- CONSISTÊNCIA ENTRE PARTES:
-- parte 1 e parte 2 alinhadas nos casos críticos — validação cruzada ok
-- divergência esperada: parte 1 é dinâmica (agregação do dataset),
--   parte 2 é estática (recomendações baseadas nos findings anteriores)
--
-- 08_pricing_analysis.sql CONCLUÍDO ✅
-- PRÓXIMOS PASSOS DO PROJETO:
-- [ ] corrigir RFM em 06_gold_modelagem.sql
-- [ ] 09_semantic_views.sql — camada semântica para BI
-- [ ] 10_powerbi_views.sql — views otimizadas para Power BI