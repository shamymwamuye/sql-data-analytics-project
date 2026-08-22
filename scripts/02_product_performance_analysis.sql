USE DataWarehouseAnalytics
GO

/*
===============================================================================
Product Performance Analysis
===============================================================================
Purpose:
    This report consolidates product-level sales performance into a single,
    query-ready view for reporting and dashboarding.

Highlights:
    1. Aggregates product-level metrics: total revenue, total units sold,
       total distinct orders, and average selling price.
    2. Ranks every product by revenue, units sold, order count, and average
       selling price.
    3. Calculates each product's contribution to total company revenue
       (revenue_contribution_pct).
    4. Runs a Pareto (80/20) analysis to identify which products make up the
       top 80% of revenue vs. the long tail (pareto_group).
===============================================================================
*/

-- ----------------------------------------------------------------------------
-- Create Report: gold.product_report
-- ----------------------------------------------------------------------------

CREATE OR ALTER VIEW gold.product_report AS

-- ----------------------------------------------------------------------------
-- CTE 1: product_summary
-- Base product-level summary: joins gold.dim_products to gold.fact_sales and
-- aggregates total revenue, total units sold, total distinct orders, and
-- average selling price (revenue / units sold) per product.
--
-- Uses a LEFT JOIN + COALESCE(...,0) so that products with zero sales still
-- appear in the report (with 0 revenue/units) instead of being dropped.
-- ----------------------------------------------------------------------------
WITH product_summary AS
(
SELECT
	p.product_key,
	p.category,
	p.subcategory,
	p.product_name,
	COALESCE(SUM(f.sales_amount),0) AS total_product_revenue,
	COALESCE(SUM(f.quantity),0) AS total_units_sold,
	COUNT(DISTINCT f.order_number) AS total_product_orders,
	CAST(SUM(f.sales_amount) AS FLOAT) / NULLIF(CAST(SUM(f.quantity) AS FLOAT),0) AS average_selling_price
FROM gold.dim_products AS p
LEFT JOIN gold.fact_sales AS f
	ON p.product_key = f.product_key
GROUP By
	p.product_key,
	p.category,
	p.subcategory,
	p.product_name
),

-- ----------------------------------------------------------------------------
-- CTE 2: product_ranking_summary
-- Ranks every product on four independent dimensions using RANK(), so ties
-- receive the same rank (e.g. two products tied for 2nd both get rank 2, and
-- the next product gets rank 4).
-- ----------------------------------------------------------------------------
product_ranking_summary AS
(
SELECT
	product_key,
	category,
	subcategory,
	product_name,
	total_product_revenue,
	total_units_sold,
	total_product_orders,
	average_selling_price,
	RANK() OVER(ORDER BY total_product_revenue DESC) AS product_revenue_rank,
	RANK() OVER(ORDER BY total_units_sold DESC) AS units_sold_rank,
	RANK() OVER(ORDER BY total_product_orders DESC) AS orders_rank,
	RANK() OVER(ORDER BY average_selling_price DESC) AS average_selling_price_rank
FROM product_summary
),

-- ----------------------------------------------------------------------------
-- CTE 3: product_contribution_summary
-- Adds company_revenue: the sum of every product's revenue, computed as a
-- window total (SUM(...) OVER()) so it's repeated on every row. This is the
-- denominator used in the next CTE to compute each product's % contribution.
-- ----------------------------------------------------------------------------
product_contribution_summary AS
(
SELECT 
	product_key,
	category,
	subcategory,
	product_name,
	total_product_revenue,
	total_units_sold,
	total_product_orders,
	average_selling_price,
	product_revenue_rank,
	units_sold_rank,
	orders_rank,
	average_selling_price_rank,
	SUM(total_product_revenue) OVER() AS company_revenue
FROM product_ranking_summary
),

-- ----------------------------------------------------------------------------
-- CTE 4: product_contribution_percentage_summary
-- Computes revenue_contribution_pct: what share of total company revenue
-- each individual product accounts for.
-- ----------------------------------------------------------------------------
product_contribution_percentage_summary AS
(
SELECT
	product_key,
	category,
	subcategory,
	product_name,
	total_product_revenue,
	total_units_sold,
	total_product_orders,
	average_selling_price,
	product_revenue_rank,
	units_sold_rank,
	orders_rank,
	average_selling_price_rank,
	company_revenue,
    CAST(total_product_revenue  AS FLOAT)
		/ company_revenue * 100 AS revenue_contribution_pct
FROM product_contribution_summary
),

-- ----------------------------------------------------------------------------
-- CTE 5: product_pareto_summary
-- Pareto (80/20) analysis: orders products from highest to lowest revenue and
-- computes a running (cumulative) total of revenue_contribution_pct. This
-- cumulative percentage is what the final SELECT uses to flag whether a
-- product falls inside the "Top 80%" of cumulative revenue or the
-- "Remaining 20%" long tail.
-- ----------------------------------------------------------------------------
product_pareto_summary AS
(
SELECT
	product_key,
	category,
	subcategory,
	product_name,
	total_product_revenue,
	total_units_sold,
	total_product_orders,
	average_selling_price,
	product_revenue_rank,
	units_sold_rank,
	orders_rank,
	average_selling_price_rank,
	company_revenue,
    revenue_contribution_pct,
    ROUND(
		SUM(revenue_contribution_pct) OVER(
										ORDER BY total_product_revenue DESC
										ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW 
										) 
		, 2)AS cumulative_revenue_contribution_pct
FROM product_contribution_percentage_summary
)

-- ------------------------------------------------------------
-- Final SELECT
-- Adds pareto_group: labels each product 'Top 80%' if it falls within the
-- cumulative 80% of company revenue (the "vital few" that drive most sales),
-- or 'Remaining 20%' otherwise (the long tail).
-- ------------------------------------------------------------
SELECT
	product_key,
	category,
	subcategory,
	product_name,
	total_product_revenue,
	total_units_sold,
	total_product_orders,
	average_selling_price,
	product_revenue_rank,
	units_sold_rank,
	orders_rank,
	average_selling_price_rank,
	company_revenue,
    revenue_contribution_pct,
    cumulative_revenue_contribution_pct,
	CASE
		WHEN cumulative_revenue_contribution_pct < 81 THEN 'Top 80%'
		ELSE  'Remaining 20%'
	END AS pareto_group
FROM product_pareto_summary
