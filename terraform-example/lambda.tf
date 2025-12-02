# (c) 2025 JFrog Ltd.
# Lambda function for JFrog secret rotation
resource "aws_lambda_function" "jfrog_secret_rotator" {
  function_name = "${var.unique_id}-jfrog-secret-rotator-lambda"
  description    = "JFrog token rotation based on Lambda IAM role"

  package_type = "Image"
  image_uri    = var.ecr_image_uri

  role    = aws_iam_role.jfrog_secret_rotation_lambda.arn
  timeout = var.timeout
  memory_size = var.memory_size

  environment {
    variables = {
      JFROG_HOST = var.jfrog_host
      SECRET_TTL = var.secret_ttl
    }
  }

  tags = var.tags
}

# Permission for Secrets Manager to invoke the Lambda function
resource "aws_lambda_permission" "secrets_manager" {
  statement_id  = "secretsmanager-invoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.jfrog_secret_rotator.function_name
  principal     = "secretsmanager.amazonaws.com"
}

