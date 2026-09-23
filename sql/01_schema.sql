-- ============================================================
-- 01_schema.sql : Normalized Relational System of Record
-- E-Commerce: Customers + Catalog + Orders
-- Compatible: MySQL 8.0+ / 9.x (HeatWave Duality Views)
-- ============================================================
DROP DATABASE IF EXISTS shopdb;
CREATE DATABASE shopdb CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
USE shopdb;

SET FOREIGN_KEY_CHECKS=0;
DROP TABLE IF EXISTS order_items;
DROP TABLE IF EXISTS orders;
DROP TABLE IF EXISTS reviews;
DROP TABLE IF EXISTS products;
DROP TABLE IF EXISTS categories;
DROP TABLE IF EXISTS customers;
DROP TABLE IF EXISTS addresses;
SET FOREIGN_KEY_CHECKS=1;

-- Customers: system of record, governed, indexed, ACID
CREATE TABLE customers (
  customer_id INT AUTO_INCREMENT PRIMARY KEY,
  name        VARCHAR(100) NOT NULL,
  email       VARCHAR(150) NOT NULL UNIQUE,
  phone       VARCHAR(20),
  created_at  DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  status      ENUM('active','inactive','vip') NOT NULL DEFAULT 'active',
  INDEX idx_customer_email (email)
) ENGINE=InnoDB;

CREATE TABLE addresses (
  address_id  INT AUTO_INCREMENT PRIMARY KEY,
  customer_id INT NOT NULL,
  label       ENUM('home','work','other') DEFAULT 'home',
  street      VARCHAR(200) NOT NULL,
  city        VARCHAR(100) NOT NULL,
  state       VARCHAR(100),
  zip         VARCHAR(20),
  country     VARCHAR(60) DEFAULT 'USA',
  is_default  BOOLEAN DEFAULT FALSE,
  FOREIGN KEY (customer_id) REFERENCES customers(customer_id) ON DELETE CASCADE,
  INDEX idx_addr_customer (customer_id)
) ENGINE=InnoDB;

CREATE TABLE categories (
  category_id   INT AUTO_INCREMENT PRIMARY KEY,
  category_name VARCHAR(100) NOT NULL UNIQUE,
  description   VARCHAR(300),
  parent_id     INT NULL,
  FOREIGN KEY (parent_id) REFERENCES categories(category_id) ON DELETE SET NULL
) ENGINE=InnoDB;

CREATE TABLE products (
  product_id   INT AUTO_INCREMENT PRIMARY KEY,
  sku          VARCHAR(40) NOT NULL UNIQUE,
  title        VARCHAR(200) NOT NULL,
  description  TEXT,
  price        DECIMAL(10,2) NOT NULL CHECK (price >= 0),
  stock        INT NOT NULL DEFAULT 0,
  category_id  INT,
  created_at   DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (category_id) REFERENCES categories(category_id) ON DELETE SET NULL,
  INDEX idx_product_category (category_id),
  FULLTEXT idx_ft_product (title, description)
) ENGINE=InnoDB;

CREATE TABLE orders (
  order_id     INT AUTO_INCREMENT PRIMARY KEY,
  customer_id  INT NOT NULL,
  status       ENUM('pending','paid','shipped','delivered','cancelled') NOT NULL DEFAULT 'pending',
  order_date   DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  total_amount DECIMAL(10,2) NOT NULL DEFAULT 0,
  shipping_address_id INT NULL,
  FOREIGN KEY (customer_id) REFERENCES customers(customer_id) ON DELETE RESTRICT,
  FOREIGN KEY (shipping_address_id) REFERENCES addresses(address_id) ON DELETE SET NULL,
  INDEX idx_order_customer (customer_id),
  INDEX idx_order_date (order_date)
) ENGINE=InnoDB;

CREATE TABLE order_items (
  order_item_id INT AUTO_INCREMENT PRIMARY KEY,
  order_id      INT NOT NULL,
  product_id    INT NOT NULL,
  quantity      INT NOT NULL CHECK (quantity > 0),
  unit_price    DECIMAL(10,2) NOT NULL,
  FOREIGN KEY (order_id) REFERENCES orders(order_id) ON DELETE CASCADE,
  FOREIGN KEY (product_id) REFERENCES products(product_id) ON DELETE RESTRICT,
  UNIQUE KEY uq_order_product (order_id, product_id),
  INDEX idx_item_product (product_id)
) ENGINE=InnoDB;

CREATE TABLE reviews (
  review_id   INT AUTO_INCREMENT PRIMARY KEY,
  product_id  INT NOT NULL,
  customer_id INT NOT NULL,
  rating      TINYINT NOT NULL CHECK (rating BETWEEN 1 AND 5),
  comment     TEXT,
  created_at  DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (product_id) REFERENCES products(product_id) ON DELETE CASCADE,
  FOREIGN KEY (customer_id) REFERENCES customers(customer_id) ON DELETE CASCADE,
  INDEX idx_review_product (product_id)
) ENGINE=InnoDB;

-- Trigger: keep orders.total_amount in sync (normalization benefit)
DELIMITER //
CREATE TRIGGER trg_order_items_after_insert AFTER INSERT ON order_items
FOR EACH ROW BEGIN
  UPDATE orders SET total_amount = (SELECT COALESCE(SUM(quantity*unit_price),0) FROM order_items WHERE order_id=NEW.order_id)
  WHERE order_id=NEW.order_id;
END//
CREATE TRIGGER trg_order_items_after_update AFTER UPDATE ON order_items
FOR EACH ROW BEGIN
  UPDATE orders SET total_amount = (SELECT COALESCE(SUM(quantity*unit_price),0) FROM order_items WHERE order_id=NEW.order_id)
  WHERE order_id=NEW.order_id;
END//
CREATE TRIGGER trg_order_items_after_delete AFTER DELETE ON order_items
FOR EACH ROW BEGIN
  UPDATE orders SET total_amount = (SELECT COALESCE(SUM(quantity*unit_price),0) FROM order_items WHERE order_id=OLD.order_id)
  WHERE order_id=OLD.order_id;
END//
DELIMITER ;
