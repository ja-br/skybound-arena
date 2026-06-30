"""In-memory matchmaking. One waiting slot, paired FIFO, state held in-process."""

import threading
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
        ticket = {"ticket_id": ticket_id, "status": "QUEUED",
                  "match_id": None, "player_id": player_id}

        with self._lock:
            self._tickets[ticket_id] = ticket

            opponent = self._next_waiting(exclude_player=player_id)
            if opponent is None:
                self._waiting.append(ticket_id)
                return dict(ticket)

            match_id = create_match(opponent["player_id"], player_id)
            for t in (opponent, ticket):
                t["status"] = "MATCHED"
                t["match_id"] = match_id
            return dict(ticket)

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
