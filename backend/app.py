import os
import socket
from datetime import datetime, timezone
from flask import Flask, jsonify, request
from flask_cors import CORS
from flask_sqlalchemy import SQLAlchemy
from prometheus_flask_exporter import PrometheusMetrics

db = SQLAlchemy()

def create_app():
    app = Flask(__name__)
    app.config["SQLALCHEMY_DATABASE_URI"] = os.getenv(
        "DATABASE_URL",
        "postgresql+psycopg://app:app@db:5432/orders"
    )
    app.config["SQLALCHEMY_TRACK_MODIFICATIONS"] = False
    db.init_app(app)
    CORS(app)
    metrics = PrometheusMetrics(app, path="/metrics")
    metrics.info("order_api_info", "Order API information", version="1.0.0")

    class Order(db.Model):
        __tablename__ = "orders"
        id = db.Column(db.Integer, primary_key=True)
        customer = db.Column(db.String(120), nullable=False)
        product = db.Column(db.String(160), nullable=False)
        quantity = db.Column(db.Integer, nullable=False)
        status = db.Column(db.String(30), nullable=False, default="CREATED")
        created_at = db.Column(db.DateTime(timezone=True), default=lambda: datetime.now(timezone.utc))

        def as_dict(self):
            return {
                "id": self.id,
                "customer": self.customer,
                "product": self.product,
                "quantity": self.quantity,
                "status": self.status,
                "created_at": self.created_at.isoformat() if self.created_at else None,
            }

    @app.get("/api/health")
    def health():
        return jsonify({"status": "UP", "service": "order-api", "host": socket.gethostname()})

    @app.get("/api/ready")
    def ready():
        try:
            db.session.execute(db.text("SELECT 1"))
            return jsonify({"status": "READY", "database": "reachable"})
        except Exception as exc:
            app.logger.exception("Readiness check failed")
            return jsonify({"status": "NOT_READY", "error": str(exc)}), 503

    @app.get("/api/orders")
    def list_orders():
        orders = Order.query.order_by(Order.id.desc()).limit(100).all()
        return jsonify([o.as_dict() for o in orders])

    @app.post("/api/orders")
    def create_order():
        data = request.get_json(silent=True) or {}
        required = ["customer", "product", "quantity"]
        missing = [k for k in required if k not in data]
        if missing:
            return jsonify({"error": f"Missing fields: {', '.join(missing)}"}), 400
        try:
            quantity = int(data["quantity"])
            if quantity <= 0:
                raise ValueError
        except (TypeError, ValueError):
            return jsonify({"error": "quantity must be a positive integer"}), 400

        order = Order(
            customer=str(data["customer"]).strip(),
            product=str(data["product"]).strip(),
            quantity=quantity,
            status="CREATED",
        )
        if not order.customer or not order.product:
            return jsonify({"error": "customer and product cannot be empty"}), 400
        db.session.add(order)
        db.session.commit()
        app.logger.info("Created order id=%s customer=%s product=%s", order.id, order.customer, order.product)
        return jsonify(order.as_dict()), 201

    @app.patch("/api/orders/<int:order_id>/status")
    def update_status(order_id):
        data = request.get_json(silent=True) or {}
        status = str(data.get("status", "")).upper()
        allowed = {"CREATED", "PROCESSING", "SHIPPED", "CANCELLED"}
        if status not in allowed:
            return jsonify({"error": f"status must be one of {sorted(allowed)}"}), 400
        order = db.session.get(Order, order_id)
        if not order:
            return jsonify({"error": "order not found"}), 404
        order.status = status
        db.session.commit()
        app.logger.info("Updated order id=%s status=%s", order.id, status)
        return jsonify(order.as_dict())

    @app.get("/api/stats")
    def stats():
        rows = db.session.execute(
            db.text("SELECT status, COUNT(*) AS count FROM orders GROUP BY status ORDER BY status")
        ).mappings().all()
        return jsonify({r["status"]: r["count"] for r in rows})

    with app.app_context():
        db.create_all()

    return app

app = create_app()

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=int(os.getenv("PORT", "8080")))
