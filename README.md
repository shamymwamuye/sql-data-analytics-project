# SQL Data Warehouse Analytics

Three SQL reporting views — **Customer Segmentation**, **Product Performance**, and **Sales Performance** — built on top of a small star-schema data warehouse (`DataWarehouseAnalytics`) using T-SQL (SQL Server). Each report uses CTEs and window functions (`NTILE`, `RANK`, `LAG`, running `SUM`/`AVG`) to turn raw transactions into ready-to-query business metrics.

## Data model

The warehouse is a simple star schema: one fact table surrounded by two dimension tables.

```
gold.dim_customers          gold.fact_sales              gold.dim_products
-----------------           -----------------             -----------------
customer_key (PK)  ───────< customer_key (FK)              product_key (PK)
customer_id                 product_key (FK)   >─────────  product_id
customer_number              order_number                  product_number
first_name / last_name       order_date                     product_name
country                      shipping_date / due_date       category_id
marital_status                sales_amount                 category
gender                        quantity                      subcategory
birth_date                    price                         maintenance
create_date                                                 cost
                                                              product_line
                                                              start_date
```

- **gold.fact_sales** — one row per order line item (order_number + product_key), ~60K rows.
- **gold.dim_customers** — ~18.4K customers.
- **gold.dim_products** — 295 products.

## Business questions answered

**`gold.customers_report`** (Customer Segmentation)
- Who are our highest-value / most loyal customers, and who is at risk of churning?
- What's each customer's recency, frequency, and monetary (RFM) profile?
- How do customers break down by age group, lifetime value tier, and tenure?

**`gold.product_report`** (Product Performance)
- Which products generate the most revenue, units sold, and orders?
- What share of total company revenue does each product contribute?
- Which products make up the "vital few" driving 80% of revenue (Pareto analysis)?

**`gold.sales_report`** (Sales Performance)
- How much revenue/orders did we generate each month, and what's the average order value?
- Is revenue trending up or down month-over-month, and by how much?
- Which months were the best and worst performers, and what does the smoothed 3-month trend look like?

## Repository structure

```
sql-data-warehouse-analytics/
├── README.md
├── datasets/
│   ├── dim_customers.csv
│   ├── dim_products.csv
│   └── fact_sales.csv
├── scripts/
│   ├── 00_init_database.sql                    -- creates DB, schema, tables; loads CSVs
│   ├── 01_customer_segmentation_analysis.sql    -- creates gold.customers_report
│   ├── 02_product_performance_analysis.sql      -- creates gold.product_report
│   └── 03_sales_performance_analysis.sql        -- creates gold.sales_report
├── results/
│   ├── customer_report_results.csv              -- sample output of gold.customers_report
│   ├── product_report_results.csv                -- sample output of gold.product_report
│   └── sales_report_results.csv                   -- sample output of gold.sales_report
└── docs/
    └── data_dictionary.md                        -- (optional) column-level definitions
```

## How to run

1. Open the scripts in SQL Server Management Studio (SSMS) or Azure Data Studio, connected to a SQL Server instance.
2. In `scripts/00_init_database.sql`, update the three `BULK INSERT ... FROM 'C:\...'` file paths so they point to your local copy of the `/datasets` folder, then run the script. This creates the `DataWarehouseAnalytics` database, the `gold` schema, the three tables, and loads them from the CSVs.
3. Run `01_customer_segmentation_analysis.sql`, `02_product_performance_analysis.sql`, and `03_sales_performance_analysis.sql` (in any order) to create the three reporting views.
4. Query the views directly, e.g.:
   ```sql
   SELECT * FROM gold.customers_report WHERE customer_RFM_segment = 'Champions';
   SELECT TOP 10 * FROM gold.product_report ORDER BY product_revenue_rank;
   SELECT * FROM gold.sales_report ORDER BY order_year, month_number;
   ```

## Sample insights

- **~18,482** customers with purchase history are segmented into 11 RFM groups — the largest are *Potential Loyalists* (3,242) and *Loyal Customers* (2,510), with 786 customers flagged *Can't Lose Them* (big past spenders who've gone quiet).
- The top-selling product, the **Mountain-200 Black-46**, accounts for roughly **4.7%** of total company revenue on its own.
- Monthly revenue peaked at **$1.87M in December 2013**, the highest-grossing month in the dataset.

## Tools & techniques

- T-SQL / SQL Server (`CREATE OR ALTER VIEW`, `BULK INSERT`)
- CTEs for readable, step-by-step transformation pipelines
- Window functions: `NTILE`, `RANK`, `LAG`, running `SUM`/`AVG` with `ROWS BETWEEN`
- RFM (Recency, Frequency, Monetary) customer segmentation
- Pareto (80/20) analysis

## Known limitations

- The analysis "as-of" date is hardcoded to `2014-01-31` (the end of the source data) rather than `GETDATE()`, since this is a static historical dataset.
- `BULK INSERT` file paths in `00_init_database.sql` are local Windows paths and must be edited before running.
