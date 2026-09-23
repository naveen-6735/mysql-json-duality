# MySQL JSON Duality Views — ShopDB Demo
> **Two models, one world**: Normalized relational tables stay the *system of record*; **JSON Duality Views** expose hierarchical JSON documents for apps, APIs, and AI agents — fully updatable, zero duplication.

Realistic e-commerce scenario: **Customers ↔ Addresses, Categories → Products → Reviews, Orders → Order Items**. Includes 3 duality views, FastAPI over duality, single-file UI, and AI-agent tool demo.

Bonus: works on **MySQL 9.1+ (native duality)** *and* **MySQL 8.0 (fallback JSON_OBJECT views)** via version-gated init.

---

<img width="1046" height="733" alt="image" src="https://github.com/user-attachments/assets/c4c4cb34-d889-4a13-948c-75d25507ad3b" />


## What’s inside

- `sql/01_schema.sql` — 7 normalized tables + FK/UNIQUE/CHECK + triggers (`total_amount`)
- `sql/02_seed.sql` — realistic customers/products/orders
- `sql/03_duality_views.sql` — **3 JSON DUALITY VIEWs**:
  - `customer_orders_jv` — Customer root → addresses + orders → items → product
  - `product_catalog_jv` — Category → products → reviews
  - `order_detail_jv` — Order root → customer + items (checkout doc)
- `sql/04_demo_queries.sql` — before/after JSON comparison + INSERT/UPDATE/DELETE via JSON
- `api/` — FastAPI REST that **reads/writes through duality views** (`/api/customers`, `/api/catalog`, `/api/orders`, `/api/agent/query`)
- `ui/index.html` — zero-build SPA to test every duality CRUD from the browser
- `docker-compose.yml` + `scripts/init_duality.sh` — one-command run

---

## Architecture

See `docs/architecture.md` (mermaid diagram + trade-offs). TL;DR:

```
App (JS/Mobile/AI) --REST/JSON--> FastAPI --SELECT/INSERT on Duality View--> MySQL (normalized tables, governed)
```

---

## Prerequisites

- Docker + Docker Compose  (or local MySQL 9.1+ + Python 3.11)
- Ports free: 3306, 8000, 8080

No Node build needed for UI.

---

## Quick start (Docker — recommended)

```powershell
cd "D:\Zava Onboarding Agent\mysql-json-duality"

# 1. Start MySQL 9.4 + API + Adminer
docker compose up --build -d

# 2. Watch init (duality vs fallback auto-detected)
docker logs shop_mysql --follow
# Expect: "Creating NATIVE JSON DUALITY VIEWs" on MySQL 9.1+, else fallback

# 3. Check health
curl http://localhost:8000/health
# {"status":"ok","duality":true,"msg":"Using JSON DUALITY VIEW"}

# 4. Open UI
start ui\index.html
# Or open http://localhost:8000/_ui if you serve it via API (see alt below)
# Easiest: double-click ui\index.html -> set API base to http://localhost:8000

# 5. Optional: Adminer at http://localhost:8080  (server=mysql, user=root, pass=shop_password, db=shopdb)
```

> **Local without Docker**:
> ```powershell
> # MySQL: run sql\01_schema.sql, 02_seed.sql, 03_duality_views.sql in Workbench
> cd api
> pip install -r requirements.txt
> copy .env.example .env   # edit if needed
> uvicorn main:app --reload --port 8000
> # open ui\index.html
> ```

---

## How to test from UI (end-to-end)

Open `ui/index.html` in browser (API base = `http://localhost:8000`).

1. **Health badge** top: green = duality active, orange = fallback (MySQL 8). KPI shows counts.

2. **👥 Customers** tab:
   - Search “alice” → see filtered JSON.
   - Click **View JSON** → full doc: `{ name, addresses[], orders[ {items[ {product}]}] }`.
   - Copy `raw` JSON — that’s the duality doc, one fetch, no JOINs.

3. **📦 Catalog** tab → **Reload** → categories with nested products+reviews (from `product_catalog_jv`).

4. **➕ Create** tab:
   - **Customer**: leave defaults, click **Create Customer** → `INSERT INTO customer_orders_jv VALUES ('{...}')` (shreds to `customers`+`addresses`). Search new email in Customers tab.
   - **Order**: enter `customer_id=2, productId=3, qty=2` → **Create Order** → inserts via `order_detail_jv`, atomically creates `orders`+`order_items`, trigger updates `total_amount`. Check **🧾 Orders** tab.

5. **🧾 Orders** tab:
   - **View** any order → hierarchical JSON.
   - PATCH: enter `order id` + `shipped` → **PATCH status** → `UPDATE order_detail_jv SET doc=JSON_MERGE_PATCH(...)` (governed, FK intact).

6. **🤖 AI Agent** tab:
   - Click **show customer 1** / **show catalog** / **how many orders?** → demonstrates agent tool = one duality fetch.
   - Try custom: “show customer Alice”.

7. **⚖️ Before vs After** tab — compares manual `JSON_OBJECT+JSON_ARRAYAGG` vs declarative duality.

### cURL alternative

```powershell
curl http://localhost:8000/api/customers/1
curl http://localhost:8000/api/catalog
curl -X POST http://localhost:8000/api/customers -H "Content-Type: application/json" -d "{\"name\":\"Test\",\"email\":\"test_$(Get-Date -Format yyyyMMddHHmmss)@x.com\"}"
curl -X POST http://localhost:8000/api/orders -H "Content-Type: application/json" -d "{\"customer_id\":1,\"items\":[{\"productId\":1,\"quantity\":1}]}"
curl -X PATCH http://localhost:8000/api/orders/1 -H "Content-Type: application/json" -d "{\"status\":\"shipped\"}"
curl -X POST http://localhost:8000/api/agent/query -H "Content-Type: application/json" -d "{\"question\":\"show customer 1\"}"
```

### Verify governance (relational still protects)

```sql
-- In Adminer or mysql client:
INSERT INTO customer_orders_jv VALUES ('{"name":"Dup","email":"alice@example.com"}'); -- fails UNIQUE
INSERT INTO order_detail_jv VALUES ('{"status":"pending","customer":{"customerId":1},"items":[{"productId":999,"quantity":1,"unitPrice":10}]}'); -- fails FK
```

### Run SQL demo

```powershell
docker exec -i shop_mysql mysql -uroot -pshop_password shopdb < sql\04_demo_queries.sql
```

---

## Project structure — maintainable

- **SQL is source**: `01_schema.sql` (facts), `03_duality_views.sql` (only place JSON shape lives).
- **API is thin**: `api/main.py` — no ORM models drifting from DB; version detection handles 9.1 vs 8.
- **UI is zero-build**: single HTML file, fetch only.
- **Commit hygiene**: don’t commit `mysql_data` volume; seed is idempotent via `DROP DATABASE`.

---

## When to use vs not

See `docs/architecture.md` — table comparing **JSON column** vs **manual JSON_OBJECT** vs **Duality View** vs **ORM**.

Key: Use duality when you need **both** JSON ergonomics (JS/mobile/AI) **and** relational governance (FK, ACID, no duplication). Don’t use for pure blob workloads, >100KB docs, or sharded XA.

References:
- https://blogs.oracle.com/mysql/two-models-one-world-introducing-json-relational-duality-views-in-mysql-heatwave
- https://dev.mysql.com/doc/refman/9.7/en/json-duality-views-syntax.html
- https://dev.mysql.com/doc/refman/9.7/en/jdv-limitations.html

---

## Teardown

```powershell
docker compose down -v   # -v removes mysql_data
```
