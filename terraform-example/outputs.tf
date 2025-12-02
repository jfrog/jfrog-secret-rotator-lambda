# (c) 2025 JFrog Ltd.
# Secret outputs
output "secret_name" {
  description = "Name of the AWS Secrets Manager secret"
  value       = aws_secretsmanager_secret.jfrog_token.name
}

output "secret_arn" {
  description = "ARN of the AWS Secrets Manager secret"
  value       = aws_secretsmanager_secret.jfrog_token.arn
}

# Lambda function outputs
output "function_name" {
  description = "Name of the Lambda function"
  value       = aws_lambda_function.jfrog_secret_rotator.function_name
}

output "function_arn" {
  description = "ARN of the Lambda function"
  value       = aws_lambda_function.jfrog_secret_rotator.arn
}

# IAM role ARN for JFrog API command
output "iam_role_arn" {
  description = "ARN of the IAM role for Lambda execution"
  value       = aws_iam_role.jfrog_secret_rotation_lambda.arn
}

# JFrog IAM role assignment status
output "jfrog_iam_role_assigned" {
  description = "Status of JFrog IAM role assignment (executed automatically during terraform apply)"
  value       = "IAM role ${aws_iam_role.jfrog_secret_rotation_lambda.arn} assigned to JFrog user ${var.jfrog_admin_username}"
}

# VPC outputs
output "vpc_id" {
  description = "ID of the VPC"
  value       = aws_vpc.main.id
}

# ECS outputs
output "ecs_cluster_name" {
  description = "Name of the ECS cluster"
  value       = var.create_ecs ? aws_ecs_cluster.main[0].name : "N/A"
}

output "ecs_service_name" {
  description = "Name of the ECS service"
  value       = var.create_ecs ? aws_ecs_service.nginx[0].name : "N/A"
}

output "alb_dns_name" {
  description = "DNS name of the Application Load Balancer"
  value       = var.create_ecs ? aws_lb.main[0].dns_name : "N/A"
}

output "nginx_endpoint" {
  description = "Endpoint URL to test the nginx service"
  value       = var.create_ecs ? "http://${aws_lb.main[0].dns_name}" : "N/A"
}
