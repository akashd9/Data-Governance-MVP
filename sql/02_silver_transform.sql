-- 02_silver_transform.sql
-- Cleans, dedupes, types and constrains bronze data into the silver layer.
USE CATALOG datagovernancemvp;

-- customers -----------------------------------------------------------------
CREATE OR REPLACE TABLE silver.customers (
  customer_id   BIGINT    NOT NULL,
  first_name    STRING    NOT NULL,
  last_name     STRING    NOT NULL,
  email         STRING    NOT NULL,
  phone         STRING,
  ssn           STRING    NOT NULL,
  dob           DATE      NOT NULL,
  address       STRING,
  city          STRING,
  state         STRING,
  zip           STRING,
  country       STRING,
  risk_segment  STRING,
  created_at    TIMESTAMP,
  _ingested_at  TIMESTAMP,
  CONSTRAINT pk_customers PRIMARY KEY (customer_id)
)
COMMENT 'Conformed customer master data. Contains PII governed via masking (see governance schema).';

INSERT OVERWRITE silver.customers
SELECT
  customer_id, trim(first_name), trim(last_name), lower(trim(email)), phone, ssn, dob,
  address, city, state, zip, country, risk_segment, created_at, current_timestamp()
FROM (
  SELECT *, row_number() OVER (PARTITION BY customer_id ORDER BY created_at DESC) AS rn
  FROM bronze.customers_raw
  WHERE customer_id IS NOT NULL
) d
WHERE rn = 1;

ALTER TABLE silver.customers ADD CONSTRAINT chk_customers_dob CHECK (dob < current_date());

-- accounts --------------------------------------------------------------------
CREATE OR REPLACE TABLE silver.accounts (
  account_id      BIGINT    NOT NULL,
  customer_id     BIGINT    NOT NULL,
  account_type    STRING    NOT NULL,
  open_date       DATE      NOT NULL,
  status          STRING    NOT NULL,
  branch_country  STRING,
  _ingested_at    TIMESTAMP,
  CONSTRAINT pk_accounts PRIMARY KEY (account_id),
  CONSTRAINT fk_accounts_customer FOREIGN KEY (customer_id) REFERENCES silver.customers (customer_id)
)
COMMENT 'Conformed account master data.';

INSERT OVERWRITE silver.accounts
SELECT account_id, customer_id, account_type, open_date, status, branch_country, current_timestamp()
FROM (
  SELECT *, row_number() OVER (PARTITION BY account_id ORDER BY open_date DESC) AS rn
  FROM bronze.accounts_raw
  WHERE account_id IS NOT NULL
) d
WHERE rn = 1;

ALTER TABLE silver.accounts ADD CONSTRAINT chk_accounts_status CHECK (status IN ('ACTIVE','DORMANT','CLOSED'));

-- transactions ------------------------------------------------------------------
CREATE OR REPLACE TABLE silver.transactions (
  transaction_id  BIGINT          NOT NULL,
  account_id      BIGINT          NOT NULL,
  txn_timestamp   TIMESTAMP       NOT NULL,
  amount          DECIMAL(12,2)   NOT NULL,
  currency        STRING          NOT NULL,
  merchant        STRING,
  txn_type        STRING,
  channel         STRING,
  country         STRING,
  is_foreign      BOOLEAN,
  is_high_value   BOOLEAN,
  is_flagged      BOOLEAN,
  flagged_reason  STRING,
  _ingested_at    TIMESTAMP,
  CONSTRAINT pk_transactions PRIMARY KEY (transaction_id),
  CONSTRAINT fk_transactions_account FOREIGN KEY (account_id) REFERENCES silver.accounts (account_id)
)
COMMENT 'Conformed transaction fact table with rule-based fraud flags.';

INSERT OVERWRITE silver.transactions
SELECT
  transaction_id, account_id, txn_timestamp, amount, currency, merchant, txn_type, channel, country,
  country <> 'USA' AS is_foreign,
  amount > 3000 AS is_high_value,
  (amount > 3000 OR (country <> 'USA' AND amount > 1000)) AS is_flagged,
  CASE
    WHEN amount > 3000 AND country <> 'USA' THEN 'High value + foreign country'
    WHEN amount > 3000 THEN 'High value transaction'
    WHEN country <> 'USA' AND amount > 1000 THEN 'Elevated foreign transaction'
    ELSE NULL
  END AS flagged_reason,
  current_timestamp()
FROM bronze.transactions_raw
WHERE transaction_id IS NOT NULL;

ALTER TABLE silver.transactions ADD CONSTRAINT chk_transactions_amount CHECK (amount > 0);
