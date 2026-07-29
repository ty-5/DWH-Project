-- I want to index my gold.fact_sales table
-- Here is my methodology


-- ============================================================
-- I : customer_key — equality filtering
-- ============================================================

SELECT 
    s.name AS schema_name,
    t.name AS table_name,
    p.rows AS row_count
FROM sys.tables t
JOIN sys.schemas s ON s.schema_id = t.schema_id
JOIN sys.partitions p ON p.object_id = t.object_id
WHERE p.index_id IN (0, 1)   -- 0 = heap, 1 = clustered index
    AND s.name = 'gold'
ORDER BY p.rows DESC;


SELECT TOP 10 * FROM gold.fact_sales;

--what to index...
-- joining on product key, customer key
-- filtering on order date, price
-- group by product key

-- cardinality check for index candidates

SELECT 'product_key' AS column_name,
       COUNT(DISTINCT product_key) AS distinct_values,
       COUNT(*) AS total_rows,
       CAST(COUNT(DISTINCT product_key) AS FLOAT) / COUNT(*) AS selectivity_ratio,
       ROUND(CAST(COUNT(*) AS FLOAT) / COUNT(DISTINCT product_key), 2) AS avg_rows_per_value
FROM gold.fact_sales
UNION ALL
SELECT 'customer_key',
       COUNT(DISTINCT customer_key),
       COUNT(*),
       CAST(COUNT(DISTINCT customer_key) AS FLOAT) / COUNT(*),
       ROUND(CAST(COUNT(*) AS FLOAT) / COUNT(DISTINCT customer_key), 2) AS avg_rows_per_value
FROM gold.fact_sales
UNION ALL
SELECT 'order_date',
       COUNT(DISTINCT order_date),
       COUNT(*),
       CAST(COUNT(DISTINCT order_date) AS FLOAT) / COUNT(*),
       ROUND(CAST(COUNT(*) AS FLOAT) / COUNT(DISTINCT order_date), 2) AS avg_rows_per_value
FROM gold.fact_sales
UNION ALL
SELECT 'price',
       COUNT(DISTINCT price),
       COUNT(*),
       CAST(COUNT(DISTINCT price) AS FLOAT) / COUNT(*),
       ROUND(CAST(COUNT(*) AS FLOAT) / COUNT(DISTINCT price), 2) AS avg_rows_per_value
FROM gold.fact_sales;


-- avg rows per value may be misleading, going to find if the distributions are even or skewed
SELECT
MAX(rows_per_pk) AS maximum_rows_per_productkey,
AVG(CAST(rows_per_pk AS FLOAT)) AS average_rows_per_productkey
FROM (
    SELECT
        product_key,
        COUNT(*) as rows_per_pk
    FROM gold.fact_sales
    GROUP BY product_key
    )t;

SELECT
MAX(rows_per_price) AS maximum_rows_per_price,
ROUND(AVG(CAST(rows_per_price AS FLOAT)), 2) AS average_rows_per_price
FROM (
    SELECT
        price,
        COUNT(*) as rows_per_price
    FROM gold.fact_sales
    GROUP BY price
    )t

-- customer_key — strong, clear winner for equality lookups/joins
-- order_date — good, best suited for range filtering rather than single-day equality
-- product_key — decent for most values, weaker for one skewed outlier
-- price — weak on both counts, should drop it as a candidate

-- for customer_key filter

SELECT
    order_number,
    order_date,
    product_key,
    sales_amount,
    quantity
FROM gold.fact_sales
WHERE customer_key = 1324

-- Reading 100% of the table to return only 0.02% of it (11/60398)

--DROP INDEX IF EXISTS IX_fact_sales_customer_key ON gold.fact_sales;

--CREATE NONCLUSTERED INDEX IX_fact_sales_customer_key
--ON gold.fact_sales (customer_key);

-- 83 % of cost is for RID Lookup, can try to remove that cost by creating a covering index to reduce key lookups

DROP INDEX IF EXISTS IX_fact_sales_customer_key ON gold.fact_sales;

CREATE NONCLUSTERED INDEX IX_fact_sales_customer_key
ON gold.fact_sales (customer_key)
INCLUDE (order_number, order_date, product_key, sales_amount, quantity);

-- index physically stores 5 extra columns at every leaf entry.
-- trade off worth considering as there is now more write overhead.


-- ============================================================
-- II : order_date — range filtering
-- ============================================================

SELECT
    MIN(order_date) as earliest_date,
    MAX(order_date) as latest_date
FROM gold.fact_sales

-- query for exec plan
-- show all sales in the 4th quarter

SELECT
    sales_amount,
    order_date
FROM gold.fact_sales
WHERE DATEPART(quarter, order_date) = 4
ORDER BY YEAR(order_date) DESC, MONTH(order_date) DESC

-- since I wrapped order_date into a function, the index from the previous section will not work
-- because it is getting the quarter of every date before anything else, called a non-sargable-predicate. **revisit
-- to fix, will have to add an order_quarter col to the table so its seekable

SELECT 
    sales_amount,
    order_date
FROM gold.fact_sales
WHERE order_date >= '2013-01-01' AND order_date <= '2014-01-01'

-- earlier I calculated that are on average 54 rows per day for order_date
-- which means a full year is about 32% of the entire table.
-- in a scenario like this.. creating an index would likely not be usefull as the optimizer
-- will default to a table scan 

-- in order to showcase an index for the order_date column, let's hone in on a single month

SELECT 
    sales_amount,
    order_date
FROM gold.fact_sales
WHERE order_date >= '2013-03-01' AND order_date < '2013-04-01'


DROP INDEX IF EXISTS IX_fact_sales_order_date ON gold.fact_sales

CREATE NONCLUSTERED INDEX IX_fact_sales_order_date
ON gold.fact_sales (order_date)
INCLUDE(sales_amount)

-- ============================================================
-- III : (customer_key, order_date) — composite key
-- ============================================================

-- finding the skewed product key to test the new index (295)

SELECT TOP 1 product_key, COUNT(*) as row_count
FROM gold.fact_sales
GROUP BY product_key
ORDER BY row_count DESC


SELECT
    product_key,
    order_date,
    sales_amount
FROM gold.fact_sales
WHERE product_key = 295
    AND order_date >= '2013-01-01' AND order_date < '2013-04-01';

-- running the above query as is yeilds a missing index message in the exec plan with 99% impact so this is
-- a good place to try a composite index

DROP INDEX IF EXISTS IX_fact_sales_product_key_order_date ON gold.fact_sales;

CREATE NONCLUSTERED INDEX IX_fact_sales_product_key_order_date 
ON gold.fact_sales (product_key, order_date)
INCLUDE (sales_amount);

SELECT
    product_key,
    order_date,
    sales_amount
FROM gold.fact_sales WITH (INDEX(IX_fact_sales_product_key_order_date))
WHERE order_date >= '2013-01-01' AND order_date < '2013-04-01';

-- since we are filtering on the secondmost argument in the composite index,
-- it will not work. so what is being used is the order_date standalone index 
-- from earlier
