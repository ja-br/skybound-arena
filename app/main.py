"""Skybound Arena backend API: 8 endpoints (2 meta, 2 player, 2 matchmaking,
1 result, 1 leaderboard)."""

import logging
import time
import uuid
from datetime import datetime, timezone

from boto3.dynamodb.conditions import Key
from fastapi import FastAPI, HTTPException, Query, Request

from config import settings
from db import matches_table, players_table
from elo import updated_ratings
from logging_config import configure_logging
from matchmaking import matchmaker
from metrics import emit
from models import (
    CreatePlayer,
    LeaderboardEntry,
    MatchResult,
    Player,
    QueueRequest,
    ResultRequest,
    Ticket,
)

configure_logging()
_log = logging.getLogger("skybound.api")

app = FastAPI(title="Skybound Arena", version=settings.version)

STARTING_RATING = 1000

# Health/meta paths are excluded from metric emission: /healthz is hit by the
# ALB every 30s across two target groups, so metering it is pure noise + cost.
_UNMETERED_PATHS = {"/healthz", "/version"}


@app.middleware("http")
async def observe(request: Request, call_next):
    """Per-request access log + RequestCount / HttpErrorCount metrics."""
    request_id = request.headers.get("x-request-id") or uuid.uuid4().hex
    start = time.perf_counter()
    status = 500
    try:
        response = await call_next(request)
        status = response.status_code
        response.headers["x-request-id"] = request_id
        return response
    except Exception:
        # An unhandled error propagates *through* this middleware, so anything
        # after call_next only runs via `finally`. Count it as a 5xx, re-raise.
        status = 500
        raise
    finally:
        duration_ms = round((time.perf_counter() - start) * 1000, 2)
        if request.url.path not in _UNMETERED_PATHS:
            # Route TEMPLATE, never the raw path — a per-path-param dimension
            # (e.g. /players/{id}) would create one custom metric per value.
            # scope["route"] is set by the router (after call_next) and is
            # absent for a request that matched no route.
            route = request.scope.get("route")
            route_path = getattr(route, "path", None) or "unmatched"
            # RequestCount/HttpErrorCount aggregate at service/env so the
            # dashboard can derive a clean error rate; route + status class ride
            # along as log fields (not dimensions) to stay cardinality-safe.
            metrics = {"RequestCount": 1}
            units = {"RequestCount": "Count"}
            fields = {"route": route_path}
            if status >= 400:
                metrics["HttpErrorCount"] = 1
                units["HttpErrorCount"] = "Count"
                fields["status_class"] = f"{status // 100}xx"
            emit(metrics, units, fields=fields)
        _log.info(
            "request",
            extra={
                "request_id": request_id,
                "method": request.method,
                "path": request.url.path,
                "status": status,
                "duration_ms": duration_ms,
            },
        )


def _now() -> str:
    return datetime.now(timezone.utc).isoformat()


def _to_player(item: dict) -> Player:
    """DynamoDB returns numbers as Decimal; coerce to int for the API."""
    return Player(
        player_id=item["player_id"],
        username=item["username"],
        rating=int(item["rating"]),
        wins=int(item["wins"]),
        losses=int(item["losses"]),
        created_at=item["created_at"],
    )


def _load_player(player_id: str) -> dict:
    item = players_table().get_item(Key={"player_id": player_id}).get("Item")
    if not item:
        raise HTTPException(status_code=404, detail="player not found")
    return item


# ---------------------------------------------------------------------------
# Health & meta — /healthz for health checks, /version returns the build SHA.
# ---------------------------------------------------------------------------

@app.get("/healthz")
def healthz():
    return {"status": "ok"}


@app.get("/version")
def version():
    return {"version": settings.version}


# ---------------------------------------------------------------------------
# Players
# ---------------------------------------------------------------------------

@app.post("/players", response_model=Player, status_code=201)
def create_player(body: CreatePlayer):
    player_id = uuid.uuid4().hex
    item = {
        "player_id": player_id,
        "entity": "PLAYER",  # constant GSI PK -> leaderboard-index by rating
        "username": body.username,
        "rating": STARTING_RATING,
        "wins": 0,
        "losses": 0,
        "created_at": _now(),
    }
    players_table().put_item(Item=item)
    emit({"PlayersCreated": 1}, {"PlayersCreated": "Count"})
    _log.info("player_created", extra={"player_id": player_id})
    return _to_player(item)


@app.get("/players/{player_id}", response_model=Player)
def get_player(player_id: str):
    return _to_player(_load_player(player_id))


# ---------------------------------------------------------------------------
# Matchmaking (in-memory)
# ---------------------------------------------------------------------------

def _create_match(player_a: str, player_b: str) -> str:
    match_id = "mt_" + uuid.uuid4().hex
    matches_table().put_item(
        Item={
            "match_id": match_id,
            "player_a": player_a,
            "player_b": player_b,
            "status": "PENDING",
            "winner": None,
            "created_at": _now(),
        }
    )
    return match_id


@app.post("/matchmaking/queue", response_model=Ticket)
def join_queue(body: QueueRequest):
    _load_player(body.player_id)  # 404 if the player doesn't exist
    ticket = matchmaker.queue(body.player_id, _create_match)

    outcome = ticket["status"]  # QUEUED | MATCHED
    metrics = {"MatchmakingQueueDepth": matchmaker.depth()}
    units = {"MatchmakingQueueDepth": "Count"}
    if outcome == "MATCHED":
        metrics["MatchesMade"] = 1
        units["MatchesMade"] = "Count"
        if ticket.get("wait_ms") is not None:
            metrics["MatchmakingLatencyMs"] = ticket["wait_ms"]
            units["MatchmakingLatencyMs"] = "Milliseconds"
    emit(metrics, units)
    _log.info("matchmaking", extra={"player_id": body.player_id, "outcome": outcome})
    return Ticket(**ticket)


@app.get("/matchmaking/tickets/{ticket_id}", response_model=Ticket)
def get_ticket(ticket_id: str):
    ticket = matchmaker.get(ticket_id)
    if not ticket:
        raise HTTPException(status_code=404, detail="ticket not found")
    return Ticket(**ticket)


# ---------------------------------------------------------------------------
# Match results — the ELO update
# ---------------------------------------------------------------------------

@app.post("/matches/{match_id}/result", response_model=MatchResult)
def report_result(match_id: str, body: ResultRequest):
    match = matches_table().get_item(Key={"match_id": match_id}).get("Item")
    if not match:
        raise HTTPException(status_code=404, detail="match not found")
    if match["status"] == "COMPLETE":
        raise HTTPException(status_code=409, detail="match already complete")

    player_a, player_b = match["player_a"], match["player_b"]
    if body.winner not in (player_a, player_b):
        raise HTTPException(status_code=400, detail="winner is not in this match")

    a = _load_player(player_a)
    b = _load_player(player_b)
    a_won = body.winner == player_a

    new_a, new_b = updated_ratings(int(a["rating"]), int(b["rating"]), a_won)
    _apply_result(player_a, new_a, won=a_won)
    _apply_result(player_b, new_b, won=not a_won)

    matches_table().update_item(
        Key={"match_id": match_id},
        UpdateExpression="SET #s = :complete, winner = :w",
        ExpressionAttributeNames={"#s": "status"},
        ExpressionAttributeValues={":complete": "COMPLETE", ":w": body.winner},
    )

    emit({"MatchCompleted": 1}, {"MatchCompleted": "Count"})
    _log.info("match_completed", extra={"match_id": match_id, "player_id": body.winner})
    return MatchResult(
        match_id=match_id,
        status="COMPLETE",
        ratings={player_a: new_a, player_b: new_b},
    )


def _apply_result(player_id: str, new_rating: int, won: bool) -> None:
    field = "wins" if won else "losses"
    players_table().update_item(
        Key={"player_id": player_id},
        UpdateExpression=f"SET rating = :r ADD {field} :one",
        ExpressionAttributeValues={":r": new_rating, ":one": 1},
    )


# ---------------------------------------------------------------------------
# Leaderboard — top-N by rating via the GSI
# ---------------------------------------------------------------------------

@app.get("/leaderboard", response_model=list[LeaderboardEntry])
def leaderboard(limit: int = Query(default=10, ge=1, le=100)):
    start = time.perf_counter()
    resp = players_table().query(
        IndexName="leaderboard-index",
        KeyConditionExpression=Key("entity").eq("PLAYER"),
        ScanIndexForward=False,  # highest rating first
        Limit=limit,
    )
    emit(
        {"LeaderboardQueryMs": round((time.perf_counter() - start) * 1000, 2)},
        {"LeaderboardQueryMs": "Milliseconds"},
    )
    return [
        LeaderboardEntry(username=i["username"], rating=int(i["rating"]))
        for i in resp.get("Items", [])
    ]
