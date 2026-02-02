#!/bin/bash
# ECS Container Instance User Data

# Set cluster name
echo ECS_CLUSTER=${cluster_name} >> /etc/ecs/ecs.config

# Optional: Enable CloudWatch logging for ECS agent
echo ECS_AVAILABLE_LOGGING_DRIVERS=[\"json-file\",\"awslogs\"] >> /etc/ecs/ecs.config

# Start ECS agent
systemctl enable --now ecs

# Install CloudWatch agent for better monitoring (optional)
yum update -y
yum install -y amazon-cloudwatch-agent

# Signal success to CloudFormation/Auto Scaling (optional)
# /opt/aws/bin/cfn-signal -e $? ...
