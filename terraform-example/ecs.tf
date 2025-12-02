# ------------------------------------------------------------------------------
# (c) 2025 JFrog Ltd.
# An example of how to deploy an ECS cluster, IAM role, security groups,
# load balancer, target group, listener, task definition, and service.
# task definition, and service.
# 
# Comment out the resources to actually apply them as part of the terraform apply.
# ------------------------------------------------------------------------------

# ECS Cluster
resource "aws_ecs_cluster" "main" {
  count = var.create_ecs ? 1 : 0
  name  = "${var.unique_id}-ecs-cluster"

  tags = var.tags
}

# IAM role for ECS tasks
resource "aws_iam_role" "ecs_task_execution" {
  count = var.create_ecs ? 1 : 0
  name = "${var.unique_id}-ecs-task-execution-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = var.tags
}

# IAM policy for ECS task execution role
resource "aws_iam_role_policy_attachment" "ecs_task_execution" {
  count      = var.create_ecs ? 1 : 0
  role       = aws_iam_role.ecs_task_execution[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# IAM policy for ECS task to access Secrets Manager
resource "aws_iam_role_policy" "ecs_task_secrets" {
  count = var.create_ecs ? 1 : 0
  name  = "${var.unique_id}-ecs-task-secrets-policy"
  role  = aws_iam_role.ecs_task_execution[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue"
        ]
        Resource = aws_secretsmanager_secret.jfrog_token.arn
      }
    ]
  })
}

# Security group for ECS tasks
resource "aws_security_group" "ecs_task" {
  count       = var.create_ecs ? 1 : 0
  name        = "${var.unique_id}-ecs-task-sg"
  description = "Security group for ECS tasks"
  vpc_id      = aws_vpc.main.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound traffic"
  }

  tags = var.tags
}

# Security group for load balancer
resource "aws_security_group" "alb" {
  count       = var.create_ecs ? 1 : 0
  name        = "${var.unique_id}-alb-sg"
  description = "Security group for Application Load Balancer"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = var.alb_allowed_cidr_blocks
    description = "Allow HTTP traffic from specified CIDR blocks"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound traffic"
  }

  tags = var.tags
}

# Allow traffic from ALB to ECS tasks
resource "aws_security_group_rule" "alb_to_ecs" {
  count                    = var.create_ecs ? 1 : 0
  type                     = "ingress"
  from_port                = 80
  to_port                  = 80
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.alb[0].id
  security_group_id        = aws_security_group.ecs_task[0].id
  description              = "Allow traffic from ALB to ECS tasks"
}

# Application Load Balancer
resource "aws_lb" "main" {
  count              = var.create_ecs ? 1 : 0
  name               = "${var.unique_id}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb[0].id]
  subnets            = aws_subnet.public[*].id

  enable_deletion_protection = false

  tags = var.tags
}

# Target group for ECS service
resource "aws_lb_target_group" "ecs" {
  count       = var.create_ecs ? 1 : 0
  name        = "${var.unique_id}-ecs-tg"
  port        = 80
  protocol    = "HTTP"
  vpc_id      = aws_vpc.main.id
  target_type = "ip"

  health_check {
    enabled             = true
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 5
    interval            = 30
    path                = "/"
    matcher             = "200"
  }

  tags = var.tags
}

# ALB listener
resource "aws_lb_listener" "main" {
  count             = var.create_ecs ? 1 : 0
  load_balancer_arn = aws_lb.main[0].arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.ecs[0].arn
  }
}

# CloudWatch Log Group for ECS tasks
resource "aws_cloudwatch_log_group" "ecs_task" {
  count             = var.create_ecs ? 1 : 0
  name              = "/ecs/${var.unique_id}-nginx"
  retention_in_days = 7

  tags = var.tags
}

# ECS Task Definition
# Note: For Docker registry authentication, the secret in Secrets Manager must contain
# JSON with "username" and "password" keys, e.g., {"username": "username", "password": "token"}
# The repositoryCredentials parameter references the secret ARN.
resource "aws_ecs_task_definition" "nginx" {
  count                    = var.create_ecs ? 1 : 0
  family                   = "${var.unique_id}-nginx"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "256" # millicores
  memory                   = "512" # MB
  execution_role_arn       = aws_iam_role.ecs_task_execution[0].arn

  container_definitions = jsonencode([
    {
      name  = "nginx"
      image = "${var.jfrog_host}/docker/nginx:latest"
      portMappings = [
        {
          containerPort = 80
          protocol      = "tcp"
        }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.ecs_task[0].name
          "awslogs-region"        = var.region
          "awslogs-stream-prefix" = "ecs"
        }
      }
      repositoryCredentials = {
        credentialsParameter = aws_secretsmanager_secret.jfrog_token.arn
      }
    }
  ])

  tags = var.tags
}

# ECS Service
resource "aws_ecs_service" "nginx" {
  count            = var.create_ecs ? 1 : 0
  name             = "${var.unique_id}-nginx-service"
  cluster          = aws_ecs_cluster.main[0].id
  task_definition  = aws_ecs_task_definition.nginx[0].arn
  desired_count    = 1
  launch_type      = "FARGATE"

  network_configuration {
    subnets          = aws_subnet.private[*].id
    security_groups  = [aws_security_group.ecs_task[0].id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.ecs[0].arn
    container_name   = "nginx"
    container_port   = 80
  }

  depends_on = [
    aws_lb_listener.main[0],
    null_resource.jfrog_iam_role_assignment
  ]

  tags = var.tags
}

