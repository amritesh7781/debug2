# Input variable declarations for the ShopSmart Terraform configuration
# All environment-specific values should be defined here

variable "aws_region" {
  type        = string
  default     = "us-east-1"
  description = "AWS region where resources will be provisioned"
}

variable "ecr_backend_repo_name" {
  type        = string
  default     = "shopsmart-backend"
  description = "Name of the ECR repository for the backend Docker image"
}

variable "ecr_frontend_repo_name" {
  type        = string
  default     = "shopsmart-frontend"
  description = "Name of the ECR repository for the frontend Docker image"
}

variable "ecs_cluster_name" {
  type        = string
  default     = "shopsmart-cluster"
  description = "Name of the ECS cluster"
}

variable "service_desired_count" {
  type        = number
  default     = 1
  description = "Desired number of running tasks for each ECS service"
}

variable "backend_cpu" {
  type        = number
  default     = 256
  description = "CPU units for the backend container (1024 = 1 vCPU)"
}

variable "backend_memory" {
  type        = number
  default     = 512
  description = "Memory (MiB) for the backend container"
}

variable "frontend_cpu" {
  type        = number
  default     = 256
  description = "CPU units for the frontend container (1024 = 1 vCPU)"
}

variable "frontend_memory" {
  type        = number
  default     = 512
  description = "Memory (MiB) for the frontend container"
}

variable "backend_port" {
  type        = number
  default     = 5001
  description = "Port number exposed by the backend container"
}

variable "frontend_port" {
  type        = number
  default     = 80
  description = "Port number exposed by the frontend container"
}

variable "image_tag" {
  type        = string
  description = "Docker image tag (Git SHA) — required at plan time"
}

variable "backend_env_vars" {
  type        = map(string)
  default     = {}
  description = "Environment variables to inject into the backend container"
}

variable "frontend_env_vars" {
  type        = map(string)
  default     = {}
  description = "Environment variables to inject into the frontend container"
}
