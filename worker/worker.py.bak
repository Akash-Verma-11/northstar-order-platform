import os, time, logging
import psycopg

logging.basicConfig(level=os.getenv("LOG_LEVEL", "INFO"), format="%(asctime)s %(levelname)s %(message)s")
DB = os.getenv("DATABASE_URL", "postgresql://app:app@db:5432/orders")

def process():
    with psycopg.connect(DB) as conn:
        with conn.cursor() as cur:
            cur.execute("SELECT id, customer, product FROM orders WHERE status='CREATED' ORDER BY id LIMIT 10")
            rows = cur.fetchall()
            for order_id, customer, product in rows:
                logging.info("processing order id=%s customer=%s product=%s", order_id, customer, product)
                cur.execute("UPDATE orders SET status='PROCESSING' WHERE id=%s", (order_id,))
        conn.commit()

if __name__ == "__main__":
    logging.info("order-worker started")
    while True:
        try:
            process()
        except Exception:
            logging.exception("worker processing failure")
        time.sleep(int(os.getenv("POLL_SECONDS", "10")))
