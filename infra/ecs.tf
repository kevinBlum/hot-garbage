# ECS needs its service-linked role to exist before using FARGATE/FARGATE_SPOT
# capacity providers. This role is account-wide so it's created once here and
# subsequent applies are no-ops (Terraform state tracks it).
resource "aws_iam_service_linked_role" "ecs" {
  aws_service_name = "ecs.amazonaws.com"
}

resource "aws_ecs_cluster" "server" {
  name = local.name_prefix

  setting {
    name  = "containerInsights"
    value = "enabled"
  }

  tags = { Name = local.name_prefix }
}

resource "aws_ecs_cluster_capacity_providers" "server" {
  cluster_name = aws_ecs_cluster.server.name

  capacity_providers = ["FARGATE", "FARGATE_SPOT"]

  default_capacity_provider_strategy {
    base              = 1
    weight            = 1
    capacity_provider = var.use_fargate_spot ? "FARGATE_SPOT" : "FARGATE"
  }

  depends_on = [aws_iam_service_linked_role.ecs]
}

resource "aws_ecs_task_definition" "server" {
  family                   = local.name_prefix
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = var.task_cpu
  memory                   = var.task_memory
  execution_role_arn       = aws_iam_role.ecs_execution.arn
  task_role_arn            = aws_iam_role.ecs_task.arn

  container_definitions = jsonencode([{
    name  = "server"
    image = "${aws_ecr_repository.server.repository_url}:${var.image_tag}"

    portMappings = [{
      containerPort = 3000
      protocol      = "tcp"
    }]

    environment = [
      { name = "PORT", value = "3000" },
      { name = "DYNAMODB_REGION", value = data.aws_region.current.name },
      { name = "DYNAMODB_TABLE", value = aws_dynamodb_table.rooms.name },
    ]

    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.server.name
        "awslogs-region"        = data.aws_region.current.name
        "awslogs-stream-prefix" = "ecs"
      }
    }

    essential         = true
    memoryReservation = 384
  }])

  tags = { Name = local.name_prefix }
}

resource "aws_ecs_service" "server" {
  name            = local.name_prefix
  cluster         = aws_ecs_cluster.server.id
  task_definition = aws_ecs_task_definition.server.arn
  desired_count   = var.desired_count

  capacity_provider_strategy {
    capacity_provider = var.use_fargate_spot ? "FARGATE_SPOT" : "FARGATE"
    weight            = 1
    base              = 1
  }

  network_configuration {
    subnets         = local.public_subnet_ids
    security_groups = [aws_security_group.ecs_task.id]
    # Public IP required for outbound ECR pulls and DynamoDB calls without a NAT Gateway.
    # Inbound is controlled exclusively by ecs_task_sg (ALB origin only).
    assign_public_ip = true
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.server.arn
    container_name   = "server"
    container_port   = 3000
  }

  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  deployment_controller {
    type = "ECS"
  }

  # Allow ALB registration to complete before health checks start
  health_check_grace_period_seconds = 60

  depends_on = [aws_lb_listener.http]

  tags = { Name = local.name_prefix }
}
