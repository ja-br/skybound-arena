"""DynamoDB access. The resource is created lazily so importing the app (e.g.
in unit tests) never opens a connection or needs credentials."""

import boto3

from config import settings

_resource = None


def _dynamodb():
    global _resource
    if _resource is None:
        kwargs = {"region_name": settings.aws_region}
        if settings.dynamodb_endpoint:
            # DynamoDB Local for docker-compose; dummy creds keep boto3 happy.
            kwargs.update(
                endpoint_url=settings.dynamodb_endpoint,
                aws_access_key_id="local",
                aws_secret_access_key="local",
            )
        _resource = boto3.resource("dynamodb", **kwargs)
    return _resource


def players_table():
    return _dynamodb().Table(settings.players_table)


def matches_table():
    return _dynamodb().Table(settings.matches_table)
