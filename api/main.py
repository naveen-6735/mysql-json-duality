"""
FastAPI app bridging relational MySQL <-> JSON Duality Views
Endpoints read/write THROUGH duality views so app sees JSON,
DB keeps normalized, governed data.
"""
import json
import os
from typing import Any, Optional
from fastapi import FastAPI, HTTPException, Query
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
from database import query, execute, duality_available

app = FastAPI(
    title="ShopDB Duality View API",
    description="REST API over MySQL JSON Duality Views. Relational = system of record, JSON = app interface.",
    version="1.0.0",
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

# ---------- Helpers ----------
USE_DUALITY = None  # lazy detect

def is_duality() -> bool:
    global USE_DUALITY
    if USE_DUALITY is None:
        try:
            USE_DUALITY = duality_available()
        except Exception:
            USE_DUALITY = False
    # allow override via env
    if os.getenv("FORCE_FALLBACK") == "1":
        return False
    return USE_DUALITY

def parse_doc(row: dict) -> dict:
    """Normalize row -> JSON doc. Handles both duality native `data` and fallback `doc`."""
    if row is None:
        return None
    if "data" in row:
        v = row["data"]
        if isinstance(v, (str, bytes)):
            try:
                return json.loads(v)
            except Exception:
                return v
        return v
    if "doc" in row and isinstance(row["doc"], (str, bytes)):
        try:
            return json.loads(row["doc"])
        except Exception:
            return row["doc"]
    if "doc" in row and isinstance(row["doc"], dict):
        return row["doc"]
    return row

# ---------- Models ----------
class CustomerCreate(BaseModel):
    name: str
    email: str
    phone: Optional[str] = None
    status: Optional[str] = "active"
    addresses: Optional[list] = None

class OrderCreate(BaseModel):
    customer_id: int
    status: Optional[str] = "pending"
    items: list  # [{productId, quantity}]

class AgentQuery(BaseModel):
    question: str

# ---------- Health ----------
@app.get("/health")
def health():
    return {"status": "ok", "duality": is_duality(), "msg": "Using JSON DUALITY VIEW" if is_duality() else "Using fallback JSON_OBJECT view (MySQL 8 compatible)"}

# ---------- Customers (via customer_orders_jv) ----------
@app.get("/api/customers")
def list_customers(limit: int = 20, search: Optional[str] = None):
    if is_duality():
        # Native duality view: each row is JSON doc; select JSON_OBJECT from view or select *
        # MySQL 9.7: SELECT * FROM customer_orders_jv returns JSON docs in `data` column or expanded
        # We handle both: try expanded, fallback to doc
        try:
            rows = query("SELECT * FROM customer_orders_jv LIMIT %s", (limit,))
            # If duality returns `data` JSON column:
            if rows and "data" in rows[0]:
                docs = [json.loads(r["data"]) if isinstance(r["data"], str) else r["data"] for r in rows]
            elif rows and "doc" in rows[0]:
                docs = [parse_doc(r) for r in rows]
            else:
                docs = rows  # already JSON-like
            if search:
                docs = [d for d in docs if search.lower() in json.dumps(d).lower()]
            return docs
        except Exception as e:
            raise HTTPException(500, f"Duality query failed: {e}")
    else:
        # Fallback view
        if search:
            rows = query("SELECT doc FROM customer_orders_jv_fallback WHERE JSON_EXTRACT(doc,'$.name') LIKE %s OR JSON_EXTRACT(doc,'$.email') LIKE %s LIMIT %s",
                         (f"%{search}%", f"%{search}%", limit))
        else:
            rows = query("SELECT doc FROM customer_orders_jv_fallback LIMIT %s", (limit,))
        docs = []
        for r in rows:
            v = r["doc"]
            docs.append(json.loads(v) if isinstance(v, str) else v)
        return docs

@app.get("/api/customers/{customer_id}")
def get_customer(customer_id: int):
    if is_duality():
        try:
            row = query("SELECT data FROM customer_orders_jv WHERE JSON_EXTRACT(data, '$._id') = %s", (customer_id,), fetch="one")
            if not row:
                raise HTTPException(404, "Customer not found")
            return parse_doc(row)
        except HTTPException:
            raise
        except Exception as e:
            raise HTTPException(500, str(e))
    else:
        row = query("SELECT doc FROM customer_orders_jv_fallback WHERE JSON_EXTRACT(doc,'$._id')=%s", (customer_id,), fetch="one")
        if not row:
            raise HTTPException(404, "Customer not found")
        v = row["doc"]
        return json.loads(v) if isinstance(v, str) else v

@app.post("/api/customers", status_code=201)
def create_customer(payload: CustomerCreate):
    # Try Duality INSERT first (HeatWave), fallback to relational (Community 9.4)
    if is_duality():
        doc = {
            "name": payload.name,
            "email": payload.email,
            "phone": payload.phone,
            "status": payload.status or "active",
            "addresses": payload.addresses or [],
            "orders": []
        }
        try:
            execute("INSERT INTO customer_orders_jv VALUES (%s)", (json.dumps(doc),))
            row = query("SELECT data FROM customer_orders_jv WHERE JSON_EXTRACT(data, '$.email')=%s ORDER BY JSON_EXTRACT(data, '$._id') DESC LIMIT 1", (payload.email,), fetch="one")
            if row:
                return parse_doc(row)
            return doc
        except Exception as e:
            # 6503 = DML not available in Community, fallback to relational
            if "6503" not in str(e) and "Feature not available" not in str(e):
                # For duplicate etc., still try to show error but fallback if duality DML blocked
                pass
            # Fallback relational (always governed)
            try:
                cid = execute("INSERT INTO customers (name,email,phone,status) VALUES (%s,%s,%s,%s)",
                              (payload.name, payload.email, payload.phone, payload.status or "active"))
                if payload.addresses:
                    for a in payload.addresses:
                        execute("INSERT INTO addresses (customer_id,label,street,city,state,zip) VALUES (%s,%s,%s,%s,%s,%s)",
                                (cid, a.get("label","home"), a.get("street",""), a.get("city",""), a.get("state",""), a.get("zip","")))
                # fetch via duality read (so response shape is duality doc)
                row2 = query("SELECT data FROM customer_orders_jv WHERE JSON_EXTRACT(data, '$._id')=%s", (cid,), fetch="one")
                if row2:
                    return parse_doc(row2)
                return get_customer(cid)
            except Exception as e2:
                raise HTTPException(400, f"Insert failed (check UNIQUE email): {e2} (duality error was: {e})")
    else:
        try:
            cid = execute("INSERT INTO customers (name,email,phone,status) VALUES (%s,%s,%s,%s)",
                          (payload.name, payload.email, payload.phone, payload.status or "active"))
            if payload.addresses:
                for a in payload.addresses:
                    execute("INSERT INTO addresses (customer_id,label,street,city,state,zip) VALUES (%s,%s,%s,%s,%s,%s)",
                            (cid, a.get("label","home"), a.get("street",""), a.get("city",""), a.get("state",""), a.get("zip","")))
            return get_customer(cid)
        except Exception as e:
            raise HTTPException(400, str(e))

@app.delete("/api/customers/{customer_id}")
def delete_customer(customer_id: int):
    if is_duality():
        try:
            row = query("SELECT data FROM customer_orders_jv WHERE JSON_EXTRACT(data, '$._id')=%s", (customer_id,), fetch="one")
            if not row:
                raise HTTPException(404, "Not found")
            try:
                execute("DELETE FROM customer_orders_jv WHERE JSON_EXTRACT(data, '$._id')=%s", (customer_id,))
                return {"deleted": customer_id}
            except Exception as e:
                if "6503" in str(e) or "Feature not available" in str(e):
                    # Fallback relational delete (will enforce FK)
                    execute("DELETE FROM customers WHERE customer_id=%s", (customer_id,))
                    return {"deleted": customer_id, "via": "relational fallback (duality DML not in Community)"}
                raise
        except HTTPException:
            raise
        except Exception as e:
            raise HTTPException(400, f"Delete blocked by FK (customer has orders): {e}")
    else:
        try:
            execute("DELETE FROM customers WHERE customer_id=%s", (customer_id,))
            return {"deleted": customer_id}
        except Exception as e:
            raise HTTPException(400, str(e))

# ---------- Catalog ----------
@app.get("/api/catalog")
def get_catalog():
    if is_duality():
        try:
            rows = query("SELECT data FROM product_catalog_jv")
            return [parse_doc(r) for r in rows]
        except Exception as e:
            raise HTTPException(500, str(e))
    else:
        rows = query("SELECT doc FROM product_catalog_jv_fallback")
        return [json.loads(r["doc"]) if isinstance(r["doc"], str) else r["doc"] for r in rows]

@app.get("/api/products")
def list_products(q: Optional[str] = None, category: Optional[int] = None):
    sql = "SELECT product_id, sku, title, description, price, stock, category_id FROM products WHERE 1=1"
    params = []
    if q:
        sql += " AND (title LIKE %s OR description LIKE %s)"
        params.extend([f"%{q}%", f"%{q}%"])
    if category:
        sql += " AND category_id=%s"
        params.append(category)
    sql += " LIMIT 100"
    return query(sql, tuple(params))

@app.get("/api/products/{product_id}")
def get_product(product_id: int):
    row = query("SELECT * FROM products WHERE product_id=%s", (product_id,), fetch="one")
    if not row:
        raise HTTPException(404, "Product not found")
    revs = query("SELECT * FROM reviews WHERE product_id=%s", (product_id,))
    row["reviews"] = revs
    return row

# ---------- Orders (via order_detail_jv) ----------
@app.get("/api/orders")
def list_orders(customer_id: Optional[int] = None):
    if is_duality():
        try:
            rows = query("SELECT data FROM order_detail_jv LIMIT 50")
            docs = [parse_doc(r) for r in rows]
            if customer_id:
                docs = [d for d in docs if d.get('customerId') == customer_id or (d.get('customer') and d['customer'].get('customerId') == customer_id)]
            return docs
        except Exception as e:
            rows = query("SELECT * FROM orders LIMIT 50")
            for r in rows:
                r["items"] = query("SELECT * FROM order_items WHERE order_id=%s", (r["order_id"],))
            return rows
    else:
        orders = query("SELECT * FROM orders LIMIT 50")
        for o in orders:
            o["customer"] = query("SELECT customer_id, name, email FROM customers WHERE customer_id=%s", (o["customer_id"],), fetch="one")
            o["items"] = query("""
                SELECT oi.*, p.sku, p.title FROM order_items oi
                JOIN products p ON p.product_id=oi.product_id WHERE oi.order_id=%s
            """, (o["order_id"],))
        if customer_id:
            orders = [o for o in orders if o["customer_id"]==customer_id]
        return orders

@app.get("/api/orders/{order_id}")
def get_order(order_id: int):
    if is_duality():
        try:
            row = query("SELECT data FROM order_detail_jv WHERE JSON_EXTRACT(data, '$._id')=%s", (order_id,), fetch="one")
            if row:
                return parse_doc(row)
        except Exception:
            pass
    o = query("SELECT * FROM orders WHERE order_id=%s", (order_id,), fetch="one")
    if not o:
        raise HTTPException(404, "Order not found")
    o["customer"] = query("SELECT customer_id, name, email FROM customers WHERE customer_id=%s", (o["customer_id"],), fetch="one")
    o["items"] = query("SELECT oi.*, p.sku, p.title FROM order_items oi JOIN products p ON p.product_id=oi.product_id WHERE oi.order_id=%s", (order_id,))
    return o

@app.post("/api/orders", status_code=201)
def create_order(payload: OrderCreate):
    if is_duality():
        # Try duality insert, fallback to relational on 6503 (Community edition)
        doc = {
            "_id": None,
            "status": payload.status,
            "customer": {"customerId": payload.customer_id},
            "items": [{"productId": i["productId"], "quantity": i["quantity"], "unitPrice": i.get("unitPrice") or 0} for i in payload.items]
        }
        for it in doc["items"]:
            if not it["unitPrice"]:
                p = query("SELECT price FROM products WHERE product_id=%s", (it["productId"],), fetch="one")
                if not p:
                    raise HTTPException(400, f"Product {it['productId']} not found")
                it["unitPrice"] = float(p["price"])
        try:
            execute("INSERT INTO order_detail_jv VALUES (%s)", (json.dumps(doc),))
            row = query("SELECT order_id FROM orders WHERE customer_id=%s ORDER BY order_id DESC LIMIT 1", (payload.customer_id,), fetch="one")
            return get_order(row["order_id"]) if row else doc
        except Exception as e:
            if "6503" not in str(e) and "Feature not available" not in str(e):
                pass
            # fallback relational
            try:
                oid = execute("INSERT INTO orders (customer_id,status) VALUES (%s,%s)", (payload.customer_id, payload.status))
                for it in payload.items:
                    p = query("SELECT price FROM products WHERE product_id=%s", (it["productId"],), fetch="one")
                    if not p:
                        raise HTTPException(400, f"Product {it['productId']} not found")
                    price = it.get("unitPrice") or float(p["price"])
                    execute("INSERT INTO order_items (order_id,product_id,quantity,unit_price) VALUES (%s,%s,%s,%s)",
                            (oid, it["productId"], it["quantity"], price))
                return get_order(oid)
            except HTTPException:
                raise
            except Exception as e2:
                raise HTTPException(400, f"Order create failed: {e2} (duality error: {e})")
    else:
        try:
            oid = execute("INSERT INTO orders (customer_id,status) VALUES (%s,%s)", (payload.customer_id, payload.status))
            for it in payload.items:
                p = query("SELECT price FROM products WHERE product_id=%s", (it["productId"],), fetch="one")
                if not p:
                    raise HTTPException(400, f"Product {it['productId']} not found")
                price = it.get("unitPrice") or float(p["price"])
                execute("INSERT INTO order_items (order_id,product_id,quantity,unit_price) VALUES (%s,%s,%s,%s)",
                        (oid, it["productId"], it["quantity"], price))
            return get_order(oid)
        except HTTPException:
            raise
        except Exception as e:
            raise HTTPException(400, str(e))

@app.patch("/api/orders/{order_id}")
def update_order(order_id: int, payload: dict):
    if "status" not in payload:
        raise HTTPException(400, "Only status update supported in demo")
    if is_duality():
        try:
            execute("UPDATE order_detail_jv SET data = JSON_MERGE_PATCH(data, %s) WHERE JSON_EXTRACT(data, '$._id')=%s", (json.dumps({"status": payload["status"]}), order_id))
            return get_order(order_id)
        except Exception as e:
            if "6503" in str(e) or "Feature not available" in str(e):
                execute("UPDATE orders SET status=%s WHERE order_id=%s", (payload["status"], order_id))
                return get_order(order_id)
            execute("UPDATE orders SET status=%s WHERE order_id=%s", (payload["status"], order_id))
            return get_order(order_id)
    else:
        execute("UPDATE orders SET status=%s WHERE order_id=%s", (payload["status"], order_id))
        return get_order(order_id)

# ---------- AI Agent Bonus ----------
@app.post("/api/agent/query")
def agent_query(q: AgentQuery):
    """
    Simple AI-agent-style data-access: natural language -> SQL/JSON via Duality Views.
    No LLM call here (offline), but shows how duality views simplify agent tool use:
    Agent can request ONE JSON document instead of JOINs.
    """
    question = q.question.lower()
    # naive intent routing - in real app, LLM would generate SQL or call duality view
    if "customer" in question and ("alice" in question or "1" in question):
        doc = get_customer(1)
        return {"answer": "Customer Alice Johnson with nested orders", "data": doc, "via": "customer_orders_jv (single JSON doc)"}
    if "catalog" in question or "product" in question:
        return {"answer": "Full catalog with categories -> products -> reviews", "data": get_catalog(), "via": "product_catalog_jv"}
    if "order" in question:
        return {"answer": "Orders as JSON documents", "data": list_orders(), "via": "order_detail_jv"}
    if "how many" in question or "count" in question:
        cnt = query("SELECT COUNT(*) as c FROM orders", fetch="one")["c"]
        return {"answer": f"There are {cnt} orders in the system.", "count": cnt, "via": "relational count (governed)"}
    # default: explain duality benefit
    return {
        "answer": "I can fetch any entity as a hierarchical JSON document via Duality Views — no manual JOINs. Try: 'show customer 1', 'show catalog', 'list orders'.",
        "hint": "In a real LLM agent, tool definition would be: fetch_customer(id) -> customer_orders_jv._id, fetch_catalog() -> product_catalog_jv",
        "duality": is_duality()
    }

# ---------- Stats ----------
@app.get("/api/stats")
def stats():
    return {
        "customers": query("SELECT COUNT(*) as c FROM customers", fetch="one")["c"],
        "products": query("SELECT COUNT(*) as c FROM products", fetch="one")["c"],
        "orders": query("SELECT COUNT(*) as c FROM orders", fetch="one")["c"],
        "duality": is_duality(),
    }
