"""Create the Players/Matches tables in DynamoDB Local for local dev.

Players + leaderboard-index GSI, and Matches. Idempotent: skips tables that
already exist.
"""

import boto3
from botocore.exceptions import ClientError

from config import settings


def _client():
    return boto3.client(
        "dynamodb",
        region_name=settings.aws_region,
        endpoint_url=settings.dynamodb_endpoint,
        aws_access_key_id="local",
        aws_secret_access_key="local",
    )


def _create(client, **kwargs) -> None:
    name = kwargs["TableName"]
    try:
        client.create_table(BillingMode="PAY_PER_REQUEST", **kwargs)
        client.get_waiter("table_exists").wait(TableName=name)
        print(f"created {name}")
    except ClientError as e:
        if e.response["Error"]["Code"] == "ResourceInUseException":
            print(f"{name} already exists, skipping")
        else:
            raise


def main() -> None:
    client = _client()

    _create(
        client,
        TableName=settings.players_table,
        AttributeDefinitions=[
            {"AttributeName": "player_id", "AttributeType": "S"},
            {"AttributeName": "entity", "AttributeType": "S"},
            {"AttributeName": "rating", "AttributeType": "N"},
        ],
        KeySchema=[{"AttributeName": "player_id", "KeyType": "HASH"}],
        GlobalSecondaryIndexes=[
            {
                "IndexName": "leaderboard-index",
                "KeySchema": [
                    {"AttributeName": "entity", "KeyType": "HASH"},
                    {"AttributeName": "rating", "KeyType": "RANGE"},
                ],
                "Projection": {"ProjectionType": "ALL"},
            }
        ],
    )

    _create(
        client,
        TableName=settings.matches_table,
        AttributeDefinitions=[{"AttributeName": "match_id", "AttributeType": "S"}],
        KeySchema=[{"AttributeName": "match_id", "KeyType": "HASH"}],
    )


if __name__ == "__main__":
    main()
