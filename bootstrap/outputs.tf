output "state_bucket" {
  description = "Put this in each environments/*/backend.tf as `bucket`. Locking is S3-native (use_lockfile), so there's no lock-table output."
  value       = aws_s3_bucket.tfstate.id
}
