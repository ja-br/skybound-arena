"""In-memory matchmaking. One waiting slot, paired FIFO, state held in-process."""

import threading
import time
import uuid
from collections import deque
from typing import Callable

# create_match(player_a, player_b) -> match_id
MatchFactory = Callable[[str, str], str]


class Matchmaker:
    def __init__(self) -> None:
        self._lock = threading.Lock()
        self._waiting: deque[str] = deque()  # ticket_ids waiting for an opponent
        self._tickets: dict[str, dict] = {}

    def queue(self, player_id: str, create_match: MatchFactory) -> dict:
        """Join the queue. If someone is already waiting (a different player),
        pair them immediately and return MATCHED with a match_id; otherwise
        park this ticket as QUEUED."""
        ticket_id = "tkt_" + uuid.uuid4().hex
        # wait_ms is filled in on a MATCH; it reports the *opponent's* wait (see
        # below). None while QUEUED and for the just-arrived matcher.
        ticket = {"ticket_id": ticket_id, "status": "QUEUED",
                  "match_id": None, "player_id": player_id, "wait_ms": None}

        with self._lock:
            self._tickets[ticket_id] = ticket

            opponent = self._next_waiting(exclude_player=player_id)
            if opponent is None:
                ticket["enqueued_at"] = time.monotonic()
                self._waiting.append(ticket_id)
                return dict(ticket)

            # The meaningful wait belongs to the opponent who was already parked;
            # this ticket is matched on arrival, so measure now - their enqueue.
            wait_ms = (time.monotonic() - opponent.get("enqueued_at", time.monotonic())) * 1000
            match_id = create_match(opponent["player_id"], player_id)
            for t in (opponent, ticket):
                t["status"] = "MATCHED"
                t["match_id"] = match_id
                t["wait_ms"] = wait_ms
            return dict(ticket)

    def depth(self) -> int:
        """Number of tickets currently parked waiting for an opponent."""
        with self._lock:
            return len(self._waiting)

    def get(self, ticket_id: str) -> dict | None:
        with self._lock:
            ticket = self._tickets.get(ticket_id)
            return dict(ticket) if ticket else None

    def _next_waiting(self, exclude_player: str) -> dict | None:
        """Pop the oldest waiting ticket that isn't this same player. Skips and
        drops stale self-matches. Caller holds the lock."""
        while self._waiting:
            candidate_id = self._waiting.popleft()
            candidate = self._tickets.get(candidate_id)
            if candidate and candidate["player_id"] != exclude_player:
                return candidate
        return None


matchmaker = Matchmaker()
