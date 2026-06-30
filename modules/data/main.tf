# Data module: DynamoDB tables from the API spec
# PAY_PER_REQUEST scales like a game backend should

resource "aws_dynamodb_table" "players" {
  name         = "${var.env}-Players"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "player_id"

  attribute {
    name = "player_id"
    type = "S"
  }

  # GSI partition key: constant "PLAYER" so the whole leaderboard is one partition queryable by rating
  attribute {
    name = "entity"
    type = "S"
  }

  attribute {
    name = "rating"
    type = "N"
  }

  global_secondary_index {
    name = "leaderboard-index"

    key_schema {
      attribute_name = "entity"
      key_type       = "HASH"
    }
    key_schema {
      attribute_name = "rating"
      key_type       = "RANGE"
    }

    projection_type = "ALL"
  }

  # DR posture: point-in-time recovery.
  point_in_time_recovery {
    enabled = var.pitr_enabled
  }

  tags = { Name = "${var.env}-Players", Project = "skybound" }
}

resource "aws_dynamodb_table" "matches" {
  name         = "${var.env}-Matches"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "match_id"

  attribute {
    name = "match_id"
    type = "S"
  }

  point_in_time_recovery {
    enabled = var.pitr_enabled
  }

  tags = { Name = "${var.env}-Matches", Project = "skybound" }
}
