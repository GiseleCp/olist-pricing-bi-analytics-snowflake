USE WAREHOUSE olist_wh;
USE DATABASE olist_db;
USE SCHEMA raw;

COPY INTO olist_db.raw.customers
FROM @olist_db.raw.raw_stage/olist_customers_dataset.csv
FILE_FORMAT = (TYPE = 'CSV' FIELD_OPTIONALLY_ENCLOSED_BY = '"' SKIP_HEADER = 1);

COPY INTO olist_db.raw.geolocation
FROM @olist_db.raw.raw_stage/olist_geolocation_dataset.csv
FILE_FORMAT = (TYPE = 'CSV' FIELD_OPTIONALLY_ENCLOSED_BY = '"' SKIP_HEADER = 1);

COPY INTO olist_db.raw.order_items
FROM @olist_db.raw.raw_stage/olist_order_items_dataset.csv
FILE_FORMAT = (TYPE = 'CSV' FIELD_OPTIONALLY_ENCLOSED_BY = '"' SKIP_HEADER = 1);

COPY INTO olist_db.raw.order_payments
FROM @olist_db.raw.raw_stage/olist_order_payments_dataset.csv
FILE_FORMAT = (TYPE = 'CSV' FIELD_OPTIONALLY_ENCLOSED_BY = '"' SKIP_HEADER = 1);

COPY INTO olist_db.raw.order_reviews
FROM @olist_db.raw.raw_stage/olist_order_reviews_dataset.csv
FILE_FORMAT = (TYPE = 'CSV' FIELD_OPTIONALLY_ENCLOSED_BY = '"' SKIP_HEADER = 1);

COPY INTO olist_db.raw.orders
FROM @olist_db.raw.raw_stage/olist_orders_dataset.csv
FILE_FORMAT = (TYPE = 'CSV' FIELD_OPTIONALLY_ENCLOSED_BY = '"' SKIP_HEADER = 1);

COPY INTO olist_db.raw.products
FROM @olist_db.raw.raw_stage/olist_products_dataset.csv
FILE_FORMAT = (TYPE = 'CSV' FIELD_OPTIONALLY_ENCLOSED_BY = '"' SKIP_HEADER = 1);

COPY INTO olist_db.raw.sellers
FROM @olist_db.raw.raw_stage/olist_sellers_dataset.csv
FILE_FORMAT = (TYPE = 'CSV' FIELD_OPTIONALLY_ENCLOSED_BY = '"' SKIP_HEADER = 1);

COPY INTO olist_db.raw.category_translation
FROM @olist_db.raw.raw_stage/product_category_name_translation.csv
FILE_FORMAT = (TYPE = 'CSV' FIELD_OPTIONALLY_ENCLOSED_BY = '"' SKIP_HEADER = 1);

SELECT COUNT(*) FROM customers;
SELECT COUNT(*) FROM orders;
SELECT COUNT(*) FROM order_items;
SELECT COUNT(*) FROM products;