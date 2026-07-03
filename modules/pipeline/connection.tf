# CodeConnections GitHub connection — how the Source stages pull the repo with
# no stored token. Terraform creates it in PENDING state; a human completes the
# OAuth handshake once in the console (Developer Tools > Connections > Update
# pending connection), after which every pipeline run authenticates through the
# connection ARN. The ARN is not a secret.
resource "aws_codestarconnections_connection" "github" {
  name          = "${local.name}-github"
  provider_type = "GitHub"
}
