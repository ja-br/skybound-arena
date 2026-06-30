"""Smoke test for /healthz and /version. Neither touches DynamoDB, so this
runs with no AWS access."""

import os

os.environ["VERSION"] = "test-sha-123"

from fastapi.testclient import TestClient  # noqa: E402

from main import app  # noqa: E402

client = TestClient(app)


def test_healthz_ok():
    resp = client.get("/healthz")
    assert resp.status_code == 200
    assert resp.json() == {"status": "ok"}


def test_version_reflects_injected_build():
    resp = client.get("/version")
    assert resp.status_code == 200
    assert resp.json() == {"version": "test-sha-123"}
