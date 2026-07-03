output "github_connection_arn" {
  description = "CodeConnections connection ARN. Starts PENDING — activate it once in the console (Developer Tools > Connections) before the first run."
  value       = aws_codestarconnections_connection.github.arn
}

output "artifact_bucket" {
  description = "S3 bucket CodePipeline stages pass artifacts through."
  value       = aws_s3_bucket.artifacts.bucket
}

output "infra_pipeline_name" {
  description = "Name of the Terraform (infra) pipeline."
  value       = aws_codepipeline.infra.name
}

output "app_pipeline_name" {
  description = "Name of the app build + blue/green deploy pipeline."
  value       = aws_codepipeline.app.name
}
