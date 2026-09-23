import os
import mysql.connector
from mysql.connector import pooling
from dotenv import load_dotenv

load_dotenv()

DB_CONFIG = {
    "host": os.getenv("MYSQL_HOST", "localhost"),
    "port": int(os.getenv("MYSQL_PORT", "3306")),
    "user": os.getenv("MYSQL_USER", "root"),
    "password": os.getenv("MYSQL_PASSWORD", "shop_password"),
    "database": os.getenv("MYSQL_DATABASE", "shopdb"),
    "autocommit": True,
}

# Pool for concurrency
pool = None

def get_pool():
    global pool
    if pool is None:
        pool = pooling.MySQLConnectionPool(pool_name="shop_pool", pool_size=5, **DB_CONFIG)
    return pool

def get_conn():
    return get_pool().get_connection()

def query(sql, params=None, fetch="all", dictionary=True):
    conn = get_conn()
    try:
        cur = conn.cursor(dictionary=dictionary)
        cur.execute(sql, params or ())
        if fetch == "all":
            res = cur.fetchall()
        elif fetch == "one":
            res = cur.fetchone()
        else:
            res = None
            conn.commit()
        cur.close()
        return res
    finally:
        conn.close()

def execute(sql, params=None):
    conn = get_conn()
    try:
        cur = conn.cursor()
        cur.execute(sql, params or ())
        conn.commit()
        last_id = cur.lastrowid
        cur.close()
        return last_id
    finally:
        conn.close()

def duality_available() -> bool:
    """Check if server supports JSON DUALITY VIEW (>=9.1)."""
    try:
        row = query("SELECT VERSION() as v", fetch="one")
        ver = row["v"] if row else "0.0.0"
        major = int(ver.split(".")[0])
        minor = int(ver.split(".")[1]) if len(ver.split("."))>1 else 0
        return (major > 9) or (major == 9 and minor >= 1)
    except Exception:
        return False
