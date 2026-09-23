-- ============================================================
-- 03_duality_views.sql : JSON Duality Views (MySQL 9.4+)
-- Correct syntax uses JSON_DUALITY_OBJECT + JSON_ARRAYAGG
-- Each view is updatable via WITH(INSERT,UPDATE,DELETE)
-- See https://dev.mysql.com/doc/refman/9.7/en/json-duality-views-syntax.html
-- ============================================================
USE shopdb;

DROP VIEW IF EXISTS customer_orders_jv;
DROP VIEW IF EXISTS product_catalog_jv;
DROP VIEW IF EXISTS order_detail_jv;
DROP VIEW IF EXISTS customer_orders_jv_fallback;
DROP VIEW IF EXISTS product_catalog_jv_fallback;

-- =================================================================
-- VIEW 1: customer_orders_jv â€” Customer as root
-- one-to-many: customers -> addresses, customers -> orders -> order_items
-- Updatable: WITH(INSERT,UPDATE,DELETE) on root + nested
-- =================================================================
CREATE JSON DUALITY VIEW customer_orders_jv AS
SELECT JSON_DUALITY_OBJECT(WITH(INSERT,UPDATE,DELETE)
    '_id': customers.customer_id,
    'name': customers.name,
    'email': customers.email,
    'phone': customers.phone,
    'status': customers.status,
    'addresses': (
        SELECT JSON_ARRAYAGG(
            JSON_DUALITY_OBJECT(WITH(INSERT,UPDATE,DELETE)
                'addressId': addresses.address_id,
                'label': addresses.label,
                'street': addresses.street,
                'city': addresses.city,
                'state': addresses.state,
                'zip': addresses.zip
            )
        ) FROM addresses WHERE addresses.customer_id = customers.customer_id
    ),
    'orders': (
        SELECT JSON_ARRAYAGG(
            JSON_DUALITY_OBJECT(WITH(INSERT,UPDATE,DELETE)
                'orderId': orders.order_id,
                'status': orders.status,
                'orderDate': orders.order_date,
                'totalAmount': orders.total_amount,
                'items': (
                    SELECT JSON_ARRAYAGG(
                        JSON_DUALITY_OBJECT(WITH(INSERT,UPDATE,DELETE)
                            'orderItemId': order_items.order_item_id,
                            'productId': order_items.product_id,
                            'quantity': order_items.quantity,
                            'unitPrice': order_items.unit_price
                        )
                    ) FROM order_items WHERE order_items.order_id = orders.order_id
                )
            )
        ) FROM orders WHERE orders.customer_id = customers.customer_id
    )
) FROM customers;

-- =================================================================
-- VIEW 2: product_catalog_jv â€” Category -> Products -> Reviews
-- =================================================================
CREATE JSON DUALITY VIEW product_catalog_jv AS
SELECT JSON_DUALITY_OBJECT(WITH(INSERT,UPDATE,DELETE)
    '_id': categories.category_id,
    'categoryName': categories.category_name,
    'description': categories.description,
    'products': (
        SELECT JSON_ARRAYAGG(
            JSON_DUALITY_OBJECT(WITH(INSERT,UPDATE,DELETE)
                'productId': products.product_id,
                'sku': products.sku,
                'title': products.title,
                'description': products.description,
                'price': products.price,
                'stock': products.stock,
                'reviews': (
                    SELECT JSON_ARRAYAGG(
                        JSON_DUALITY_OBJECT(WITH(INSERT,UPDATE,DELETE)
                            'reviewId': reviews.review_id,
                            'rating': reviews.rating,
                            'comment': reviews.comment,
                            'customerId': reviews.customer_id
                        )
                    ) FROM reviews WHERE reviews.product_id = products.product_id
                )
            )
        ) FROM products WHERE products.category_id = categories.category_id
    )
) FROM categories;

-- =================================================================
-- VIEW 3: order_detail_jv â€” Order as root (singleton customer + nested items)
-- Demonstrates 1:1 (singleton) and 1:N (nested) together
-- =================================================================
CREATE JSON DUALITY VIEW order_detail_jv AS
SELECT JSON_DUALITY_OBJECT(WITH(INSERT,UPDATE,DELETE)
    '_id': orders.order_id,
    'status': orders.status,
    'orderDate': orders.order_date,
    'totalAmount': orders.total_amount,
    'customerId': orders.customer_id,
    'customer': (
        SELECT JSON_DUALITY_OBJECT(WITH(INSERT,UPDATE)
            'customerId': customers.customer_id,
            'name': customers.name,
            'email': customers.email
        ) FROM customers WHERE customers.customer_id = orders.customer_id
    ),
    'items': (
        SELECT JSON_ARRAYAGG(
            JSON_DUALITY_OBJECT(WITH(INSERT,UPDATE,DELETE)
                'orderItemId': order_items.order_item_id,
                'productId': order_items.product_id,
                'quantity': order_items.quantity,
                'unitPrice': order_items.unit_price
            )
        ) FROM order_items WHERE order_items.order_id = orders.order_id
    )
) FROM orders;
