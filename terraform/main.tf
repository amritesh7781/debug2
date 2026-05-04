# ============================================================
# Terraform Configuration — AWS Academy Compatible
# NO IAM role creation — uses pre-existing LabRole
# ============================================================

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
  required_version = ">= 1.5"

  backend "s3" {
    # Values supplied at init time via -backend-config flags:
    # -backend-config="bucket=<TF_STATE_BUCKET>"
    # -backend-config="key=shopsmart/terraform.tfstate"
    # -backend-config="region=<AWS_REGION>"
    # -backend-config="encrypt=true"
    # Falls back to local state in AWS Academy environments
  }
}

provider "aws" {
  region = var.aws_region
}

# Auto-fetch current AWS Account ID (no hardcoding needed)
data "aws_caller_identity" "current" {}

# ──────────────────────────────────────────
# ECR Repositories
# ──────────────────────────────────────────

resource "aws_ecr_repository" "backend" {
  name         = var.ecr_backend_repo_name
  force_delete = true # Allows deleting even if images exist

  image_scanning_configuration {
    scan_on_push = true
  }

  image_tag_mutability = "MUTABLE"

  tags = {
    Name        = var.ecr_backend_repo_name
    Environment = "lab"
  }
}

resource "aws_ecr_repository" "frontend" {
  name         = var.ecr_frontend_repo_name
  force_delete = true

  image_scanning_configuration {
    scan_on_push = true
  }

  image_tag_mutability = "MUTABLE"

  tags = {
    Name        = var.ecr_frontend_repo_name
    Environment = "lab"
  }
}

# ──────────────────────────────────────────
# ECR Lifecycle Policies (keep only last 5 images)
# ──────────────────────────────────────────

resource "aws_ecr_lifecycle_policy" "backend_policy" {
  repository = aws_ecr_repository.backend.name

  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep only last 5 images"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = 5
      }
      action = { type = "expire" }
    }]
  })
}

resource "aws_ecr_lifecycle_policy" "frontend_policy" {
  repository = aws_ecr_repository.frontend.name

  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep only last 5 images"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = 5
      }
      action = { type = "expire" }
    }]
  })
}

# ──────────────────────────────────────────
# ECS Cluster
# ──────────────────────────────────────────

resource "aws_ecs_cluster" "main" {
  name = var.ecs_cluster_name

  setting {
    name  = "containerInsights"
    value = "disabled" # Disabled for AWS Academy
  }

  tags = {
    Name        = var.ecs_cluster_name
    Environment = "lab"
  }
}

# ──────────────────────────────────────────
# ECS Task Definitions
# Uses AWS Academy's pre-existing LabRole (no IAM creation)
# ──────────────────────────────────────────

resource "aws_ecs_task_definition" "backend" {
  family                   = "shopsmart-backend"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = var.backend_cpu
  memory                   = var.backend_memory

  # ← AWS Academy LabRole (already exists, do NOT create it)
  execution_role_arn = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/LabRole"
  task_role_arn      = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/LabRole"

  container_definitions = jsonencode([
    {
      name      = "backend"
      image     = "${aws_ecr_repository.backend.repository_url}:${var.image_tag}"
      essential = true
      portMappings = [
        {
          containerPort = var.backend_port
          protocol      = "tcp"
        }
      ]
      environment = [
        for key, value in var.backend_env_vars : {
          name  = key
          value = value
        }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = "/ecs/shopsmart-backend"
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "ecs"
          "awslogs-create-group"  = "true"
        }
      }
    }
  ])

  tags = {
    Name = "shopsmart-backend-task"
  }
}

resource "aws_ecs_task_definition" "frontend" {
  family                   = "shopsmart-frontend"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = var.frontend_cpu
  memory                   = var.frontend_memory

  execution_role_arn = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/LabRole"
  task_role_arn      = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/LabRole"

  container_definitions = jsonencode([
    {
      name      = "frontend"
      image     = "${aws_ecr_repository.frontend.repository_url}:${var.image_tag}"
      essential = true
      portMappings = [
        {
          containerPort = var.frontend_port
          protocol      = "tcp"
        }
      ]
      environment = [
        for key, value in var.frontend_env_vars : {
          name  = key
          value = value
        }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = "/ecs/shopsmart-frontend"
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "ecs"
          "awslogs-create-group"  = "true"
        }
      }
    }
  ])

  tags = {
    Name = "shopsmart-frontend-task"
  }
}

# ──────────────────────────────────────────
# ECS Services
# ──────────────────────────────────────────

resource "aws_ecs_service" "backend" {
  name            = "shopsmart-backend-service"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.backend.arn
  desired_count   = var.service_desired_count
  launch_type     = "FARGATE"

  # Force redeployment on every apply (picks up new Docker image)
  force_new_deployment = true

  deployment_minimum_healthy_percent = 50
  deployment_maximum_percent         = 200

  network_configuration {
    subnets          = var.subnet_ids
    security_groups  = [var.security_group_id]
    assign_public_ip = true
  }

  tags = {
    Name        = "shopsmart-backend-service"
    Environment = "lab"
  }
}

resource "aws_ecs_service" "frontend" {
  name            = "shopsmart-frontend-service"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.frontend.arn
  desired_count   = var.service_desired_count
  launch_type     = "FARGATE"

  force_new_deployment = true

  deployment_minimum_healthy_percent = 50
  deployment_maximum_percent         = 200

  network_configuration {
    subnets          = var.subnet_ids
    security_groups  = [var.security_group_id]
    assign_public_ip = true
  }

  tags = {
    Name        = "shopsmart-frontend-service"
    Environment = "lab"
  }
}

# ──────────────────────────────────────────
# Outputs
# ──────────────────────────────────────────

output "ecr_backend_url" {
  description = "ECR repository URL for backend"
  value       = aws_ecr_repository.backend.repository_url
}

output "ecr_frontend_url" {
  description = "ECR repository URL for frontend"
  value       = aws_ecr_repository.frontend.repository_url
}

output "ecs_cluster_name" {
  description = "ECS cluster name"
  value       = aws_ecs_cluster.main.name
}

output "ecs_cluster_arn" {
  description = "ECS cluster ARN"
  value       = aws_ecs_cluster.main.arn
}

output "backend_service_name" {
  description = "Backend ECS service name"
  value       = aws_ecs_service.backend.name
}

output "frontend_service_name" {
  description = "Frontend ECS service name"
  value       = aws_ecs_service.frontend.name
}
