# NYC Taxi Data Warehouse — Azure Synapse Analytics

An end-to-end data warehouse built on Azure Synapse Analytics using the **Medallion Architecture** (Bronze → Silver → Gold), modeled as a dimensional **star schema**, and exposed via Synapse Serverless SQL for natural-language querying through a **Microsoft Copilot Studio** AI agent.

---

## Overview

| | |
|---|---|
| **Source data** | NYC Yellow Taxi Trip Data (public dataset, ~3.58M records) |
| **Platform** | Azure Synapse Analytics |
| **Storage** | Azure Data Lake Storage Gen2 (ADLS Gen2) |
| **Transformation** | Apache Spark (PySpark notebooks, Delta Lake format) |
| **Serving layer** | Synapse Serverless SQL Pool (views over Delta) |
| **Consumption** | Microsoft Copilot Studio agent (SQL connector) |
| **Modeling approach** | Kimball-style dimensional modeling (star schema) |

---

## Architecture

```
                    ┌─────────────────────┐
  NYC TLC Source ──▶│  Copy Activity       │
  (public parquet)  │  (Synapse Pipeline)  │
                    └──────────┬───────────┘
                               ▼
                    ┌─────────────────────┐
                    │   BRONZE LAYER      │   raw, as-landed
                    │   (ADLS Gen2)       │   no transformation
                    └──────────┬──────────┘
                               ▼
                    ┌─────────────────────┐
                    │  Spark Notebook     │   cleansing, dedup,
                    │  (PySpark)          │   null handling,
                    └──────────┬──────────┘   outlier removal
                               ▼
                    ┌─────────────────────┐
                    │   SILVER LAYER      │   cleansed, conformed,
                    │   (Delta format)    │   typed
                    └──────────┬──────────┘
                               ▼
                    ┌─────────────────────┐
                    │  Spark Notebook     │   star schema build:
                    │  (PySpark)          │   1 fact + 6 dims
                    └──────────┬──────────┘
                               ▼
                    ┌─────────────────────┐
                    │   GOLD LAYER        │   fact_trips +
                    │   (Delta format)    │   dimension tables
                    └──────────┬──────────┘
                               ▼
                    ┌─────────────────────┐
                    │  Serverless SQL     │   external data source
                    │  Pool (Built-in)    │   + views (OPENROWSET)
                    └──────────┬──────────┘
                               ▼
                    ┌─────────────────────┐
                    │  Copilot Studio     │   SQL Server connector,
                    │  AI Agent           │   read-only login
                    └─────────────────────┘
```

---

## Dataset

**NYC Yellow Taxi Trip Data**, sourced from the [NYC TLC public dataset](https://www.nyc.gov/site/tlc/about/tlc-trip-record-data.page).

- ~3.58M trip records
- Format: Parquet
- Fields: pickup/dropoff timestamps, location IDs, fare breakdown, payment type, vendor, rate code, passenger count, trip distance

---

## Medallion Architecture

### 🥉 Bronze Layer
Raw parquet file landed as-is via **Copy Activity** (HTTP source ( converted ZSTD compressed parquet to snappy parquet to parse it properly → ADLS Gen2 sink). No schema enforcement, no transformation , exact copy of source.

### 🥈 Silver Layer
Cleansed and conformed using PySpark. Rules applied based on actual data profiling (not assumptions):

| Issue | Rows affected | Action |
|---|---|---|
| Nulls in `passenger_count`, `RatecodeID`, `store_and_fwd_flag`, `congestion_surcharge`, `Airport_fee` | 426,190 (~11.9%) | Imputed with sensible defaults |
| Invalid pickup dates (e.g. year 2002) | Outliers | Filtered to valid trip month |
| Dropoff before pickup | 117 | Dropped — physically invalid |
| Fare ≤ 0 or distance ≤ 0 | 142,563 (~4%) | Dropped — invalid transactions |
| Duplicate rows | 0 | No action needed |
| `passenger_count = 0` | Legitimate value | **Kept** — distinct from null, valid per TLC data dictionary |

Output written as **Delta format** to `silver/taxi_trips/`, with an added `trip_duration_minutes` derived column.

### 🥇 Gold Layer — Star Schema

**Grain:** one row in `fact_trips` = one completed taxi trip.

```
                        dim_date  (role-played: pickup / dropoff)
                            │
    dim_vendor ────┐        │        ┌──── dim_location (role-played: PU / DO)
                    │        │        │
                    └──── fact_trips ─┘
                    │        │        │
    dim_ratecode ───┘        │        └──── dim_payment_type
                            │
                        dim_time  (role-played: pickup / dropoff)
```

| Table | Type | Description |
|---|---|---|
| `fact_trips` | Fact | Trip-grain measures: fare, tips, tolls, surcharges, distance, duration + FKs |
| `dim_date` | Dimension | Calendar attributes (year, month, day, weekend flag) — role-played for pickup/dropoff |
| `dim_time` | Dimension | Minute-of-day granularity (1,440 rows) — role-played for pickup/dropoff |
| `dim_location` | Dimension | Pickup/dropoff location IDs — role-played |
| `dim_vendor` | Dimension | Taxi technology provider lookup |
| `dim_ratecode` | Dimension | Fare rule lookup (standard, JFK, Newark, negotiated, etc.) |
| `dim_payment_type` | Dimension | Payment method lookup (credit card, cash, disputed, etc.) |

All facts are **additive** (safe to `SUM` across any dimension) except derived ratios (e.g. fare-per-mile), which must be computed post-aggregation.

---

## Serving Layer — Serverless SQL Pool

Gold Delta tables are exposed as SQL views using `OPENROWSET` with `FORMAT = 'DELTA'`, queried live (no data duplication/caching):

```sql
CREATE DATABASE gold_taxi_dw;

CREATE MASTER KEY ENCRYPTION BY PASSWORD = '<strong-password>';

CREATE DATABASE SCOPED CREDENTIAL synapse_managed_identity
WITH IDENTITY = 'Managed Identity';

CREATE EXTERNAL DATA SOURCE gold_lake
WITH (
    LOCATION = 'abfss://gold@<storage-account>.dfs.core.windows.net/',
    CREDENTIAL = synapse_managed_identity
);

CREATE VIEW dbo.fact_trips AS
SELECT * FROM OPENROWSET(
    BULK 'fact_trips/', DATA_SOURCE = 'gold_lake', FORMAT = 'DELTA'
) AS result;
-- + 6 more views for each dimension
```


---

## AI Agent Integration — Microsoft Copilot Studio

The agent connects to the Synapse Serverless SQL endpoint via the **SQL Server connector**, authenticating with the read-only login, and is scoped to query only the `gold` schema (facts + dimensions).

```
Endpoint : <workspace-name>-ondemand.sql.azuresynapse.net
Database : gold_taxi_dw
Auth     : SQL Login (copilot_reader, read-only)
```

The agent is given the Gold schema (table/column names, grain, and relationships) so it can translate natural-language questions into correct T-SQL joins across `fact_trips` and its dimensions — e.g.:

> "What was total revenue by payment type last March?"
> → `SELECT pt.payment_desc, SUM(f.total_amount) ... GROUP BY pt.payment_desc`

---


---

## Tech Stack

- **Azure Synapse Analytics** — workspace, Spark pool, Serverless SQL pool, Pipelines
- **Azure Data Lake Storage Gen2** — medallion-layer storage
- **Delta Lake** — ACID table format for Silver/Gold
- **PySpark** — transformation logic
- **T-SQL** — Gold layer exposure via views
- **Microsoft Copilot Studio** — natural-language AI agent, SQL connector

---

## Key Design Decisions

- **Serverless over Dedicated SQL Pool** — pay-per-query, no idle compute cost, sufficient for this data volume.
- **Role-playing dimensions** for `dim_date`, `dim_time`, and `dim_location` — avoids duplicating tables for pickup vs. dropoff context.
- **Delta format for Silver/Gold** — enables ACID writes, schema enforcement, and native `OPENROWSET` reads from serverless SQL without a separate load step.
- **Data-driven cleansing rules** — every Silver-layer decision (impute vs. drop, thresholds) based on actual profiling output, not generic assumptions.

---

## Future Work

- Add TLC zone lookup to enrich `dim_location` with borough/zone names for more readable agent responses
- Incremental/CDC loading for new monthly files instead of full reload
- Migrate Gold layer to Snowflake (native Copilot Studio knowledge-source support) as an alternative serving engine
- Row-level security on Gold views for multi-tenant agent access
