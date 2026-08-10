-- 05_data_quality_checks.sql
-- Basic referential/quality checks over the silver layer, persisted for review.
USE CATALOG datagovernancemvp;

CREATE OR REPLACE TABLE governance.dq_results
COMMENT 'Latest data quality check results for the silver layer.'
AS
SELECT 'customers_row_count' AS check_name, count(*) AS metric_value,
       CASE WHEN count(*) > 0 THEN 'PASS' ELSE 'FAIL' END AS status, current_timestamp() AS checked_at
FROM silver.customers

UNION ALL
SELECT 'customers_duplicate_ids', count(*) - count(DISTINCT customer_id),
       CASE WHEN count(*) = count(DISTINCT customer_id) THEN 'PASS' ELSE 'FAIL' END, current_timestamp()
FROM silver.customers

UNION ALL
SELECT 'accounts_row_count', count(*),
       CASE WHEN count(*) > 0 THEN 'PASS' ELSE 'FAIL' END, current_timestamp()
FROM silver.accounts

UNION ALL
SELECT 'orphan_accounts_missing_customer', count(*),
       CASE WHEN count(*) = 0 THEN 'PASS' ELSE 'FAIL' END, current_timestamp()
FROM silver.accounts a
LEFT ANTI JOIN silver.customers c ON a.customer_id = c.customer_id

UNION ALL
SELECT 'transactions_row_count', count(*),
       CASE WHEN count(*) > 0 THEN 'PASS' ELSE 'FAIL' END, current_timestamp()
FROM silver.transactions

UNION ALL
SELECT 'orphan_transactions_missing_account', count(*),
       CASE WHEN count(*) = 0 THEN 'PASS' ELSE 'FAIL' END, current_timestamp()
FROM silver.transactions t
LEFT ANTI JOIN silver.accounts a ON t.account_id = a.account_id

UNION ALL
SELECT 'non_positive_amount_transactions', count(*),
       CASE WHEN count(*) = 0 THEN 'PASS' ELSE 'FAIL' END, current_timestamp()
FROM silver.transactions
WHERE amount <= 0

UNION ALL
SELECT 'null_email_customers', count(*),
       CASE WHEN count(*) = 0 THEN 'PASS' ELSE 'FAIL' END, current_timestamp()
FROM silver.customers
WHERE email IS NULL

UNION ALL
SELECT 'flagged_transaction_pct', round(100.0 * sum(CASE WHEN is_flagged THEN 1 ELSE 0 END) / count(*), 2),
       'INFO', current_timestamp()
FROM silver.transactions;

SELECT * FROM governance.dq_results ORDER BY status DESC, check_name;
