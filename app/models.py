"""Request/response schemas."""

from pydantic import BaseModel, Field


# ---- requests ----

class CreatePlayer(BaseModel):
    username: str = Field(min_length=1, max_length=32)


class QueueRequest(BaseModel):
    player_id: str


class ResultRequest(BaseModel):
    winner: str  # player_id of the winner


# ---- responses ----

class Player(BaseModel):
    player_id: str
    username: str
    rating: int
    wins: int
    losses: int
    created_at: str


class Ticket(BaseModel):
    ticket_id: str
    status: str  # QUEUED | MATCHED
    match_id: str | None = None


class MatchResult(BaseModel):
    match_id: str
    status: str  # COMPLETE
    ratings: dict[str, int]


class LeaderboardEntry(BaseModel):
    username: str
    rating: int
