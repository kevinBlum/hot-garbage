#!/bin/bash
set -e
ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
REGION=us-east-1
REPO=$ACCOUNT.dkr.ecr.$REGION.amazonaws.com/hot-garbage-server

aws ecr get-login-password --region $REGION | docker login --username AWS --password-stdin $REPO
docker build -t hot-garbage-server -f hot-garbage-server/Dockerfile .
docker tag hot-garbage-server:latest $REPO:latest
docker push $REPO:latest
echo "Pushed to $REPO:latest"
