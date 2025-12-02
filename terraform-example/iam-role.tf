# (c) 2025 JFrog Ltd.
# Data source to get the current AWS account ID
data "aws_caller_identity" "current" {}

# Data source to get the current AWS region
data "aws_region" "current" {}

# IAM role for Lambda execution
resource "aws_iam_role" "jfrog_secret_rotation_lambda" {
  name        = "${var.unique_id}-jfrog-secret-rotation-lambda-role"
  description = "IAM role for JFrog secret rotation Lambda function"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

# Inline policy for the Lambda role
resource "aws_iam_role_policy" "jfrog_secret_rotation_policy" {
  name = "${var.unique_id}-jfrog-secret-rotation-policy"
  role = aws_iam_role.jfrog_secret_rotation_lambda.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:DescribeSecret",
          "secretsmanager:UpdateSecretVersionStage"
        ]
        Resource = "arn:aws:secretsmanager:*:${data.aws_caller_identity.current.account_id}:secret:*"
      },
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:PutSecretValue"
        ]
        Resource = aws_secretsmanager_secret.jfrog_token.arn
      },
      {
        Effect = "Allow"
        Action = [
          "lambda:GetFunctionConfiguration"
        ]
        Resource = "arn:aws:lambda:*:*:function:*"
      },
      {
        Effect = "Allow"
        Action = [
          "sts:GetCallerIdentity",
          "sts:AssumeRole"
        ]
        Resource = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/${aws_iam_role.jfrog_secret_rotation_lambda.name}"
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:*:*:*"
      }
    ]
  })
}

