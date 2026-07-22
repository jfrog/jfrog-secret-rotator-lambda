# (c) 2026 JFrog Ltd.
# Package the Lambda source as a zip (boto3 is provided by the Python Lambda runtime)
data "archive_file" "lambda_package" {
  type        = "zip"
  source_file = "${path.module}/../secret-rotator/lambda_function.py"
  output_path = "${path.module}/build/jfrog-secret-rotator-lambda.zip"
}

# Lambda function for JFrog secret rotation
resource "aws_lambda_function" "jfrog_secret_rotator" {
  function_name = "${var.unique_id}-jfrog-secret-rotator-lambda"
  description   = "JFrog token rotation based on Lambda IAM role"

  filename         = data.archive_file.lambda_package.output_path
  source_code_hash = data.archive_file.lambda_package.output_base64sha256
  runtime          = "python3.14"
  handler          = "lambda_function.lambda_handler"

  role        = aws_iam_role.jfrog_secret_rotation_lambda.arn
  timeout     = var.timeout
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
