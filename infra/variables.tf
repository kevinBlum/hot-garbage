variable "image_tag" {
  description = "Docker image tag to deploy (Git SHA)"
  type        = string
  default     = "latest"
}

variable "desired_count" {
  description = "Number of running ECS task instances"
  type        = number
  default     = 1
}

variable "task_cpu" {
  description = "Fargate task CPU units (256 = 0.25 vCPU)"
  type        = number
  default     = 256
}

variable "task_memory" {
  description = "Fargate task memory in MB"
  type        = number
  default     = 512
}

variable "use_fargate_spot" {
  description = "Use FARGATE_SPOT capacity provider (~70% cost reduction for fault-tolerant workloads)"
  type        = bool
  default     = false
}
