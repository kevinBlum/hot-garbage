resource "aws_dynamodb_table" "rooms" {
  name         = "hot-garbage-rooms-${local.env}"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "roomName"

  attribute {
    name = "roomName"
    type = "S"
  }

  tags = {
    Name = "hot-garbage-rooms-${local.env}"
  }
}
