/*
===============================================================================
Init Database: Create Database, Schema, and Tables
===============================================================================
Script Purpose:
    This script creates a new database named 'DataWarehouseAnalytics' after
    checking whether it already exists. If it exists, it is dropped and
    recreated. The script then creates a 'gold' schema (representing the
    business-ready / presentation layer of the warehouse) and three tables
    inside it:
        - gold.dim_customers  : customer dimension (who bought)
        - gold.dim_products   : product dimension (what was sold)
        - gold.fact_sales     : sales fact table (the transactions)
    Finally, it bulk-loads each table from the corresponding CSV file in
    the /datasets folder.

WARNING:
    Running this script will DROP the entire 'DataWarehouseAnalytics'
    database if it already exists. All data in it will be permanently
    deleted. Make sure you have a backup (or don't need one) before running.

BEFORE YOU RUN THIS:
    The BULK INSERT statements below use absolute Windows file paths
    (e.g. 'C:\...\datasets\dim_customers.csv'). Update these three paths to
    match the location of the /datasets folder on your own machine before
    executing this script.
===============================================================================
*/

USE master;
GO

-- ----------------------------------------------------------------------------
-- Step 1: Drop and recreate the 'DataWarehouseAnalytics' database
-- ----------------------------------------------------------------------------
IF EXISTS (SELECT 1 FROM sys.databases WHERE name = 'DataWarehouseAnalytics')
BEGIN
    ALTER DATABASE DataWarehouseAnalytics SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE DataWarehouseAnalytics;
END;
GO

CREATE DATABASE DataWarehouseAnalytics;
GO

USE DataWarehouseAnalytics;
GO

-- ----------------------------------------------------------------------------
-- Step 2: Create the 'gold' schema
-- This schema holds the clean, business-ready dimension and fact tables that
-- the three analysis scripts (customer, product, sales) build their views on.
-- ----------------------------------------------------------------------------
CREATE SCHEMA gold;
GO

-- ----------------------------------------------------------------------------
-- Step 3: Create tables
-- ----------------------------------------------------------------------------

-- Customer dimension: one row per customer, with demographic attributes.
-- Note: the source CSV's date-of-birth column is named "birthdate" while
-- this table names it "birth_date". BULK INSERT loads by column position
-- (not by name), so this mismatch does not break the load — but keep it in
-- mind if you ever rename columns or switch to a name-based import method.
CREATE TABLE gold.dim_customers (
	customer_key INT,
	customer_id INT,
	customer_number NVARCHAR(50),
	first_name NVARCHAR(50),
	last_name NVARCHAR(50),
	country NVARCHAR(50),
	marital_status NVARCHAR(50),
	gender NVARCHAR(50),
	birth_date DATE,
	create_date DATE
);
GO

-- Product dimension: one row per product, with category hierarchy and cost.
CREATE TABLE gold.dim_products (
	product_key INT,
	product_id INT,
	product_number NVARCHAR(50),
	product_name NVARCHAR(50),
	category_id NVARCHAR(50),
	category NVARCHAR(50),
	subcategory NVARCHAR(50),
	maintenance NVARCHAR(50),
	cost INT,
	product_line NVARCHAR(50),
	start_date DATE 
);
GO

-- Sales fact table: one row per order line item.
-- Links to gold.dim_customers via customer_key and gold.dim_products via product_key.
CREATE TABLE gold.fact_sales (
	order_number NVARCHAR(50),
	product_key INT,
	customer_key INT,
	order_date DATE,
	shipping_date DATE,
	due_date DATE,
	sales_amount INT,
	quantity TINYINT,
	price INT 
);
GO

-- ----------------------------------------------------------------------------
-- Step 4: Load data from CSV files
-- Each table is truncated first so the script is safely re-runnable.
-- Update the file paths below to point to your local /datasets folder.
-- ----------------------------------------------------------------------------

TRUNCATE TABLE gold.dim_customers;
GO

BULK INSERT gold.dim_customers
FROM 'C:\Users\USER\Desktop\MyProjects\SQL\SQL-Projects\Data_Warehouse_Project_Analytics\datasets\dim_customers.csv'
WITH (
	FIRSTROW = 2,          -- skip the header row
	FIELDTERMINATOR = ',',
	TABLOCK
);
GO

TRUNCATE TABLE gold.dim_products;
GO

BULK INSERT gold.dim_products
FROM 'C:\Users\USER\Desktop\MyProjects\SQL\SQL-Projects\Data_Warehouse_Project_Analytics\datasets\dim_products.csv'
WITH (
	FIRSTROW = 2,
	FIELDTERMINATOR = ',',
	TABLOCK
);
GO

TRUNCATE TABLE gold.fact_sales;
GO

BULK INSERT gold.fact_sales
FROM 'C:\Users\USER\Desktop\MyProjects\SQL\SQL-Projects\Data_Warehouse_Project_Analytics\datasets\fact_sales.csv'
WITH (
	FIRSTROW = 2,
	FIELDTERMINATOR = ',',
	TABLOCK
);
GO
