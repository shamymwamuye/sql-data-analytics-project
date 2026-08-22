USE DataWarehouseAnalytics
GO

/*
===============================================================================
SALES PERFORMANCE ANALYSIS
===============================================================================
The sales performance dashboard simply answers these questions:

How much revenue did we generate each month?
How many orders did we receive each month?
What was the average order value for each month?
Compared to last month, did revenue increase or decrease?
By what percentage did revenue change from the previous month?
Which month generated the highest revenue?
Which month generated the lowest revenue?
===============================================================================
*/

-- ----------------------------------------------------------------------------
-- Create Report: gold.sales_report
-- ----------------------------------------------------------------------------

CREATE OR ALTER VIEW gold.sales_report AS

-- ----------------------------------------------------------------------------
-- CTE 1: monthly_summary
-- Rolls fact_sales up to one row per calendar month: total revenue, total
-- distinct orders, and average order value. Rows with no order_date are
-- excluded since they can't be assigned to a month.
-- ----------------------------------------------------------------------------
WITH monthly_summary AS
(
SELECT
	YEAR(order_date) AS order_year,
    MONTH(order_date) AS month_number,
    FORMAT(order_date, 'yyyy-MMM') AS order_year_month,
    SUM(sales_amount) AS total_month_revenue,
    COUNT(DISTINCT order_number) AS total_month_orders,
    CAST(SUM(sales_amount) AS FLOAT) / COUNT(DISTINCT order_number) AS average_order_value
FROM gold.fact_sales
WHERE order_date IS NOT NULL
GROUP BY
	YEAR(order_date),
    MONTH(order_date),
    FORMAT(order_date, 'yyyy-MMM')
),

-- ----------------------------------------------------------------------------
-- CTE 2: monthly_previous_summary
-- Uses LAG() to pull each month's revenue alongside the previous calendar
-- month's revenue (previous_month_revenue), ordered chronologically by year
-- then month. This sets up the month-over-month comparison in the next CTE.
-- ----------------------------------------------------------------------------
monthly_previous_summary AS
(
SELECT
	order_year,
    month_number,
    order_year_month,
    total_month_revenue,
    total_month_orders,
    average_order_value,
    LAG(total_month_revenue) OVER(
							ORDER BY 
									order_year,
									month_number
							) AS previous_month_revenue
FROM monthly_summary
),

-- ----------------------------------------------------------------------------
-- CTE 3: monthly_growth_summary
-- Computes month-over-month change: the absolute revenue_difference and the
-- revenue_growth_pct relative to the previous month. NULLIF guards against a
-- divide-by-zero when the previous month had no revenue (or doesn't exist,
-- as with the very first month in the dataset).
-- ----------------------------------------------------------------------------
monthly_growth_summary AS
(
SELECT 
	order_year,
    month_number,
    order_year_month,
    total_month_revenue,
    total_month_orders,
    average_order_value,
    previous_month_revenue,
	total_month_revenue - previous_month_revenue AS revenue_difference,
	ROUND(
			CAST((total_month_revenue - previous_month_revenue) AS FLOAT) 
            / NULLIF(CAST(previous_month_revenue AS FLOAT),0) 
            * 100
		, 2) AS revenue_growth_pct
FROM monthly_previous_summary
),

-- ----------------------------------------------------------------------------
-- CTE 4: monthly_trend_summary
-- Smooths out month-to-month noise with a rolling 3-month average revenue
-- (the current month plus the two before it), useful for spotting the
-- underlying trend rather than single-month spikes/dips.
-- ----------------------------------------------------------------------------
monthly_trend_summary AS
(
SELECT 
	order_year,
    month_number,
    order_year_month,
    total_month_revenue,
    total_month_orders,
    average_order_value,
    previous_month_revenue,
	revenue_difference,
	revenue_growth_pct,
    ROUND(
			AVG(total_month_revenue)
			OVER(
				ORDER BY
					order_year,
					month_number
				ROWS BETWEEN 2 PRECEDING AND CURRENT ROW
				) 
        , 2) AS rolling_3_month_revenue
FROM monthly_growth_summary
),

-- ----------------------------------------------------------------------------
-- CTE 5: monthly_rank_summary
-- Ranks every month by average order value, total orders, and total revenue,
-- so the best/worst performing months (by any of those measures) can be
-- picked out at a glance.
-- ----------------------------------------------------------------------------
monthly_rank_summary AS
(
SELECT
	order_year,
    month_number,
    order_year_month,
    total_month_revenue,
    total_month_orders,
    average_order_value,
    previous_month_revenue,
	revenue_difference,
	revenue_growth_pct,
    rolling_3_month_revenue,
    RANK() OVER(ORDER BY average_order_value DESC) AS average_order_value_rank,
    RANK() OVER(ORDER BY total_month_orders DESC) AS total_orders_rank,
    RANK() OVER(ORDER BY total_month_revenue DESC) AS revenue_rank
FROM monthly_trend_summary
)

-- ------------------------------------------------------------
-- Final SELECT
-- Returns one row per calendar month with revenue, orders, average order
-- value, month-over-month growth, the rolling 3-month trend, and each
-- month's rank across revenue, order count, and average order value.
-- ------------------------------------------------------------
SELECT 
    order_year,
    month_number,
    order_year_month,
    total_month_revenue,
	previous_month_revenue,
	revenue_difference,
	revenue_growth_pct,
    total_month_orders,
    average_order_value,
    rolling_3_month_revenue,
    average_order_value_rank,
    total_orders_rank,
    revenue_rank
FROM monthly_rank_summary
