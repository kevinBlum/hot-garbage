#!/bin/bash
# Run once to create the DynamoDB table in AWS
set -e

aws dynamodb create-table \
  --table-name hot-garbage-rooms \
  --attribute-definitions AttributeName=roomName,AttributeType=S \
  --key-schema AttributeName=roomName,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  --region us-east-1
