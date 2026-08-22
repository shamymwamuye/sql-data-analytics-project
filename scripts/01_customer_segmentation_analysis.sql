USE DataWarehouseAnalytics
GO

/*
===============================================================================
Customer Report Analysis
===============================================================================
Purpose:
    This report consolidates key customer metrics and behaviors into a single,
    query-ready view for reporting and dashboarding.

Highlights:
    1. Gathers all essential fields about a customer such as names, country,
       gender, ages, and transaction details.
    2. Segments customers into RFM-based categories (Champions, Loyal Customers,
       At Risk, Lost, etc.) and into age groups.
    3. Aggregates customer-level metrics:
       - total orders
       - total sales (customer lifetime value)
       - total quantity purchased
       - lifespan (in months)
    4. Calculates valuable KPIs:
       - recency  (number of days since the customer's last purchase)
       - frequency (how often they buy — total number of distinct orders)
       - monetary  (how much they have spent — customer lifetime value)
       - average order value

Note on the analysis "as-of" date:
    The fact_sales data ends in early 2014, so every date-based calculation
    below (age, recency) is anchored to '2014-01-31' instead of GETDATE().
    This keeps the metrics meaningful for this historical dataset. If this
    view is ever pointed at live, ongoing data, replace the hardcoded
    '2014-01-31' with GETDATE() (or a parameter) in all three places it
    appears below.
===============================================================================
*/

-- ----------------------------------------------------------------------------
-- Create Report: gold.customers_report
-- ----------------------------------------------------------------------------

CREATE OR ALTER VIEW gold.customers_report AS

-- ----------------------------------------------------------------------------
-- CTE 1: customer_report_summary
-- Builds the base customer-level summary by joining gold.dim_customers with
-- gold.fact_sales. Aggregates lifetime value, total quantities, order count,
-- average order value, and the date of each customer's first and most recent
-- order.

-- Note: the join below is written as a LEFT JOIN, but the WHERE clause filters
-- out any row where order_date IS NULL. In practice this means only customers
-- with at least one completed order end up in the report — customers with zero
-- orders are excluded, the same as an INNER JOIN would behave. This is
-- intentional here (a customer report with no purchase history isn't very
-- useful), but worth knowing if you reuse this pattern elsewhere.
-- ----------------------------------------------------------------------------

WITH customer_report_summary AS
(
SELECT
	cu.customer_key,
	CONCAT(COALESCE(cu.first_name, ''), ' ', COALESCE(cu.last_name,'')) AS customer_name,
	cu.country,
	cu.marital_status,
	cu.gender,
	DATEDIFF(YEAR, birth_date, CAST('2014-01-31' AS DATE)) AS age,
	SUM(fs.sales_amount) AS customer_lifetime_value,
	SUM(fs.quantity) AS total_quantities,
	COUNT(DISTINCT fs.order_number) AS total_orders,
	MIN(order_date) AS first_purchase_date,
	MAX(order_date) AS last_purchase_date,
	SUM(fs.sales_amount) / COUNT(DISTINCT fs.order_number) AS average_order_value
FROM gold.dim_customers AS cu
LEFT JOIN gold.fact_sales AS fs
	ON cu.customer_key = fs.customer_key
WHERE order_date IS NOT NULL
GROUP BY
	cu.customer_key,
	cu.first_name, 
	cu.last_name, 
	cu.country,
	cu.marital_status,
	cu.gender,
	birth_date
),

-- ----------------------------------------------------------------------------
-- CTE 2: customer360_report_summary
-- Extends the base summary with:
--   - lifespan: total number of months between a customer's first and last
--     purchase (i.e. how long they have been an active buyer).
--   - recency: number of days between the analysis "as-of" date (2014-01-31)
--     and the customer's last purchase.
-- ----------------------------------------------------------------------------

customer360_report_summary AS
(
SELECT
	customer_key,
	customer_name, 
	country,
	marital_status,
	gender,
	age,
	customer_lifetime_value,
	total_quantities,
	total_orders,
	first_purchase_date,
	last_purchase_date,
	average_order_value,
	DATEDIFF(MONTH, first_purchase_date, last_purchase_date) AS lifespan,
	DATEDIFF(DAY, last_purchase_date, CAST('2014-01-31' AS DATE)) AS recency
FROM customer_report_summary
),

-- ------------------------------------------------------------
-- CTE 3: RFM_scores
-- Scores every customer 1-5 on Recency, Frequency, and Monetary
-- value using NTILE(5), where 5 = best.
--   - R Score: customers with the FEWEST days since their last purchase
--     (i.e. bought most recently) get the highest score.
--   - F Score: customers with MORE total distinct orders score higher.
--   - M Score: customers with HIGHER lifetime value score higher.
-- ------------------------------------------------------------

RFM_scores AS
(
SELECT 
	customer_key,
	customer_name, 
	country,
	marital_status,
	gender,
	age,
	customer_lifetime_value,
	total_quantities,
	total_orders,
	first_purchase_date,
	last_purchase_date,
	average_order_value,
	lifespan,
	recency,
	NTILE(5) OVER(ORDER BY recency DESC) AS r_score,
	NTILE(5) OVER(ORDER BY total_orders) AS f_score,
	NTILE(5) OVER(ORDER BY customer_lifetime_value) AS m_score
FROM customer360_report_summary
),

-- ------------------------------------------------------------
-- CTE 4: RFM_code
-- Concatenates the three individual scores (R, F, M) into a
-- single 3-digit RFM Code (e.g. '555' = top score on all three)
-- used to classify each customer into a segment in the final
-- SELECT.
-- ------------------------------------------------------------

RFM_code AS
(
SELECT
	customer_key,
	customer_name, 
	country,
	marital_status,
	gender,
	age,
	customer_lifetime_value,
	total_quantities,
	total_orders,
	average_order_value,
	first_purchase_date,
	last_purchase_date,
	lifespan,
	recency,
	r_score,
	f_score,
	m_score,
	CONCAT(r_score,f_score,m_score) AS RFM_code
FROM RFM_scores
)

-- ------------------------------------------------------------
-- Final SELECT
-- Adds three human-readable classifications on top of the raw metrics:
--   1. age_group - buckets customers by age (Under 20 ... 50 and above)
--   2. lifetime_value_segment - buckets customers by lifetime spend
--   3. lifespan_customer_segment - buckets customers by how long they've been active
--   4. customer_RFM_segment  - maps each RFM Code to a named marketing segment
--      (Champions, Loyal Customers, At Risk, Lost, etc.). Only the most
--      common/meaningful RFM code combinations are labeled explicitly; every
--      other combination falls into 'Others' for further analysis.
-- ------------------------------------------------------------

SELECT
	customer_key,
	customer_name, 
	country,
	marital_status,
	gender,
	age,
	CASE 
		 WHEN age < 20 THEN 'Under 20'
		 WHEN age between 20 and 29 THEN '20-29'
		 WHEN age between 30 and 39 THEN '30-39'
		 WHEN age between 40 and 49 THEN '40-49'
		 ELSE '50 and above'
	END AS age_group,
	customer_lifetime_value,
	CASE 
		WHEN customer_lifetime_value >= 10000 THEN 'VIP Customer'
		WHEN customer_lifetime_value >= 5000 THEN 'High Value Customer'
		WHEN customer_lifetime_value >= 1000 THEN 'Medium Value Customer'
		ELSE 'Low Value Customer'
	END AS lifetime_value_segment,
	total_quantities,
	total_orders,
	average_order_value,
	first_purchase_date,
	last_purchase_date,
	lifespan,
	CASE 
		WHEN lifespan >= 24 THEN 'Long-term Customer'
		WHEN lifespan >= 12 THEN 'Established Customer'
		WHEN lifespan >= 6 THEN 'Developing Customer'
		ELSE 'New Customer'
	END AS lifespan_customer_segment,
	recency,
	r_score,
	f_score,
	m_score,
	RFM_code,
	CASE 
        -- Champions: Highly recent, high-frequency, and high-value customers
        WHEN R_Score >= 4 AND F_Score >= 4 AND M_Score >= 4 THEN 'Champions' 

        -- Loyal Customers: Buy regularly, responsive to promotions
        WHEN R_Score >= 4 AND F_Score >= 3 AND M_Score >= 3 THEN 'Loyal Customers' 

        -- Potential Loyalists: Recent customers showing potential to develop into repeat, higher-value customers
        WHEN R_Score >= 3 AND F_Score >= 3 AND M_Score <= 3 THEN 'Potential Loyalists'

        -- New Customers: Bought most recently, but not frequently yet
        WHEN R_Score >= 4 AND F_Score = 1 AND M_Score <= 2  THEN 'New Customers'

        -- Promising: Recent shoppers, but haven't spent much
        WHEN R_Score >= 3 AND F_Score <= 2 AND M_Score <= 3  THEN 'Promising'

        -- Need Attention: Previously valuable customers whose purchasing activity has 
		-- declined and requires re-engagement
        WHEN R_Score = 3 AND F_Score >= 2 AND M_Score >= 2 THEN 'Need Attention'

        -- About to Sleep: Below average recency and frequency
        WHEN R_Score = 2 AND F_Score <= 2 AND M_Score <= 2 THEN 'About to Sleep'

		-- Can't Lose Them: Made huge purchases but haven't returned in a long time
        WHEN R_Score = 1 AND F_Score >= 4 AND M_Score >= 4 THEN 'Can''t Lose Them'

        -- At Risk: Spent big and often, but it was a long time ago
        WHEN R_Score <= 2 AND F_Score >= 3 AND M_Score >= 3 THEN 'At Risk'

        -- Hibernating: Inactive customers with some historical purchasing value 
		-- who may still be worth reactivation
        WHEN R_Score = 1 AND (F_Score > 1 OR M_Score > 1) THEN 'Hibernate'

        -- Lost: Lowest scores across all metrics
		WHEN R_Score = 1 AND F_Score = 1 AND M_Score = 1 THEN 'Lost'

		-- Others represents RFM combinations that do not meet the defined strategic segmentation rules 
		-- and are retained for further analysis
        ELSE 'Others'
    END AS customer_RFM_segment
FROM RFM_code
