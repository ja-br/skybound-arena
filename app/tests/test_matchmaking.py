"""Matchmaker wait-time + depth. In-memory only, no AWS."""

import time

from matchmaking import Matchmaker


def _factory(player_a: str, player_b: str) -> str:
    return "mt_test"


def test_match_reports_opponent_wait_not_zero():
    mm = Matchmaker()

    first = mm.queue("p1", _factory)
    assert first["status"] == "QUEUED"
    assert first["wait_ms"] is None
    assert mm.depth() == 1

    time.sleep(0.01)
    second = mm.queue("p2", _factory)
    assert second["status"] == "MATCHED"
    assert second["match_id"] == "mt_test"
    # The wait belongs to p1 (parked ~10ms), not the just-arrived p2 (~0ms).
    assert second["wait_ms"] >= 5
    assert mm.depth() == 0


def test_same_player_does_not_self_match():
    mm = Matchmaker()
    mm.queue("p1", _factory)
    again = mm.queue("p1", _factory)
    # The stale self-match ticket is dropped; the new one parks in its place.
    assert again["status"] == "QUEUED"
    assert mm.depth() == 1
