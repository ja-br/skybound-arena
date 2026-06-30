"""Runtime configuration, read entirely from environment variables."""

import os


class Settings:
    # DynamoDB table names, defaulting to the dev tables.
    players_table: str = os.environ.get("PLAYERS_TABLE", "dev-Players")
    matches_table: str = os.environ.get("MATCHES_TABLE", "dev-Matches")

    aws_region: str = os.environ.get("AWS_REGION", "us-east-1")

    # Build SHA baked in via Dockerfile ARG -> ENV, surfaced at /version.
    version: str = os.environ.get("VERSION", "dev")

    # Set to http://dynamodb-local:8000 for local docker-compose runs; unset in AWS.
    dynamodb_endpoint: str | None = os.environ.get("DYNAMODB_ENDPOINT_URL") or None


settings = Settings()
