# Data Governance MVP (Databricks / Unity Catalog)

An end-to-end medallion pipeline built on the `datagovernancemvp` Unity Catalog catalog, demonstrating
a banking/fraud use case with Unity Catalog governance layered on top: PII tags, column masking,
row-level security, and role-scoped grants.

## Architecture

```
bronze (raw, synthetic)      silver (conformed, constrained)     gold (curated)
─────────────────────        ──────────────────────────          ──────────────────────
customers_raw          ──▶   customers (PK, CHECK dob)     ──▶   customer_360 (masked PII,
accounts_raw            ──▶   accounts (PK/FK, CHECK status) ──▶   row-filtered for fraud team)
transactions_raw        ──▶   transactions (PK/FK,           ──▶   monthly_transaction_summary
                               CHECK amount>0, fraud flags)  ──▶   fraud_alerts (fraud/compliance only)

governance schema: mask_ssn / mask_email / mask_phone, customer_360_row_filter, dq_results
```

Data is synthetically generated in pure SQL (`01_bronze_ingest.sql`) so the project runs standalone
with no external source system: ~2,000 customers, ~3,500 accounts, ~80,000 transactions.

## Pipeline (`/sql`)

Run in order (also wired as a Databricks Job, see `/job`):

| # | Notebook | Purpose |
|---|----------|---------|
| 00 | `00_setup_catalog_schemas.sql` | Creates `bronze`, `silver`, `gold`, `governance` schemas + catalog tags |
| 01 | `01_bronze_ingest.sql` | Generates synthetic customers/accounts/transactions into bronze |
| 02 | `02_silver_transform.sql` | Dedupes, types, and constrains data into silver (PK/FK/CHECK constraints, rule-based fraud flags) |
| 03 | `03_gold_aggregate.sql` | Builds `customer_360`, `monthly_transaction_summary`, `fraud_alerts` |
| 04 | `04_governance_apply.sql` | Applies column masks, row filter, PII tags, and role-scoped grants |
| 05 | `05_data_quality_checks.sql` | Referential/quality checks persisted to `governance.dq_results` |
| 06 | `06_audit_lineage_demo.sql` | Reads `system.access.audit`, `system.access.table_lineage`, `information_schema` for observability |

## Governance model

The design is role-scoped around four groups: `data_engineers`, `compliance_officers`,
`analysts`, `fraud_investigators`. **Known environment gap:** these currently exist only as
workspace-local groups in this Databricks account, not account-level identities — Unity Catalog
can only grant privileges to account users, service principals, or account-level groups, so
`GRANT ... TO \`data_engineers\`` fails with `PRINCIPAL_DOES_NOT_EXIST`. Promoting them requires
account-admin rights on the Databricks account (this deployment only had workspace-admin rights).
Until that's done, `04_governance_apply.sql` grants everything to the single account user
(`akash.dolas@gmail.com`) so the pipeline, masks, and row filter still deploy and run end-to-end;
the intended role-scoped grants are included commented-out, ready to swap in once an account admin
promotes the groups.

| Role | Silver | `gold.customer_360` | `gold.fraud_alerts` | PII visibility |
|---|---|---|---|---|
| `data_engineers` | Full (owner) | Full | Full | Unmasked |
| `compliance_officers` | Read | Full | Full | Unmasked |
| `analysts` | — | Read (masked, all rows) | — | Masked |
| `fraud_investigators` | — | Read (masked, **flagged customers only**) | Full | Masked |

- **Column masking**: `governance.mask_ssn/mask_email/mask_phone` reveal real values only to
  `compliance_officers`, `data_engineers`, `admins`; everyone else sees a masked value.
  Masks are applied on `gold.customer_360` only — Unity Catalog does not support column masks on
  tables carrying `CHECK` constraints, which `silver.customers` has (`chk_customers_dob`). Since
  silver access is limited to roles already unmasked by the function logic, this has no governance gap.
- **Row-level security**: `governance.customer_360_row_filter` restricts `fraud_investigators` to
  customers with at least one flagged transaction; every other granted role sees all rows.
- **Tags**: PII columns (`ssn`, `email`, `phone`, `dob`) are tagged `pii_category`/`sensitivity`
  at the column level; schemas and the catalog carry classification tags too.
- **Data quality**: PK/FK/CHECK constraints on silver tables, plus a standalone check suite
  (`governance.dq_results`) validating row counts, orphan keys, and non-positive amounts.

## Deploying

```powershell
databricks workspace import-dir sql /Workspace/Users/<you>/datagovernancemvp --profile <profile>
databricks jobs create --json @job/job_definition.json --profile <profile>
databricks jobs run-now <job_id> --profile <profile>
```

`job/job_definition.json` is the deployed job spec (7 sequential tasks, serverless notebook
compute, no cluster to manage). Update the `notebook_path` values if deploying under a different
workspace user.

## Catalog

- Metastore-registered catalog: `datagovernancemvp`
- Warehouse used for ad-hoc queries: the workspace's serverless SQL warehouse
