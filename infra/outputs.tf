output "alb_dns_name" {
  description = "ALB DNS name — update network_manager.gd SERVER_URL to ws://<value> after first deploy"
  value       = aws_lb.server.dns_name
}

output "ecr_repository_url" {
  description = "ECR repository URL for Docker image pushes"
  value       = aws_ecr_repository.server.repository_url
}

output "ecs_cluster_name" {
  description = "ECS cluster name"
  value       = aws_ecs_cluster.server.name
}

output "ecs_service_name" {
  description = "ECS service name"
  value       = aws_ecs_service.server.name
}

output "dynamodb_table_name" {
  description = "DynamoDB rooms table name"
  value       = aws_dynamodb_table.rooms.name
}
