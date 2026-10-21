import os
import time
import logging
import psycopg

logging.basicConfig(
    level=os.getenv("LOG_LEVEL", "INFO"),
    format="%(asctime)s %(levelname)s %(message)s"
)

DB = os.getenv(
    "DATABASE_URL",
    "postgresql://app:app@db:5432/orders"
)


def process():
    # Claim orders atomically in a single PostgreSQL transaction.
    with psycopg.connect(DB) as conn:
        with conn.cursor() as cur:
            cur.execute("""
                WITH claimed AS (
                    SELECT id
                    FROM orders
                    WHERE status = 'CREATED'
                    ORDER BY id
                    LIMIT 10
                    FOR UPDATE SKIP LOCKED
                )
                UPDATE orders AS o
                SET status = 'PROCESSING'
                FROM claimed
                WHERE o.id = claimed.id
                RETURNING o.id, o.customer, o.product
            """)

            rows = cur.fetchall()

        # Commit the claim before logging success.
        conn.commit()

    for order_id, customer, product in rows:
        logging.info(
            "claimed order id=%s customer=%s product=%s",
            order_id,
            customer,
            product
        )

    if rows:
        logging.info(
            "successfully claimed %s orders",
            len(rows)
        )


if __name__ == "__main__":
    logging.info("order-worker started")

    while True:
        try:
            process()
        except Exception:
            logging.exception("worker processing failure")

        time.sleep(int(os.getenv("POLL_SECONDS", "10")))