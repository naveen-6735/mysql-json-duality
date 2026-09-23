-- ============================================================
-- 04_demo_queries.sql : Comparing old JSON vs Duality Views
-- Plus Duality View CRUD examples
-- ============================================================
USE shopdb;

-- ------------------------------------------------------------
-- BEFORE Duality Views: manually build JSON (verbose, hard to maintain)
-- ------------------------------------------------------------
SELECT JSON_OBJECT(
  'customerId', c.customer_id,
  'name', c.name,
  'orders', (SELECT JSON_ARRAYAGG(JSON_OBJECT('orderId', o.order_id, 'status', o.status))
             FROM orders o WHERE o.customer_id=c.customer_id)
) AS manual_json
FROM customers c WHERE c.customer_id=1;

-- ------------------------------------------------------------
-- AFTER: Duality View — simple read (hierarchical JSON for free)
-- ------------------------------------------------------------
-- Read full customer document (MySQL 9.1+: selects from duality view return JSON)
SELECT * FROM customer_orders_jv WHERE _id = 1;  -- duality view auto-exposes _id field
-- For MySQL 8 fallback view: SELECT doc FROM customer_orders_jv_fallback ...

-- Get all customers as JSON array (REST API style)
SELECT JSON_ARRAYAGG(doc) FROM (SELECT doc FROM customer_orders_jv) t; -- fallback style

-- With native Duality Views, each row IS a JSON document:
SELECT c.doc FROM customer_orders_jv c;  -- if duality view exposes JSON column `data`
-- Note: exact projection depends on MySQL version; see dev.mysql.com/doc/refman/9.7/en/json-duality-views.html

-- Product catalog
SELECT * FROM product_catalog_jv WHERE _id = 1;

-- Single order checkout doc
SELECT * FROM order_detail_jv WHERE _id = 1;

-- ------------------------------------------------------------
-- DUALITY VIEW: UPDATABLE via JSON (relational tables stay governed)
-- ------------------------------------------------------------

-- INSERT a new customer with nested address + order in ONE statement:
INSERT INTO customer_orders_jv VALUES ('{
  "name":"Eve Martinez",
  "email":"eve@example.com",
  "phone":"+1-415-555-0199",
  "status":"active",
  "addresses":[{"label":"home","street":"99 Mission St","city":"San Francisco","state":"CA","zip":"94105"}],
  "orders":[]
}');

-- UPDATE: add address via JSON patch (MySQL 9.1+ supports JSON_MERGE_PATCH on duality view)
UPDATE customer_orders_jv SET doc = JSON_MERGE_PATCH(doc, '{"phone":"+1-415-555-9999"}') WHERE _id=1;

-- INSERT order via order_detail_jv (creates rows in orders + order_items atomically)
INSERT INTO order_detail_jv VALUES ('{
  "status":"pending",
  "customer":{"customerId":2},
  "items":[{"productId":3,"quantity":2,"unitPrice":89.50}]
}');

-- DELETE an order (cascades to order_items due to FK)
DELETE FROM order_detail_jv WHERE _id = 3;

-- ------------------------------------------------------------
-- GOVERNANCE DEMO: relational constraints still enforced
-- ------------------------------------------------------------
-- This fails: FK violation (product 999 doesn't exist)
-- INSERT INTO order_detail_jv VALUES ('{"status":"pending","customer":{"customerId":1},"items":[{"productId":999,"quantity":1,"unitPrice":10}]}');

-- This fails: UNIQUE email
-- INSERT INTO customer_orders_jv VALUES ('{"name":"Dup","email":"alice@example.com"}');

-- ------------------------------------------------------------
-- SEARCH inside JSON docs (use generated columns / JSON functions)
-- ------------------------------------------------------------
-- Find customers who ordered SKU-LAP-001
SELECT _id, JSON_EXTRACT(doc, '$.name') FROM customer_orders_jv
WHERE JSON_CONTAINS(doc, JSON_OBJECT('sku','SKU-LAP-001'), '$.orders[*].items[*].product');

-- Fulltext search still works on base tables: 
SELECT * FROM products WHERE MATCH(title,description) AGAINST('laptop' IN NATURAL LANGUAGE MODE);
