#!/bin/bash
# ECS Container Instance User Data

# Install updates first. Restarting Docker after ECS starts can leave ecs.service inactive.
yum update -y
yum install -y amazon-cloudwatch-agent

# Set cluster name
echo ECS_CLUSTER=${cluster_name} >> /etc/ecs/ecs.config

# Optional: Enable CloudWatch logging for ECS agent
echo ECS_AVAILABLE_LOGGING_DRIVERS=[\"json-file\",\"awslogs\"] >> /etc/ecs/ecs.config

# Start ECS agent
systemctl enable --now ecs

# Ensure ECS agent is running after package updates and service restarts
systemctl restart ecs

# Signal success to CloudFormation/Auto Scaling (optional)
# /opt/aws/bin/cfn-signal -e $? ...
