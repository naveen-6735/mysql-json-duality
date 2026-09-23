#!/bin/bash
# 04_init_duality.sh - runs after 01_schema, 02_seed, 03_duality_views
# Makes deployment resilient: if native DUALITY VIEW failed (e.g. MySQL 8), create fallback JSON_OBJECT views
set +e

echo ">> [init_duality] checking MySQL version..."
VERSION=$(mysql -uroot -pshop_password -N -e "SELECT VERSION();" shopdb 2>&1)
echo ">> [init_duality] MySQL version: $VERSION"

# Check if native duality views exist and are queryable
HAS_DUALITY=0
mysql -uroot -pshop_password -N -e "SELECT COUNT(*) FROM information_schema.views WHERE table_schema='shopdb' AND table_name='customer_orders_jv';" shopdb 2>/dev/null | grep -q "1" && HAS_DUALITY=1

# Also probe by trying a select from the view - if it fails, duality is not usable
if [ "$HAS_DUALITY" -eq 1 ]; then
  mysql -uroot -pshop_password -e "SELECT * FROM shopdb.customer_orders_jv LIMIT 1;" 2>&1 | head -n 5
  if [ $? -ne 0 ]; then
    echo ">> [init_duality] native view exists but SELECT failed - will recreate fallback"
    HAS_DUALITY=0
  else
    echo ">> [init_duality] native JSON DUALITY VIEW is usable"
  fi
fi

# If duality creation from 03_duality_views.sql failed, code 1, we add fallback views
if [ "$HAS_DUALITY" -eq 0 ]; then
  echo ">> [init_duality] creating FALLBACK JSON_OBJECT views (MySQL 8 compatible)..."
  mysql -uroot -pshop_password shopdb <<'EOSQL'
USE shopdb;
DROP VIEW IF EXISTS customer_orders_jv;
DROP VIEW IF EXISTS product_catalog_jv;
DROP VIEW IF EXISTS order_detail_jv;

DROP VIEW IF EXISTS customer_orders_jv_fallback;
CREATE VIEW customer_orders_jv_fallback AS
SELECT JSON_OBJECT(
  '_id', c.customer_id,
  'name', c.name,
  'email', c.email,
  'phone', c.phone,
  'status', c.status,
  'addresses', COALESCE((SELECT JSON_ARRAYAGG(JSON_OBJECT('addressId', a.address_id,'label',a.label,'street',a.street,'city',a.city,'state',a.state,'zip',a.zip)) FROM addresses a WHERE a.customer_id=c.customer_id), JSON_ARRAY()),
  'orders', COALESCE((SELECT JSON_ARRAYAGG(JSON_OBJECT('orderId', o.order_id,'status',o.status,'orderDate',o.order_date,'totalAmount',o.total_amount,'items', COALESCE((SELECT JSON_ARRAYAGG(JSON_OBJECT('orderItemId', oi.order_item_id,'productId', oi.product_id,'quantity',oi.quantity,'unitPrice',oi.unit_price)) FROM order_items oi WHERE oi.order_id=o.order_id), JSON_ARRAY()))) FROM orders o WHERE o.customer_id=c.customer_id), JSON_ARRAY())
) AS doc FROM customers c;

DROP VIEW IF EXISTS product_catalog_jv_fallback;
CREATE VIEW product_catalog_jv_fallback AS
SELECT JSON_OBJECT(
  '_id', cat.category_id,
  'categoryName', cat.category_name,
  'description', cat.description,
  'products', COALESCE((SELECT JSON_ARRAYAGG(JSON_OBJECT('productId', p.product_id,'sku',p.sku,'title',p.title,'description',p.description,'price',p.price,'stock',p.stock,'reviews', COALESCE((SELECT JSON_ARRAYAGG(JSON_OBJECT('reviewId',r.review_id,'rating',r.rating,'comment',r.comment,'customerId',r.customer_id)) FROM reviews r WHERE r.product_id=p.product_id), JSON_ARRAY()))) FROM products p WHERE p.category_id=cat.category_id), JSON_ARRAY())
) AS doc FROM categories cat;

DROP VIEW IF EXISTS order_detail_jv_fallback;
CREATE VIEW order_detail_jv_fallback AS
SELECT JSON_OBJECT(
  '_id', o.order_id,
  'status', o.status,
  'orderDate', o.order_date,
  'totalAmount', o.total_amount,
  'customerId', o.customer_id,
  'customer', (SELECT JSON_OBJECT('customerId', c.customer_id,'name',c.name,'email',c.email) FROM customers c WHERE c.customer_id=o.customer_id),
  'items', COALESCE((SELECT JSON_ARRAYAGG(JSON_OBJECT('orderItemId', oi.order_item_id,'productId',oi.product_id,'quantity',oi.quantity,'unitPrice',oi.unit_price)) FROM order_items oi WHERE oi.order_id=o.order_id), JSON_ARRAY())
) AS doc FROM orders o;
EOSQL
  if [ $? -eq 0 ]; then
    echo ">> [init_duality] fallback views created successfully"
  else
    echo ">> [init_duality] ERROR creating fallback views"
  fi
else
  echo ">> [init_duality] native duality views OK - no fallback needed (API reads via data column, writes via relational fallback on 6503)"
  # Ensure fallback views do NOT try to SELECT FROM duality (error 6504), just keep them absent or create empty placeholder
  mysql -uroot -pshop_password shopdb <<'EOSQL'
USE shopdb;
DROP VIEW IF EXISTS customer_orders_jv_fallback;
DROP VIEW IF EXISTS product_catalog_jv_fallback;
DROP VIEW IF EXISTS order_detail_jv_fallback;
EOSQL
fi

echo ">> [init_duality] done. APIs can use duality if available, else fallback."
