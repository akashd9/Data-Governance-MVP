-- 06_audit_lineage_demo.sql
-- Demonstrates governance observability using Unity Catalog system tables.
-- Read-only: no objects are created or modified by this file.
USE CATALOG datagovernancemvp;

-- Recent Unity Catalog activity (DDL/DML/grants) touching this catalog.
SELECT
  event_time,
  user_identity.email AS user_email,
  action_name,
  request_params.full_name_arg AS object_name
FROM system.access.audit
WHERE service_name = 'unityCatalog'
  AND request_params.full_name_arg LIKE 'datagovernancemvp%'
ORDER BY event_time DESC
LIMIT 100;

-- Table-level lineage feeding into the gold layer (bronze -> silver -> gold).
SELECT
  source_table_full_name,
  target_table_full_name,
  source_type,
  target_type,
  event_time
FROM system.access.table_lineage
WHERE target_table_catalog = 'datagovernancemvp'
ORDER BY event_time DESC
LIMIT 200;

-- PII/classification tags currently applied across the catalog's columns.
SELECT catalog_name, schema_name, table_name, column_name, tag_name, tag_value
FROM datagovernancemvp.information_schema.column_tags
ORDER BY table_name, column_name;

-- Grants currently in effect across the catalog's schemas and tables.
SELECT grantee, privilege_type, table_schema, table_name
FROM datagovernancemvp.information_schema.table_privileges
ORDER BY table_schema, table_name, grantee;
