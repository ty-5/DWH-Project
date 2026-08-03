-- find the customer with the second highest total sales amount across all orders

WITH total_sales_CTE AS
(
    SELECT
        customer_key,
        SUM(sales_amount) AS sum_sales
    FROM gold.fact_sales
    GROUP BY customer_key
),
ranked_CTE AS
(
    SELECT
        customer_key,
        sum_sales,
        ROW_NUMBER() OVER (ORDER BY sum_sales DESC) AS rn
    FROM total_sales_CTE
)
SELECT
    customer_key,
    sum_sales
FROM ranked_CTE
WHERE rn = 2;


-- find all customers who have never placed an order

SELECT
    c.customer_id,
    c.first_name,
    c.last_name
FROM gold.dim_customers c
WHERE NOT EXISTS (
    SELECT 1 FROM gold.fact_sales s
    WHERE c.customer_key = s.customer_key
)

SELECT
    c.customer_id,
    c.first_name,
    c.last_name
FROM gold.dim_customers c
LEFT JOIN gold.fact_sales s
ON c.customer_key = s.customer_key 
WHERE s.customer_key IS NULL

-- For each product category in dim_products, show one row with two numbers: 
-- the total sales amount, and separately, the total sales amount from line items
-- where quantity > 1 only (multi-item line orders)

SELECT
    p.category,
    SUM(s.sales_amount) AS sum_sales,
    SUM(CASE
            WHEN s.quantity > 1 THEN s.sales_amount
            ELSE 0
    END) AS sum_multi_item_sales
FROM gold.dim_products p
LEFT JOIN gold.fact_sales s ON p.product_key = s.product_key
GROUP BY p.category


-- For each product category, find the top 3 best-selling products by total sales amount.

WITH total_sales AS (
    SELECT
        p.category,
        p.product_name,
        SUM(s.sales_amount) AS sum_sales
    FROM gold.dim_products p
    JOIN gold.fact_sales s ON p.product_key = s.product_key
    GROUP BY p.product_name, p.category
 ),
 total_sales_ranked AS (
    SELECT
        category,
        product_name,
        sum_sales,
        ROW_NUMBER() OVER(PARTITION BY category ORDER BY sum_sales DESC) as ranking
    FROM total_sales
 )

 SELECT
    category,
    product_name,
    sum_sales,
    ranking
 FROM total_sales_ranked
 WHERE ranking IN (1,2,3)
 
 -- For each month, show the total sales amount, and the change in total sales compared to the previous month (month-over-month difference).

WITH date_table AS (
    SELECT
        YEAR(order_date) AS date_year,
        MONTH(order_date) AS date_month,
        SUM(sales_amount) AS total_sales
    FROM gold.fact_sales
    WHERE order_date IS NOT NULL
    GROUP BY YEAR(order_date), MONTH(order_date)
),
date_table_with_prev_month_sales AS (
    SELECT
        date_year,
        date_month,
        total_sales,
        LAG(total_sales) OVER(ORDER BY date_year, date_month) AS prev_month_sales
    FROM date_table
)

SELECT
    date_year,
    date_month,
    total_sales,
    prev_month_sales,
    total_sales - prev_month_sales AS change_in_sales_by_month
FROM date_table_with_prev_month_sales
ORDER BY date_year, date_month
