output "players_table_name" {
  description = "Players table name (app reads via env var)."
  value       = aws_dynamodb_table.players.name
}

output "players_table_arn" {
  description = "Players table ARN (for the app task IAM policy)."
  value       = aws_dynamodb_table.players.arn
}

output "matches_table_name" {
  description = "Matches table name."
  value       = aws_dynamodb_table.matches.name
}

output "matches_table_arn" {
  description = "Matches table ARN (for the app task IAM policy)."
  value       = aws_dynamodb_table.matches.arn
}

output "leaderboard_index_name" {
  description = "GSI name for top-N leaderboard queries."
  value       = "leaderboard-index"
}
