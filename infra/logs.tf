resource "aws_cloudwatch_log_group" "server" {
  name              = "/hot-garbage/${local.env}/server"
  retention_in_days = 30

  tags = {
    Name = "/hot-garbage/${local.env}/server"
  }
}
