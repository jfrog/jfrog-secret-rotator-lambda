# (c) 2025 JFrog Ltd.
# AWS Secrets Manager secret for JFrog token
resource "aws_secretsmanager_secret" "jfrog_token" {
  name        = "${var.unique_id}-jfrog-token"
  description = "JFrog Artifactory access token for ${var.unique_id}"

  recovery_window_in_days = 0

  tags = var.tags
}

# Initial secret value
resource "aws_secretsmanager_secret_version" "jfrog_token_initial" {
  secret_id     = aws_secretsmanager_secret.jfrog_token.id
  secret_string = var.secret_initial_value
}

# Configure rotation for the secret
resource "aws_secretsmanager_secret_rotation" "jfrog_token" {
  secret_id           = aws_secretsmanager_secret.jfrog_token.id
  rotation_lambda_arn = aws_lambda_function.jfrog_secret_rotator.arn

  # Trigger the first rotation on setup instead of waiting for the schedule
  rotate_immediately = var.trigger_initial_rotation

  rotation_rules {
    automatically_after_days = null
    duration                 = var.rotation_duration
    schedule_expression      = var.rotation_schedule_expression
  }

  depends_on = [
    aws_secretsmanager_secret_version.jfrog_token_initial,
    aws_lambda_permission.secrets_manager
  ]
}

# Assign the Lambda IAM role to a specific JFrog user for passwordless access.
# Requires Artifactory 7.90.10 or later.
resource "platform_aws_iam_role" "jfrog_iam_role_assignment" {
  count = var.assign_jfrog_iam_role ? 1 : 0

  username = var.jfrog_admin_username
  iam_role = aws_iam_role.jfrog_secret_rotation_lambda.arn

  depends_on = [
    aws_iam_role.jfrog_secret_rotation_lambda,
    aws_secretsmanager_secret_rotation.jfrog_token
  ]
}
