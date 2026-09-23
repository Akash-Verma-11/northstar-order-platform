import os
os.environ["DATABASE_URL"] = "sqlite:///:memory:"
from app import create_app

def test_health():
    app = create_app()
    client = app.test_client()
    response = client.get("/api/health")
    assert response.status_code == 200
    assert response.json["status"] == "UP"

def test_create_and_list_order():
    app = create_app()
    client = app.test_client()
    created = client.post("/api/orders", json={
        "customer": "Demo User", "product": "Laptop", "quantity": 2
    })
    assert created.status_code == 201
    listed = client.get("/api/orders")
    assert listed.status_code == 200
    assert listed.json[0]["product"] == "Laptop"
