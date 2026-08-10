-- 04_governance_apply.sql
-- Unity Catalog governance layer: PII tags, column masking, row-level security, and grants
-- scoped to the workspace groups: data_engineers, analysts, fraud_investigators, compliance_officers.
USE CATALOG datagovernancemvp;

-- ============================================================================
-- 1. Masking functions
--    compliance_officers, data_engineers and admins see unmasked values;
--    everyone else (analysts, fraud_investigators) sees masked values.
-- ============================================================================
CREATE OR REPLACE FUNCTION governance.mask_ssn(ssn STRING)
RETURN CASE
  WHEN is_account_group_member('compliance_officers')
    OR is_account_group_member('data_engineers')
    OR is_account_group_member('admins') THEN ssn
  ELSE concat('XXX-XX-', right(ssn, 4))
END;

CREATE OR REPLACE FUNCTION governance.mask_email(email STRING)
RETURN CASE
  WHEN is_account_group_member('compliance_officers')
    OR is_account_group_member('data_engineers')
    OR is_account_group_member('admins') THEN email
  ELSE concat('***@', split(email, '@')[1])
END;

CREATE OR REPLACE FUNCTION governance.mask_phone(phone STRING)
RETURN CASE
  WHEN is_account_group_member('compliance_officers')
    OR is_account_group_member('data_engineers')
    OR is_account_group_member('admins') THEN phone
  ELSE concat('XXX-XXX-', right(phone, 4))
END;

-- ============================================================================
-- 2. Row filter
--    fraud_investigators only see customers who have at least one flagged
--    transaction; every other granted role sees all rows.
-- ============================================================================
CREATE OR REPLACE FUNCTION governance.customer_360_row_filter(flagged_txn_count INT)
RETURN NOT is_account_group_member('fraud_investigators') OR flagged_txn_count > 0;

-- ============================================================================
-- 3. Apply masks + row filter
--    Note: Unity Catalog does not allow column masks on tables that carry
--    CHECK constraints, and silver.customers has one (chk_customers_dob).
--    That's fine here: silver is only granted to data_engineers/
--    compliance_officers, both already unmasked by the functions above, so
--    masks are applied at the gold layer where analysts/fraud_investigators
--    actually query.
-- ============================================================================
ALTER TABLE gold.customer_360 ALTER COLUMN ssn   SET MASK governance.mask_ssn;
ALTER TABLE gold.customer_360 ALTER COLUMN email SET MASK governance.mask_email;
ALTER TABLE gold.customer_360 ALTER COLUMN phone SET MASK governance.mask_phone;

ALTER TABLE gold.customer_360 SET ROW FILTER governance.customer_360_row_filter ON (flagged_txn_count);

-- ============================================================================
-- 4. Classification tags (catalog / schema / column level)
-- ============================================================================
ALTER SCHEMA silver SET TAGS ('layer' = 'silver', 'contains_pii' = 'true');
ALTER SCHEMA gold   SET TAGS ('layer' = 'gold');
ALTER SCHEMA governance SET TAGS ('purpose' = 'governance_utilities');

ALTER TABLE silver.customers ALTER COLUMN ssn   SET TAGS ('pii_category' = 'ssn',   'sensitivity' = 'restricted');
ALTER TABLE silver.customers ALTER COLUMN email SET TAGS ('pii_category' = 'email', 'sensitivity' = 'confidential');
ALTER TABLE silver.customers ALTER COLUMN phone SET TAGS ('pii_category' = 'phone', 'sensitivity' = 'confidential');
ALTER TABLE silver.customers ALTER COLUMN dob   SET TAGS ('pii_category' = 'dob',   'sensitivity' = 'confidential');

ALTER TABLE gold.customer_360 ALTER COLUMN ssn   SET TAGS ('pii_category' = 'ssn',   'sensitivity' = 'restricted');
ALTER TABLE gold.customer_360 ALTER COLUMN email SET TAGS ('pii_category' = 'email', 'sensitivity' = 'confidential');
ALTER TABLE gold.customer_360 ALTER COLUMN phone SET TAGS ('pii_category' = 'phone', 'sensitivity' = 'confidential');
ALTER TABLE gold.customer_360 ALTER COLUMN dob   SET TAGS ('pii_category' = 'dob',   'sensitivity' = 'confidential');

ALTER TABLE gold.fraud_alerts SET TAGS ('data_product' = 'fraud_alerts', 'sensitivity' = 'restricted');

-- ============================================================================
-- 5. Grants
--
--    NOTE: analysts / fraud_investigators / compliance_officers / data_engineers
--    exist only as WORKSPACE-local groups in this account, not account-level
--    identities -- Unity Catalog can only grant to account users, service
--    principals, or account-level groups, so `GRANT ... TO `data_engineers``
--    (etc.) fails with PRINCIPAL_DOES_NOT_EXIST. Deploying this required
--    account-admin rights on the Databricks account (this login only has
--    workspace-admin rights), so the group promotion could not be done here.
--
--    Until an account admin promotes those four groups to account level, all
--    grants below target the single account user so the pipeline, masks, and
--    row filter can be deployed and exercised end-to-end. The intended
--    role-scoped grants are kept below, commented out, ready to swap in.
-- ============================================================================
GRANT USE CATALOG ON CATALOG datagovernancemvp TO `akash.dolas@gmail.com`;
GRANT ALL PRIVILEGES ON SCHEMA bronze     TO `akash.dolas@gmail.com`;
GRANT ALL PRIVILEGES ON SCHEMA silver     TO `akash.dolas@gmail.com`;
GRANT ALL PRIVILEGES ON SCHEMA gold       TO `akash.dolas@gmail.com`;
GRANT ALL PRIVILEGES ON SCHEMA governance TO `akash.dolas@gmail.com`;

-- -- Intended role-scoped grants (activate once the groups below are account-level):
-- GRANT USE CATALOG ON CATALOG datagovernancemvp TO `data_engineers`;
-- GRANT USE CATALOG ON CATALOG datagovernancemvp TO `analysts`;
-- GRANT USE CATALOG ON CATALOG datagovernancemvp TO `fraud_investigators`;
-- GRANT USE CATALOG ON CATALOG datagovernancemvp TO `compliance_officers`;
--
-- -- data_engineers: full build/ops access across all layers
-- GRANT ALL PRIVILEGES ON SCHEMA bronze     TO `data_engineers`;
-- GRANT ALL PRIVILEGES ON SCHEMA silver     TO `data_engineers`;
-- GRANT ALL PRIVILEGES ON SCHEMA gold       TO `data_engineers`;
-- GRANT ALL PRIVILEGES ON SCHEMA governance TO `data_engineers`;
--
-- -- compliance_officers: full read across silver + gold, unmasked (per mask functions above)
-- GRANT USE SCHEMA ON SCHEMA silver TO `compliance_officers`;
-- GRANT SELECT     ON SCHEMA silver TO `compliance_officers`;
-- GRANT USE SCHEMA ON SCHEMA gold   TO `compliance_officers`;
-- GRANT SELECT     ON SCHEMA gold   TO `compliance_officers`;
-- GRANT USE SCHEMA ON SCHEMA governance TO `compliance_officers`;
--
-- -- analysts: masked, aggregate-level gold access only (no fraud_alerts, no silver PII tables)
-- GRANT USE SCHEMA ON SCHEMA gold TO `analysts`;
-- GRANT SELECT ON TABLE gold.customer_360               TO `analysts`;
-- GRANT SELECT ON TABLE gold.monthly_transaction_summary TO `analysts`;
--
-- -- fraud_investigators: masked customer_360 (row-filtered) + full fraud_alerts detail
-- GRANT USE SCHEMA ON SCHEMA gold TO `fraud_investigators`;
-- GRANT SELECT ON TABLE gold.customer_360               TO `fraud_investigators`;
-- GRANT SELECT ON TABLE gold.monthly_transaction_summary TO `fraud_investigators`;
-- GRANT SELECT ON TABLE gold.fraud_alerts                TO `fraud_investigators`;
