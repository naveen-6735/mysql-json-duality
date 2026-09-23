# Architecture — MySQL JSON Duality Views

## One source of truth, two access models

```
                    ┌─────────────────────────────────────┐
                    │         MySQL 9.1 HeatWave          │
                    │        (or 8.0 fallback)            │
┌──────────┐       │  ┌──────────────────────────────┐  │
│  Mobile  │       │  │  Normalized Tables (Govern)  │  │
│   App    │──────▶│  │  customers, addresses,       │  │
│  React   │  REST │  │  categories, products,       │  │
│   JS     │──────▶│  │  orders, order_items, reviews│  │
│  AI Agent│  JSON │  │  • PK/FK, UNIQUE, CHECK      │  │
└──────────┘       │  │  • Triggers (total_amount)   │  │
                   │  │  • Indexes + Fulltext        │  │
                   │  └──────────────┬───────────────┘  │
                   │                 │ Duality Mapping  │
                   │  ┌──────────────▼───────────────┐  │
                   │  │  JSON DUALITY VIEWs          │  │
                   │  │  • customer_orders_jv         │  │
                   │  │  • product_catalog_jv         │  │
                   │  │  • order_detail_jv            │  │
                   │  │  WITH UPDATE/INSERT/DELETE    │  │
                   │  └──────────────┬───────────────┘  │
                   └─────────────────┼──────────────────┘
                                     │ JSON doc
                              ┌──────▼──────┐
                              │  FastAPI    │
                              │  /api/*     │
                              │  + /agent   │
                              └──────┬──────┘
                                     │ fetch()
                              ┌──────▼──────┐
                              │  ui/index.html │
                              │  Vanilla JS SPA │
                              └─────────────┘
```

## Flow

1. **Write path** — `POST /api/customers { name, email, addresses[] }` → `INSERT INTO customer_orders_jv VALUES ('{...}')` → MySQL shreds JSON into `customers` + `addresses` rows atomically, enforcing FK/UNIQUE. On MySQL 8 fallback, API writes to base tables transactionally (same governance).

2. **Read path** — `GET /api/customers/1` → `SELECT * FROM customer_orders_jv WHERE _id=1` → single hierarchical JSON: `{ _id, name, addresses[], orders[ {items[ {product}]} ] }`. No JOINs in app.

3. **AI Agent** — tool `fetch_customer(id)` = one duality view fetch vs. 4 JOINs. Agent prompt: “You have tools: customer_orders_jv, product_catalog_jv, order_detail_jv”. LLM chooses doc, not SQL.

## Project structure — maintainable

```
mysql-json-duality/
  sql/
    01_schema.sql          # DDL - relational, triggers
    02_seed.sql            # seed - realistic demo
    03_duality_views.sql   # Duality View definitions (only place JSON mapping lives)
    04_demo_queries.sql    # before/after comparison + CRUD
  api/
    main.py                # FastAPI: thin REST over duality views
    database.py            # pool + version detection (duality vs fallback)
    Dockerfile + requirements.txt
  ui/
    index.html             # single-file SPA, zero build, tests duality CRUD
  scripts/init_duality.sh  # version-gated init (9.1 vs 8 fallback)
  docker-compose.yml       # mysql:9.4 + api + adminer
```

- **Separation**: Schema vs mapping vs app. Changing JSON shape = edit `03_duality_views.sql` only, no ORM migration.
- **Compatibility**: `FORCE_FALLBACK=1` env forces MySQL 8 path for testing without upgrading.
- **Extensibility**: Add new view (e.g., `support_ticket_jv`) without touching base tables.

## When to use / not use

| Use Duality View when | Avoid when |
|---|---|
| App wants JSON docs but enterprise needs normalized governance | Pure document workload with no relational integrity (use JSON column or MongoDB) |
| Modernizing existing relational app for JS/mobile/AI | Heavy analytics/OLAP over JSON internals (use relational or generated columns) |
| Need REST/MCP tools for agents: one doc per tool call | Very deep nesting >5 levels or >100KB docs (update cost, lock contention) |
| Want updatable JSON without duplication | Cross-shard transactions are required (HeatWave limits) |
| Compare to ORM: eliminates N+1, no model drift, DB enforces truth | Need polymorphic JSON with wildly varying shapes (use JSON column + JSON_SCHEMA) |

**Trade-offs vs JSON column**: JSON column is schemaless, fast for write-once blobs, but no FK, duplicates data, hard to query/govern. Duality = zero duplication, ACID, but DDL is stricter and view definitions must declare `@id/@nest` and `WITH CONDITION`.

**Trade-offs vs ORM (Prisma/SQLAlchemy)**: ORM moves JOIN logic to app, risks N+1, model drift. Duality pushes hierarchy to DB, single round-trip, DB remains source of truth. ORM still wins for complex business logic/migrations.

For limitations see: https://dev.mysql.com/doc/refman/9.7/en/jdv-limitations.html
