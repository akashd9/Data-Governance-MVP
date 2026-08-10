-- 00_setup_catalog_schemas.sql
-- Creates the medallion schemas and the governance utility schema inside datagovernancemvp.
USE CATALOG datagovernancemvp;

CREATE SCHEMA IF NOT EXISTS bronze
  COMMENT 'Raw ingested data, unvalidated, append-only landing tables';

CREATE SCHEMA IF NOT EXISTS silver
  COMMENT 'Cleaned, conformed, constrained tables with PII present';

CREATE SCHEMA IF NOT EXISTS gold
  COMMENT 'Business-level aggregates and curated tables for consumption';

CREATE SCHEMA IF NOT EXISTS governance
  COMMENT 'Masking functions, row filters, and data quality/audit utilities';

ALTER CATALOG datagovernancemvp SET TAGS ('domain' = 'banking', 'project' = 'data_governance_mvp');

COMMENT ON CATALOG datagovernancemvp IS
  'Data Governance MVP: banking/fraud medallion pipeline (bronze/silver/gold) with Unity Catalog
   column masking, row filters, tags, and grants scoped to analysts, fraud_investigators,
   compliance_officers and data_engineers.';
