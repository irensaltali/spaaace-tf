# Spaaace Infrastructure Makefile

.PHONY: help init plan apply destroy deploy-game deploy-website validate fmt

ENV ?= dev
AWS_REGION ?= eu-west-1

help: ## Show this help
	@echo "Spaaace Infrastructure Commands:"
	@echo ""
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-20s\033[0m %s\n", $$1, $$2}'

init: ## Initialize Terraform
	cd envs/$(ENV) && terraform init

validate: ## Validate Terraform configuration
	cd envs/$(ENV) && terraform validate

fmt: ## Format Terraform files
	terraform fmt -recursive

plan: ## Run Terraform plan
	cd envs/$(ENV) && terraform plan

apply: ## Apply Terraform configuration
	cd envs/$(ENV) && terraform apply

destroy: ## Destroy Terraform infrastructure (USE WITH CAUTION)
	cd envs/$(ENV) && terraform destroy

output: ## Show Terraform outputs
	cd envs/$(ENV) && terraform output

#------------------------------------------------------------------------------
# Game Server Deployment
#------------------------------------------------------------------------------

deploy-game: ## Build and deploy game server Docker image
	@echo "Building game server Docker image..."
	cd ../spaaace && docker build -t spaaace-game:latest .
	
	@echo "Getting ECR login token..."
	aws ecr get-login-password --region $(AWS_REGION) | docker login --username AWS --password-stdin $$(cd spaaace-tf/envs/$(ENV) && terraform output -raw ecr_repository_url)
	
	@echo "Tagging and pushing image..."
	cd ../spaaace && docker tag spaaace-game:latest $$(cd ../spaaace-tf/envs/$(ENV) && terraform output -raw ecr_repository_url):latest
	cd ../spaaace && docker push $$(cd ../spaaace-tf/envs/$(ENV) && terraform output -raw ecr_repository_url):latest
	
	@echo "Updating ECS service..."
	aws ecs update-service \
		--cluster $$(cd envs/$(ENV) && terraform output -raw ecs_cluster_name) \
		--service $$(cd envs/$(ENV) && terraform output -raw ecs_service_name) \
		--force-new-deployment
	
	@echo "Game server deployed successfully!"

#------------------------------------------------------------------------------
# Website Deployment
#------------------------------------------------------------------------------

deploy-website: ## Deploy website to S3/CloudFront
	@echo "Deploying website to S3..."
	aws s3 sync ../spaaace/dist/ s3://$$(cd envs/$(ENV) && terraform output -raw website_bucket_name)/ --delete
	
	@echo "Invalidating CloudFront cache..."
	aws cloudfront create-invalidation \
		--distribution-id $$(cd envs/$(ENV) && terraform output -raw cloudfront_distribution_id) \
		--paths "/*"
	
	@echo "Website deployed successfully!"

#------------------------------------------------------------------------------
# Logs & Debugging
#------------------------------------------------------------------------------

logs: ## View game server logs
	aws logs tail /ecs/spaaace-$(ENV)-game --follow --region $(AWS_REGION)

tasks: ## List ECS tasks
	aws ecs list-tasks --cluster spaaace-$(ENV) --region $(AWS_REGION)

services: ## List ECS services
	aws ecs describe-services \
		--cluster spaaace-$(ENV) \
		--services spaaace-$(ENV)-game \
		--region $(AWS_REGION)

#------------------------------------------------------------------------------
# Full Deployment
#------------------------------------------------------------------------------

deploy-all: deploy-game deploy-website ## Deploy both game server and website

#------------------------------------------------------------------------------
# Setup
#------------------------------------------------------------------------------

setup-ecr: ## Authenticate Docker with ECR
	aws ecr get-login-password --region $(AWS_REGION) | docker login --username AWS --password-stdin $$(cd spaaace-tf/envs/$(ENV) && terraform output -raw ecr_repository_url)
