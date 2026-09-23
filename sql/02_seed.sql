-- ============================================================
-- 02_seed.sql : Realistic seed data
-- ============================================================
USE shopdb;

INSERT INTO customers (name,email,phone,status) VALUES
('Alice Johnson','alice@example.com','+1-415-555-0101','vip'),
('Bob Smith','bob@example.com','+1-415-555-0102','active'),
('Carol Davis','carol@example.com','+1-212-555-0103','active'),
('David Lee','david@example.com','+1-650-555-0104','inactive');

INSERT INTO addresses (customer_id,label,street,city,state,zip,is_default) VALUES
(1,'home','123 Market St','San Francisco','CA','94105',true),
(1,'work','500 Howard St','San Francisco','CA','94105',false),
(2,'home','45 5th Ave','New York','NY','10003',true),
(3,'home','78 Peachtree Rd','Atlanta','GA','30303',true),
(4,'home','10 Infinite Loop','Cupertino','CA','95014',true);

INSERT INTO categories (category_name, description, parent_id) VALUES
('Electronics','Devices and gadgets', NULL),
('Computers', 'Laptops & Desktops', 1),
('Accessories','Cables, mice, keyboards', 1),
('Books','Printed and e-books', NULL),
('Home','Home & Kitchen', NULL);

INSERT INTO products (sku,title,description,price,stock,category_id) VALUES
('SKU-LAP-001','UltraBook Pro 14','14\" laptop, 16GB RAM, 512GB SSD',1299.00,25,2),
('SKU-MOU-002','Ergo Wireless Mouse','Ergonomic BT mouse, 30-day battery',49.99,200,3),
('SKU-KEY-003','Mechanical Keyboard RGB','Hot-swap brown switches',89.50,120,3),
('SKU-BOK-004','Learning MySQL 9','Deep dive into JSON Duality Views',39.95,80,4),
('SKU-HOM-005','Smart Coffee Maker','WiFi-enabled, app control',149.00,40,5);

INSERT INTO orders (customer_id,status,order_date,shipping_address_id) VALUES
(1,'paid','2026-03-10 10:00:00',1),
(1,'shipped','2026-03-15 14:30:00',2),
(2,'pending','2026-03-18 09:12:00',3),
(3,'delivered','2026-03-20 16:45:00',4);

INSERT INTO order_items (order_id,product_id,quantity,unit_price) VALUES
(1,1,1,1299.00),
(1,2,2,49.99),
(2,3,1,89.50),
(2,4,1,39.95),
(3,5,1,149.00),
(3,2,1,49.99),
(4,1,1,1299.00);

INSERT INTO reviews (product_id,customer_id,rating,comment) VALUES
(1,1,5,'Fantastic laptop, super light!'),
(1,3,4,'Great but battery could be better'),
(2,2,5,'Best mouse I have owned'),
(4,1,5,'Explains Duality Views perfectly');
