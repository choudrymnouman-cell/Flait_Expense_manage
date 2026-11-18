import os
from fastapi import FastAPI
from fastapi.responses import JSONResponse
import psycopg

app = FastAPI(title="Expense Manage API", version="0.1.0", docs_url=None, redoc_url=None)

@app.get("/health")
def health():
    try:
        with psycopg.connect(os.environ["DATABASE_URL"], connect_timeout=3) as conn:
            with conn.cursor() as cursor:
                cursor.execute("SELECT 1")
                cursor.fetchone()
        return {"status": "ok", "database": "connected"}
    except Exception:
        return JSONResponse(status_code=503, content={"status": "unavailable"})
