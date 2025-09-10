-- E-COMMERCE SALES ANALYSIS PROJECT

-- Create database schema
CREATE DATABASE ecommerce_analytics;
USE ecommerce_analytics;

-- Create tables
CREATE TABLE customers (
    customer_id INT PRIMARY KEY,
    first_name VARCHAR(50),
    last_name VARCHAR(50),
    email VARCHAR(100),
    registration_date DATE,
    city VARCHAR(50),
    state VARCHAR(50),
    country VARCHAR(50)
);

CREATE TABLE products (
    product_id INT PRIMARY KEY,
    product_name VARCHAR(100),
    category VARCHAR(50),
    subcategory VARCHAR(50),
    price DECIMAL(10,2),
    cost DECIMAL(10,2),
    supplier_id INT
);

CREATE TABLE orders (
    order_id INT PRIMARY KEY,
    customer_id INT,
    order_date DATE,
    total_amount DECIMAL(10,2),
    status VARCHAR(20),
    shipping_cost DECIMAL(8,2),
    FOREIGN KEY (customer_id) REFERENCES customers(customer_id)
);

CREATE TABLE order_items (
    order_item_id INT PRIMARY KEY,
    order_id INT,
    product_id INT,
    quantity INT,
    unit_price DECIMAL(10,2),
    FOREIGN KEY (order_id) REFERENCES orders(order_id),
    FOREIGN KEY (product_id) REFERENCES products(product_id)
);

-- I added the files using import data on SSMS

-- View the tables
SELECT *
FROM customers;

SELECT *
FROM products;

SELECT *
FROM orders;

SELECT *
FROM order_items;

-- BUSINESS QUESTIONS & ANALYSIS

-- 1. Monthly Revenue Trend
WITH monthly_sales AS (
    SELECT
        CAST(YEAR(order_date) AS varchar(4))
          + '-' + RIGHT('0' + CAST(MONTH(order_date) AS varchar(2)), 2) AS [month],
        COUNT(order_id) AS total_orders,
        SUM(total_amount) AS revenue,
        AVG(total_amount) AS avg_order_value
    FROM orders
    WHERE status = 'Completed'
    GROUP BY
        CAST(YEAR(order_date) AS varchar(4)),
        MONTH(order_date)
)
SELECT
    [month],
    total_orders,
    revenue,
    avg_order_value,
    revenue
      - LAG(revenue) OVER (ORDER BY [month]) AS revenue_growth
FROM monthly_sales
ORDER BY [month];


WITH monthly_sales AS (
    SELECT
        CAST(YEAR(order_date) AS varchar(4))
          + '-' + RIGHT('0' + CAST(MONTH(order_date) AS varchar(2)), 2) AS [month],
        COUNT(order_id) AS total_orders,
        SUM(total_amount) AS revenue,
        AVG(total_amount) AS avg_order_value
    FROM orders
    WHERE status = 'Completed'
    GROUP BY
        CAST(YEAR(order_date) AS varchar(4)),
        MONTH(order_date)
)
SELECT
    [month],
    total_orders,
    ROUND(revenue, 2) AS revenue,
    ROUND(avg_order_value, 2) AS avg_order_value,
    ROUND(revenue - LAG(revenue) OVER (ORDER BY [month]), 2) AS revenue_growth,
    CASE 
        WHEN LAG(revenue) OVER (ORDER BY [month]) IS NULL
             OR LAG(revenue) OVER (ORDER BY [month]) = 0
        THEN NULL
        ELSE CONCAT(
            CAST(ROUND(
                (revenue - LAG(revenue) OVER (ORDER BY [month])) 
                / LAG(revenue) OVER (ORDER BY [month]) * 100, 2
            ) AS DECIMAL(5,2)),
            '%'
        )
    END AS revenue_growth_pct
FROM monthly_sales
ORDER BY [month];


-- 2. Top Performing Products by Revenue
SELECT TOP 10
    p.product_name,
    p.category,
    SUM(oi.quantity) as units_sold,
    SUM(oi.quantity * oi.unit_price) as total_revenue,
    SUM(oi.quantity * (oi.unit_price - p.cost)) as profit,
    ROUND(SUM(oi.quantity * (oi.unit_price - p.cost)) / SUM(oi.quantity * oi.unit_price) * 100, 2) as profit_margin_percent
FROM products p
JOIN order_items oi ON p.product_id = oi.product_id
JOIN orders o ON oi.order_id = o.order_id
WHERE o.status = 'completed'
GROUP BY p.product_id, p.product_name, p.category
ORDER BY total_revenue DESC;

-- 3. Customer Lifetime Value (CLV) Analysis
SELECT 
    c.customer_id,
    c.first_name + ' ' + c.last_name AS customer_name,
    c.registration_date,
    COUNT(o.order_id) AS total_orders,
    SUM(o.total_amount) AS lifetime_value,
    AVG(o.total_amount) AS avg_order_value,
    DATEDIFF(day, c.registration_date, GETDATE()) AS days_since_registration,
    CASE 
        WHEN COUNT(o.order_id) >= 10 THEN 'VIP'
        WHEN COUNT(o.order_id) >= 5 THEN 'Loyal'
        WHEN COUNT(o.order_id) >= 2 THEN 'Regular'
        ELSE 'New'
    END AS customer_segment
FROM customers c
LEFT JOIN orders o 
    ON c.customer_id = o.customer_id 
    AND o.status = 'Completed'
GROUP BY c.customer_id, c.first_name, c.last_name, c.registration_date
ORDER BY lifetime_value DESC;

-- 4. Quick summary of Customer Lifetime Value (CLV) Analysis
WITH customer_segments AS (
    SELECT 
        c.customer_id,
        CASE 
            WHEN COUNT(o.order_id) >= 10 THEN 'VIP'
            WHEN COUNT(o.order_id) >= 5 THEN 'Loyal'
            WHEN COUNT(o.order_id) >= 2 THEN 'Regular'
            ELSE 'New'
        END AS customer_segment
    FROM customers c
    LEFT JOIN orders o 
        ON c.customer_id = o.customer_id 
        AND o.status = 'Completed'
    GROUP BY c.customer_id
)
SELECT 
    customer_segment,
    COUNT(*) AS customer_count
FROM customer_segments
GROUP BY customer_segment
ORDER BY 
    CASE customer_segment
        WHEN 'VIP' THEN 1
        WHEN 'Loyal' THEN 2
        WHEN 'Regular' THEN 3
        WHEN 'New' THEN 4
    END;


-- 5. Product Category Performance
WITH category_metrics AS (
    SELECT 
        p.category,
        COUNT(DISTINCT p.product_id) as product_count,
        SUM(oi.quantity) as units_sold,
        SUM(oi.quantity * oi.unit_price) as revenue,
        AVG(oi.unit_price) as avg_selling_price,
        SUM(oi.quantity * p.cost) as total_cost
    FROM products p
    JOIN order_items oi ON p.product_id = oi.product_id
    JOIN orders o ON oi.order_id = o.order_id
    WHERE o.status = 'completed'
    GROUP BY p.category
)
SELECT 
    category,
    product_count,
    units_sold,
    revenue,
    revenue - total_cost as profit,
    ROUND((revenue - total_cost) / revenue * 100, 2) as profit_margin,
    RANK() OVER (ORDER BY revenue DESC) as revenue_rank
FROM category_metrics
ORDER BY revenue DESC;

-- 6. Customer Retention Analysis
WITH customer_orders AS (
    SELECT 
        customer_id,
        order_date,
        ROW_NUMBER() OVER (PARTITION BY customer_id ORDER BY order_date) AS order_number,
        LAG(order_date) OVER (PARTITION BY customer_id ORDER BY order_date) AS previous_order_date
    FROM orders
    WHERE status = 'Completed'
)
SELECT 
    order_number,
    COUNT(*) AS customer_count,
    AVG(DATEDIFF(day, previous_order_date, order_date)) AS avg_days_between_orders
FROM customer_orders
WHERE order_number <= 5  -- Focus on first 5 orders
GROUP BY order_number
ORDER BY order_number;


-- 7. Seasonal Sales Pattern
SELECT 
    MONTH(order_date) AS month,
    DATENAME(MONTH, order_date) AS month_name,
    COUNT(order_id) AS total_orders,
    SUM(total_amount) AS revenue,
    AVG(total_amount) AS avg_order_value
FROM orders
WHERE status = 'Completed'
GROUP BY MONTH(order_date), DATENAME(MONTH, order_date)
ORDER BY month;


-- 8. Geographic Sales Distribution
SELECT 
    c.state,
    c.country,
    COUNT(DISTINCT c.customer_id) as customer_count,
    COUNT(o.order_id) as total_orders,
    SUM(o.total_amount) as revenue,
    AVG(o.total_amount) as avg_order_value,
    SUM(o.total_amount) / COUNT(DISTINCT c.customer_id) as revenue_per_customer
FROM customers c
JOIN orders o ON c.customer_id = o.customer_id
WHERE o.status = 'completed'
GROUP BY c.state, c.country

ORDER BY revenue DESC;
