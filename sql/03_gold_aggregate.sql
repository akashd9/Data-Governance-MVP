-- 03_gold_aggregate.sql
-- Business-level curated tables for consumption. PII columns are masked and
-- row-level security is applied in 04_governance_apply.sql.
USE CATALOG datagovernancemvp;

-- customer_360: one row per customer with account/transaction rollups.
-- Carries PII (ssn/email/phone) so it can demonstrate column masking downstream.
CREATE OR REPLACE TABLE gold.customer_360
COMMENT 'Customer 360 view: profile + account + transaction rollups. PII masked per role.'
AS
SELECT
  c.customer_id,
  c.first_name,
  c.last_name,
  c.email,
  c.phone,
  c.ssn,
  c.dob,
  c.city,
  c.state,
  c.country,
  c.risk_segment,
  count(DISTINCT a.account_id) AS account_count,
  count(DISTINCT CASE WHEN a.status = 'ACTIVE' THEN a.account_id END) AS active_account_count,
  count(t.transaction_id) AS total_txn_count,
  round(sum(t.amount), 2) AS total_txn_amount,
  count(CASE WHEN t.is_flagged THEN 1 END) AS flagged_txn_count,
  max(t.txn_timestamp) AS last_txn_at
FROM silver.customers c
LEFT JOIN silver.accounts a ON a.customer_id = c.customer_id
LEFT JOIN silver.transactions t ON t.account_id = a.account_id
GROUP BY c.customer_id, c.first_name, c.last_name, c.email, c.phone, c.ssn, c.dob,
         c.city, c.state, c.country, c.risk_segment;

-- monthly_transaction_summary: aggregated spend by account/month, no PII.
CREATE OR REPLACE TABLE gold.monthly_transaction_summary
COMMENT 'Monthly transaction volume and value per account, aggregated (no PII).'
AS
SELECT
  a.account_id,
  a.account_type,
  date_trunc('MONTH', t.txn_timestamp) AS txn_month,
  count(*) AS txn_count,
  round(sum(t.amount), 2) AS total_amount,
  round(avg(t.amount), 2) AS avg_amount,
  count(CASE WHEN t.is_flagged THEN 1 END) AS flagged_txn_count
FROM silver.transactions t
JOIN silver.accounts a ON a.account_id = t.account_id
GROUP BY a.account_id, a.account_type, date_trunc('MONTH', t.txn_timestamp);

-- fraud_alerts: individual flagged transactions joined with customer context.
-- Restricted via grants to fraud_investigators / compliance_officers / data_engineers.
CREATE OR REPLACE TABLE gold.fraud_alerts
COMMENT 'Flagged transactions with customer context. Access restricted to fraud/compliance roles.'
AS
SELECT
  t.transaction_id,
  t.account_id,
  a.customer_id,
  c.first_name,
  c.last_name,
  c.risk_segment,
  t.txn_timestamp,
  t.amount,
  t.currency,
  t.merchant,
  t.channel,
  t.country,
  t.flagged_reason
FROM silver.transactions t
JOIN silver.accounts a ON a.account_id = t.account_id
JOIN silver.customers c ON c.customer_id = a.customer_id
WHERE t.is_flagged = true;
