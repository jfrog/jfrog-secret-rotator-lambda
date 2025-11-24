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

# Execute JFrog API call to assign IAM role to a specific JFrog user
# This must run before ECS resources are created
resource "null_resource" "jfrog_iam_role_assignment" {

  provisioner "local-exec" {
    command = <<-EOT
      echo "##################################################################"
      echo "Assigning IAM role to JFrog user ${var.jfrog_admin_username}"
      echo "##################################################################"
      curl --fail -XPUT "https://${var.jfrog_host}/access/api/v1/aws/iam_role" \
           -H "Content-type: application/json" \
           -H "Authorization: Bearer ${var.jfrog_admin_token}" \
           -d '{"username": "${var.jfrog_admin_username}", "iam_role": "${aws_iam_role.jfrog_secret_rotation_lambda.arn}"}'
    EOT
  }

  depends_on = [
    aws_iam_role.jfrog_secret_rotation_lambda,
    aws_secretsmanager_secret_rotation.jfrog_token
  ]
}
