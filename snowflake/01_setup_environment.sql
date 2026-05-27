-- PROJECT: Olist Pricing & BI Analytics
-- FILE: 01_setup_environment.sql
-- AUTHOR: Gisele CP
-- DATE: 2026-05-25

-- STEP 1: Create Virtual Warehouse
CREATE WAREHOUSE IF NOT EXISTS olist_wh
  WITH WAREHOUSE_SIZE = 'X-SMALL'
  AUTO_SUSPEND = 60
  AUTO_RESUME = TRUE
  COMMENT = 'Warehouse for Olist Pricing and BI Analytics project';

-- STEP 2: Create Database
CREATE DATABASE IF NOT EXISTS olist_db
  COMMENT = 'Olist Brazilian E-Commerce - Pricing and BI Analytics';

-- STEP 3: Create Schemas
CREATE SCHEMA IF NOT EXISTS olist_db.raw
  COMMENT = 'Raw layer - original data loaded without transformation';

CREATE SCHEMA IF NOT EXISTS olist_db.staging
  COMMENT = 'Staging layer - cleaned and standardized by dbt';

CREATE SCHEMA IF NOT EXISTS olist_db.marts
  COMMENT = 'Marts layer - business ready tables for BI consumption';

-- STEP 4: Validation
SHOW WAREHOUSES LIKE 'olist_wh';
SHOW DATABASES LIKE 'olist_db';
SHOW SCHEMAS IN DATABASE olist_db;