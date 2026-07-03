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

    # Observability. Namespace/service/env become CloudWatch metric dimensions;
    # the compute task definition injects the same values so the app's emitted
    # metrics and the dashboard's references can't drift.
    metrics_namespace: str = os.environ.get("METRICS_NAMESPACE", "Skybound/GameApp")
    service_name: str = os.environ.get("SERVICE_NAME", "skybound-api")
    env_name: str = os.environ.get("ENV", "dev")
    metrics_enabled: bool = os.environ.get("METRICS_ENABLED", "true").lower() != "false"


settings = Settings()
