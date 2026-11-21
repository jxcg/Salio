from fastapi.testclient import TestClient

from main import app


def test_feed_orders_available_places_and_drops_them_after_deadline():
    with TestClient(app) as client:
        default = client.get("/v1/sample-feed")
        at_deadline = client.get("/v1/sample-feed", params={"at": "2030-01-01T18:11:00Z"})
        after_deadline = client.get("/v1/sample-feed", params={"at": "2030-01-01T18:11:01Z"})
        after_last_deadline = client.get("/v1/sample-feed", params={"at": "2030-01-01T19:20:01Z"})

    assert default.status_code == at_deadline.status_code == after_deadline.status_code == 200
    assert default.json() == at_deadline.json()
    assert [(row["id"], row["leave_by"]) for row in at_deadline.json()] == [
        ("cinema", "2030-01-01T18:11:00Z"),
        ("gallery", "2030-01-01T19:20:00Z"),
    ]
    assert [row["id"] for row in after_deadline.json()] == ["gallery"]
    assert after_last_deadline.status_code == 200
    assert after_last_deadline.json() == []
