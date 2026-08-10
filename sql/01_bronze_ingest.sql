-- 01_bronze_ingest.sql
-- Synthetic banking data generated in pure SQL (no external source needed for the MVP).
-- Idempotent: each run fully replaces the bronze tables.
USE CATALOG datagovernancemvp;

-- ~2,000 customers
CREATE OR REPLACE TABLE bronze.customers_raw
COMMENT 'Raw customer records as landed from the source system (synthetic for MVP demo)'
AS
WITH seq AS (
  SELECT explode(sequence(1, 2000)) AS customer_id
),
named AS (
  SELECT
    customer_id,
    element_at(
      array('James','Mary','Robert','Patricia','John','Jennifer','Michael','Linda','William','Elizabeth',
            'David','Barbara','Richard','Susan','Joseph','Jessica','Thomas','Sarah','Charles','Karen',
            'Amit','Priya','Wei','Fatima','Carlos','Sofia','Yuki','Ahmed','Elena','Noah'),
      cast(pmod(customer_id * 7 + 3, 30) + 1 AS INT)
    ) AS first_name,
    element_at(
      array('Smith','Johnson','Williams','Brown','Jones','Garcia','Miller','Davis','Rodriguez','Martinez',
            'Hernandez','Lopez','Gonzalez','Wilson','Anderson','Thomas','Taylor','Moore','Jackson','Martin',
            'Lee','Perez','Thompson','White','Harris','Sanchez','Clark','Ramirez','Lewis','Robinson'),
      cast(pmod(customer_id * 13 + 5, 30) + 1 AS INT)
    ) AS last_name
  FROM seq
)
SELECT
  customer_id,
  first_name,
  last_name,
  lower(concat(first_name, '.', last_name, customer_id, '@example.com')) AS email,
  concat('+1-', lpad(cast(200 + pmod(customer_id * 3, 700) AS STRING), 3, '0'), '-',
         lpad(cast(pmod(customer_id * 97, 900) + 100 AS STRING), 3, '0'), '-',
         lpad(cast(pmod(customer_id * 911, 9000) + 1000 AS STRING), 4, '0')) AS phone,
  lpad(cast(pmod(customer_id * 104729, 900000000) + 100000000 AS STRING), 9, '0') AS ssn,
  date_add(DATE'1950-01-01', cast(pmod(customer_id * 3571, 25550) AS INT)) AS dob,
  concat(cast(100 + pmod(customer_id * 17, 899) AS STRING), ' Main St') AS address,
  element_at(
    array('New York','Los Angeles','Chicago','Houston','Phoenix','Philadelphia','San Antonio','San Diego',
          'Dallas','Austin','Seattle','Denver','Boston','Miami','Atlanta'),
    cast(pmod(customer_id, 15) + 1 AS INT)
  ) AS city,
  element_at(
    array('NY','CA','IL','TX','AZ','PA','TX','CA','TX','TX','WA','CO','MA','FL','GA'),
    cast(pmod(customer_id, 15) + 1 AS INT)
  ) AS state,
  lpad(cast(10000 + pmod(customer_id * 271, 89999) AS STRING), 5, '0') AS zip,
  'USA' AS country,
  CASE
    WHEN pmod(customer_id, 10) < 7 THEN 'low'
    WHEN pmod(customer_id, 10) < 9 THEN 'medium'
    ELSE 'high'
  END AS risk_segment,
  timestampadd(DAY, cast(-1 * pmod(customer_id * 13, 1500) AS INT), current_timestamp()) AS created_at
FROM named;

-- ~3,500 accounts, 1-2 per customer
CREATE OR REPLACE TABLE bronze.accounts_raw
COMMENT 'Raw account records as landed from the source system (synthetic for MVP demo)'
AS
WITH seq AS (
  SELECT explode(sequence(1, 3500)) AS account_id
)
SELECT
  account_id,
  cast(pmod(account_id * 31, 2000) + 1 AS BIGINT) AS customer_id,
  element_at(array('CHECKING','SAVINGS','CREDIT_CARD','LOAN'), cast(pmod(account_id, 4) + 1 AS INT)) AS account_type,
  date_add(DATE'2015-01-01', cast(pmod(account_id * 97, 3900) AS INT)) AS open_date,
  element_at(array('ACTIVE','ACTIVE','ACTIVE','DORMANT','CLOSED'), cast(pmod(account_id, 5) + 1 AS INT)) AS status,
  element_at(array('USA','USA','USA','GBR','CAN','MEX','NGA','RUS'), cast(pmod(account_id * 7, 8) + 1 AS INT)) AS branch_country
FROM seq;

-- ~80,000 transactions over the trailing ~180 days
CREATE OR REPLACE TABLE bronze.transactions_raw
COMMENT 'Raw transaction records as landed from the source system (synthetic for MVP demo)'
AS
WITH seq AS (
  SELECT explode(sequence(1, 80000)) AS transaction_id
)
SELECT
  transaction_id,
  cast(pmod(transaction_id * 53, 3500) + 1 AS BIGINT) AS account_id,
  timestampadd(SECOND, cast(-1 * pmod(transaction_id * 761, 15552000) AS INT), current_timestamp()) AS txn_timestamp,
  round(
    CASE
      WHEN pmod(transaction_id, 500) = 0 THEN 5000 + (pmod(transaction_id * 13, 15000) / 100.0)
      ELSE 5 + (pmod(transaction_id * 37, 100000) / 100.0)
    END, 2
  ) AS amount,
  'USD' AS currency,
  element_at(
    array('Amazon','Walmart','Starbucks','Uber','Shell','Target','BestBuy','Costco','Delta','Marriott',
          'Unknown POS','ATM Withdrawal','Wire Transfer'),
    cast(pmod(transaction_id * 19, 13) + 1 AS INT)
  ) AS merchant,
  element_at(array('PURCHASE','WITHDRAWAL','TRANSFER','DEPOSIT','PAYMENT'), cast(pmod(transaction_id * 11, 5) + 1 AS INT)) AS txn_type,
  element_at(array('POS','ONLINE','ATM','MOBILE','WIRE'), cast(pmod(transaction_id * 23, 5) + 1 AS INT)) AS channel,
  element_at(
    array('USA','USA','USA','USA','GBR','CAN','NGA','RUS','CHN'),
    cast(pmod(transaction_id * 29, 9) + 1 AS INT)
  ) AS country
FROM seq;
