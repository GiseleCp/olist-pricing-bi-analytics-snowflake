-- ============================================================
-- PROJECT: Olist Pricing Intelligence
-- FILE: 01_setup_environment.sql
-- DESCRIPTION: Initial environment setup for the Olist Pricing
--              Intelligence project. Creates the virtual warehouse,
--              database and the three schema layers following the
--              Medallion Architecture pattern.
-- AUTHOR: Gisele CP
-- DATE: 2026-06-06
-- ============================================================

-- MEDALLION ARCHITECTURE OVERVIEW
-- This project follows the Medallion Architecture pattern:
--
-- RAW (Bronze)     -> Landing zone. Data loaded as-is from source.
--                     No transformations. Preserves original data.
--
-- STAGING (Silver) -> Cleaned and enriched layer. Type casting,
--                     null treatment, business rules applied.
--                     Data quality guaranteed.
--
-- MARTS (Gold)     -> Business-ready layer. Star schema modeling.
--                     Aggregated metrics and KPIs for BI consumption
--                     and pricing decision support.

-- ============================================================
-- STEP 1: CREATE VIRTUAL WAREHOUSE
-- ============================================================
-- A virtual warehouse is the compute layer in Snowflake.
-- It processes all SQL queries and data loading operations.
-- X-SMALL size is sufficient for development and this project scale.
-- AUTO_SUSPEND = 60 seconds saves credits when idle.
-- AUTO_RESUME = TRUE ensures the warehouse starts automatically
-- when a new query is submitted.
-- ============================================================

CREATE WAREHOUSE IF NOT EXISTS olist_wh
  WITH WAREHOUSE_SIZE = 'X-SMALL'    -- smallest size, cost optimized for development
  AUTO_SUSPEND = 60                   -- suspends after 60 seconds of inactivity
  AUTO_RESUME = TRUE                  -- resumes automatically on new query
  COMMENT = 'Warehouse for Olist Pricing Intelligence project';

-- ============================================================
-- STEP 2: CREATE DATABASE
-- ============================================================
-- The database is the top-level container in Snowflake.
-- All schemas, tables and objects live inside this database.
-- Using IF NOT EXISTS to make the script idempotent —
-- safe to run multiple times without errors.
-- ============================================================

CREATE DATABASE IF NOT EXISTS olist_db
  COMMENT = 'Olist Brazilian E-Commerce - Pricing Intelligence';

-- ============================================================
-- STEP 3: CREATE SCHEMAS
-- ============================================================
-- Schemas are logical containers inside the database.
-- Each schema represents one layer of the Medallion Architecture.
-- Separating layers ensures data governance and clear lineage:
-- data flows only forward RAW -> STAGING -> MARTS, never backward.
-- ============================================================

-- RAW layer: receives data exactly as loaded from CSV files
-- No transformations allowed — preserves the original source data
CREATE SCHEMA IF NOT EXISTS olist_db.raw
  COMMENT = 'Raw layer - original data loaded without transformation';

-- STAGING layer: cleaned, typed and enriched data
-- All business rules and data quality treatments applied here
CREATE SCHEMA IF NOT EXISTS olist_db.staging
  COMMENT = 'Staging layer - cleaned and standardized data';

-- MARTS layer: business-ready aggregated tables
-- Star schema with facts and dimensions for BI and pricing analysis
CREATE SCHEMA IF NOT EXISTS olist_db.marts
  COMMENT = 'Marts layer - business ready tables for BI consumption';

-- ============================================================
-- STEP 4: VALIDATION
-- ============================================================
-- Confirms all objects were created successfully.
-- Expected results:
-- SHOW WAREHOUSES -> 1 row: olist_wh
-- SHOW DATABASES  -> 1 row: olist_db
-- SHOW SCHEMAS    -> 4 rows: INFORMATION_SCHEMA, RAW, STAGING, MARTS
-- ============================================================

SHOW WAREHOUSES LIKE 'olist_wh';
SHOW DATABASES LIKE 'olist_db';
SHOW SCHEMAS IN DATABASE olist_db;