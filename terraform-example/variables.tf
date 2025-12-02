# (c) 2025 JFrog Ltd.
variable "unique_id" {
  description = "Unique ID for the resources used as a prefix for the resource names"
  type        = string
  default     = "demo"
}

variable "ecr_image_uri" {
  description = "ECR image URI for the Lambda container image"
  type        = string
}

variable "jfrog_host" {
  description = "JFrog Artifactory hostname"
  type        = string
}

variable "secret_ttl" {
  description = "Token expiration time in seconds"
  type        = string
  default     = "21000"
}

variable "exclude_characters" {
  description = "Characters to exclude from generated passwords"
  type        = string
  default     = "/@\"'\\"
}

variable "region" {
  description = "AWS region"
  type        = string
  default     = "eu-central-1"
}

variable "timeout" {
  description = "Lambda function timeout in seconds"
  type        = number
  default     = 300
}

variable "memory_size" {
  description = "Lambda function memory size in MB"
  type        = number
  default     = 512
}

variable "secret_initial_value" {
  description = "Initial secret value (JSON string with token)"
  type        = string
  default     = "{\"username\":\"dummy-user\",\"password\":\"dummy-password\"}"
  sensitive   = true
}

variable "rotation_schedule_expression" {
  description = "Schedule expression for secret rotation (e.g., rate(4 hours))"
  type        = string
  default     = "rate(4 hours)"
}

variable "rotation_duration" {
  description = "Duration for rotation window (e.g., 4h)"
  type        = string
  default     = "4h"
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default     = {}
}

variable "jfrog_admin_username" {
  description = "JFrog username to assign IAM role to"
  type        = string
}

# This is the JFrog admin token for API authentication.
# Not to confused with the token used in the secret for the ECS task or the lambda function.
# For demo purposes, you can use the same admin token.
variable "jfrog_admin_token" {
  description = "JFrog admin token for API authentication"
  type        = string
  sensitive   = true
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "create_ecs" {
  description = "Whether to create ECS resources"
  type        = bool
  default     = false
}

variable "alb_allowed_cidr_blocks" {
  description = "List of CIDR blocks allowed to access the ALB"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

