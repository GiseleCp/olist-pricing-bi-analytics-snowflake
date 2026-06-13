-- ============================================================
-- PROJETO: Olist Pricing Intelligence
-- ARQUIVO: 01_setup_environment.sql
-- DESCRIÇÃO: Configuração inicial do ambiente para o projeto
--            Olist Pricing Intelligence. Cria o warehouse,
--            banco de dados e as três camadas de schema seguindo
--            o padrão de Arquitetura Medallion.
-- AUTORA: Gisele CP
-- DATA: 2026-06-06
-- ============================================================

-- VISÃO GERAL DA ARQUITETURA MEDALLION
-- Este projeto segue o padrão de Arquitetura Medallion:
--
-- RAW (Bronze)     -> Camada de ingestão. Dados carregados
--                     exatamente como recebidos da origem.
--                     Nenhuma transformação. Preserva os dados originais.
--
-- STAGING (Silver) -> Camada tratada e enriquecida. Conversão
--                     de tipos, tratamento de nulos e aplicação
--                     de regras de negócio.
--                     Aplicação de regras de qualidade e padronização dos dados.
--
-- MARTS (Gold)     -> Camada pronta para consumo pelo negócio.
--                     Modelagem dimensional (Star Schema).
--                     Métricas agregadas e KPIs para BI
--                     e suporte a decisões de precificação.

-- ============================================================
-- ETAPA 1: CRIAÇÃO DO VIRTUAL WAREHOUSE
-- ============================================================
-- Um Virtual Warehouse representa a camada computacional
-- do Snowflake.
-- Ele processa todas as consultas SQL e operações de carga.
-- O tamanho X-SMALL é suficiente para desenvolvimento
-- e para a escala deste projeto.
-- AUTO_SUSPEND = 60 segundos economiza créditos quando
-- não há atividade.
-- AUTO_RESUME = TRUE garante que o warehouse seja iniciado
-- automaticamente quando uma nova consulta for executada.
-- ============================================================

CREATE WAREHOUSE IF NOT EXISTS olist_wh
  WITH WAREHOUSE_SIZE = 'X-SMALL'    -- menor tamanho, otimizado para custos em desenvolvimento
  AUTO_SUSPEND = 60                  -- suspende após 60 segundos de inatividade
  AUTO_RESUME = TRUE                 -- reinicia automaticamente quando necessário
  COMMENT = 'Warehouse do projeto Olist Pricing Intelligence';

-- ============================================================
-- ETAPA 2: CRIAÇÃO DO BANCO DE DADOS
-- ============================================================
-- O banco de dados é o contêiner principal no Snowflake.
-- Todos os schemas, tabelas e objetos ficam armazenados nele.
-- O uso de IF NOT EXISTS torna o script idempotente,
-- permitindo sua execução múltiplas vezes sem erros.
-- ============================================================

CREATE DATABASE IF NOT EXISTS olist_db
  COMMENT = 'Olist Brazilian E-Commerce - Pricing Intelligence';

-- ============================================================
-- ETAPA 3: CRIAÇÃO DOS SCHEMAS
-- ============================================================
-- Schemas são contêineres lógicos dentro do banco de dados.
-- Cada schema representa uma camada da Arquitetura Medallion.
-- A separação das camadas garante governança de dados e
-- rastreabilidade (lineage):
-- os dados fluem apenas RAW -> STAGING -> MARTS,
-- nunca no sentido contrário.
-- ============================================================

-- Camada RAW: recebe os dados exatamente como carregados dos arquivos CSV
-- Nenhuma transformação é permitida — preserva os dados originais da fonte
CREATE SCHEMA IF NOT EXISTS olist_db.raw
  COMMENT = 'Camada RAW - dados originais carregados sem transformação';

-- Camada STAGING: dados tratados, tipados e enriquecidos
-- Todas as regras de negócio e tratamentos de qualidade são aplicados aqui
CREATE SCHEMA IF NOT EXISTS olist_db.staging
  COMMENT = 'Camada STAGING - dados limpos e padronizados';

-- Camada MARTS: tabelas prontas para consumo do negócio
-- Modelagem dimensional com fatos e dimensões para BI e análises de precificação
CREATE SCHEMA IF NOT EXISTS olist_db.marts
  COMMENT = 'Camada MARTS - tabelas prontas para consumo analítico';

-- ============================================================
-- ETAPA 4: VALIDAÇÃO
-- ============================================================
-- Confirma que todos os objetos foram criados com sucesso.
-- Resultados esperados:
-- SHOW WAREHOUSES -> 1 linha: olist_wh
-- SHOW DATABASES  -> 1 linha: olist_db
-- SHOW SCHEMAS    -> 4 linhas: INFORMATION_SCHEMA, RAW, STAGING, MARTS
-- ============================================================

SHOW WAREHOUSES LIKE 'olist_wh';
SHOW DATABASES LIKE 'olist_db';
SHOW SCHEMAS IN DATABASE olist_db;