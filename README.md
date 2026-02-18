# Spaaace Infrastructure

Production-grade, high-availability AWS infrastructure for the Spaaace multiplayer game using Terraform.

## Architecture Overview

This infrastructure implements a **High Availability Architecture** that ensures the game continues even when:
- A container/node crashes
- An EC2 instance fails  
- An entire Availability Zone goes down

```
                                    Internet
                                       |
                                   Route53
                                       |
                 ┌─────────────────────┴─────────────────────┐
                 |                                           |
           CloudFront ────> S3 (Game Website)              ALB (WebSockets)
                 |                                           |
                 |                                 ┌────────┴────────┐
                 |                                 |                 |
                 |                              ECS Cluster      Redis (ElastiCache)
                 |                                 |             (Game State)
                 |                          EC2 Nodes (ASG)           |
                 |                                 |                 |
                 |                        Game Server (Node.js) <────┘
                 |                        (Hydrates from Redis)
                 |
```

## Key Features

### 🎯 High Availability (The "Game Continues" Architecture)

| Failure Scenario | What Happens | Result |
|-----------------|--------------|--------|
| **Node Down** (container crash) | ECS restarts container, Redis hydrates state | Game resumes in 2-3 seconds |
| **EC2 Down** (instance failure) | ASG replaces instance, ECS reschedules tasks | Game resumes from Redis |
| **AZ Down** (datacenter outage) | ALB routes to healthy AZs, Redis replica promotes | Game continues seamlessly |

### 🔧 Core Components

1. **ECS Cluster (3 AZs)** - Auto-scaling EC2 nodes across availability zones
2. **ElastiCache Redis (Multi-AZ)** - Game state persistence for crash recovery
3. **ALB with Stickiness** - WebSocket-ready load balancer with session affinity
4. **Capacity Provider** - Seamless scaling and instance management

## CI/CD Architecture

This repository works together with the [`spaaace`](https://github.com/irensaltali/spaaace) repository for continuous deployment across **staging** and **production** environments:

```
spaaace repo                      spaaace-tf repo (this repo)
     │                                   │
     │  Push to develop                  │
     │ ────────────────────────────────> │  1. Build Docker image
     │                                   │  2. Push to ECR (eu-west-1)
     │  Push to master/main              │  3. Trigger staging deployment
     │ ────────────────────────────────> │
     │                                   │  4. Build Docker image
     │                                   │  5. Push to ECR (eu-north-1)
     │                                   │  6. Trigger prod deployment
     │                                   │
     │                                   ▼
     │                         ┌─────────────────┐
     │                         │  Staging Env    │  eu-west-1
     │                         │  staging.***    │
     │                         ├─────────────────┤
     │                         │  Production Env │  eu-north-1
     │                         │  spaaace.online │
     │                         └─────────────────┘
```

| Environment | Branch | Region | Domain |
|-------------|--------|--------|--------|
| **Staging** | `develop` | eu-west-1 | staging.spaaace.online |
| **Production** | `master`/`main` | eu-north-1 | spaaace.online |

See [DEPLOYMENT.md](../spaaace/DEPLOYMENT.md) in the spaaace repo for details.

## Quick Start

### Prerequisites

- AWS CLI configured with credentials
- Terraform >= 1.5.0
- Docker (optional, for manual builds)

### 1. Initialize Terraform

```bash
cd envs/staging
terraform init
```

### 2. Review the plan

```bash
terraform plan
```

### 3. Apply infrastructure

```bash
terraform apply
```

### 4. Deploy via GitHub Actions (Recommended)

The CI/CD pipeline is configured across two repositories:

**Option A: Automatic Deployment (on push to main)**

1. Push code to `spaaace` repo `main` branch
2. GitHub Actions builds and pushes Docker image to ECR
3. GitHub Actions automatically triggers deployment in `spaaace-tf`
4. ECS service is updated with the new image

**Option B: Manual Deployment**

```bash
# Get the ECR login token
aws ecr get-login-password --region eu-west-1 | docker login --username AWS --password-stdin $(terraform output -raw ecr_repository_url)

# Build and push the image
cd ../../spaaace
docker build -t spaaace-game .
docker tag spaaace-game:latest $(terraform output -raw ecr_repository_url):latest
docker push $(terraform output -raw ecr_repository_url):latest

# Trigger deployment via GitHub Actions
# Go to spaaace-tf repo → Actions → "Deploy Game" → Run workflow

# Or update the ECS service manually:
aws ecs update-service --cluster $(terraform output -raw ecs_cluster_name) --service $(terraform output -raw ecs_service_name) --force-new-deployment
```

### 5. Deploy the website

```bash
# Sync the dist folder to S3
aws s3 sync ../../spaaace/dist/ s3://$(terraform output -raw website_bucket_name)/ --delete

# Invalidate CloudFront cache
aws cloudfront create-invalidation --distribution-id $(terraform output -raw cloudfront_distribution_id) --paths "/*"
```

## Project Structure

```
spaaace-tf/
├── modules/
│   ├── vpc/           # VPC with 3 AZs, public/private subnets
│   ├── ecs-cluster/   # ECS cluster with EC2 nodes (Multi-AZ)
│   ├── ecs-service/   # ECS service and task definitions
│   ├── alb/           # ALB with WebSocket stickiness
│   ├── ecr/           # Container Registry
│   ├── elasticache/   # Redis Multi-AZ for game state
│   ├── s3-website/    # S3 + CloudFront for static site
│   └── route53/       # DNS management
├── envs/
│   ├── staging/       # Staging environment
│   ├── prod/          # Production environment
│   └── bootstrap/     # Bootstrap environment (ECR and shared resources)
└── README.md
```

## Module Details

### VPC Module
- **3 AZs** for high availability
- Public and private subnets across all AZs
- NAT Gateway for outbound traffic from private subnets
- VPC Flow Logs (optional)

### ECS Cluster Module
- EC2-backed (not Fargate) for WebSocket stability
- Auto Scaling Group with Multi-AZ distribution
- Capacity Provider for proper scaling
- Spans 3 availability zones

### ALB Module
- WebSocket-ready with 120s idle timeout
- **Session stickiness enabled** (critical for WebSockets)
- Health checks on `/health` endpoint
- Cross-zone load balancing

### ElastiCache (Redis) Module ⭐
- **Multi-AZ enabled** with automatic failover
- 2 nodes (primary + replica) across different AZs
- AOF persistence for data durability
- Game state survives node crashes

### ECS Service Module
- Auto-scaling based on CPU/Memory
- Circuit breaker with rollback
- CloudWatch logs and alarms
- Redis connection environment variables

### S3 Website Module
- Static website hosting
- CloudFront CDN with OAC (Origin Access Control)
- SPA support (index.html for all routes)

### Route53 Module
- DNS records for game and website
- ACM certificate integration
- Health checks

## High Availability Architecture

### How It Works

```
Normal Operation:
  Player -> ALB -> Node A (AZ 1) [Reads/Writes State to Redis]

Node A Crashes:
  Player Disconnects 
       |
       v
  Client Auto-Reconnecting...
       |
       v
  ALB detects Node A is dead
       |
       v
  Routes to Node B (AZ 2)
       |
       v
  Node B fetches Game State from Redis
       |
       v
  GAME RESUMES
```

### Redis State Management

The game server must implement:

1. **State Serialization**: Periodically save game state to Redis
   ```javascript
   // Key: game_room_{roomId}
   // Value: { snapshot: ..., timestamp: ... }
   ```

2. **Hydration on Startup**: Restore state from Redis when container starts
   ```javascript
   // Pseudo-code
   async onRoomStart(roomId) {
       const savedState = await redis.get(`game_room_${roomId}`);
       if (savedState) {
           this.gameEngine.applySnapshot(savedState);
       }
   }
   ```

See [ARCHITECTURE.md](ARCHITECTURE.md) for detailed implementation guide.

## Environments

### Staging Environment
- **3 AZs** for HA testing (`eu-west-1a`, `eu-west-1b`, `eu-west-1c`)
- Cost-optimized (t3.small, single NAT gateway)
- HTTP only (no SSL certificate)
- Auto-scaling disabled
- Redis with 3-day snapshot retention

### Production Environment (Future)
- 3 AZs with multiple NAT gateways
- HTTPS with ACM certificates
- Auto-scaling enabled
- Redis with encryption and longer retention
- WAF protection

## Terraform Cloud Setup

1. Create organization at https://app.terraform.io
2. Create workspace `spaaace-staging`
3. Configure AWS credentials as environment variables:
   - `AWS_ACCESS_KEY_ID`
   - `AWS_SECRET_ACCESS_KEY`
   - `AWS_DEFAULT_REGION`
4. Update `envs/staging/main.tf` to use Terraform Cloud backend

## Domain Setup

1. Register domain `spaaace.online` in Route53 or transfer existing
2. Configure Route53 settings in `envs/staging/main.tf` (or `envs/prod/main.tf`)
3. Request ACM certificate for the domain
4. Update ALB to use HTTPS
5. Run `terraform apply`

## Monitoring

- CloudWatch Logs for ECS containers
- CloudWatch Metrics for ALB, ECS, and Redis
- CloudWatch Alarms (optional)
- Redis CloudWatch metrics for cache performance

## Cost Estimation (Staging)

| Resource | Monthly Cost |
|----------|-------------|
| t3.small EC2 (1x) | ~$15 |
| ALB | ~$16 |
| NAT Gateway | ~$35 |
| ElastiCache (t4g.micro) | ~$12 |
| Data Transfer | ~$5 |
| CloudFront | ~$5 |
| S3 | ~$1 |
| **Total** | **~$89/month** |

Use spot instances to save ~60% on EC2 costs.

## Troubleshooting

### ECS tasks not starting
Check CloudWatch logs:
```bash
aws logs tail /ecs/spaaace-staging-game --follow
```

### WebSocket connections dropping
- ALB idle timeout is set to 120s (configurable)
- Session stickiness is enabled (required for WebSockets)

### Container health check failing
Ensure the game server implements a `/health` endpoint returning 200 OK

### Redis connection issues
Check security groups allow traffic from ECS to Redis on port 6379

### Game state not persisting
Verify game server code implements Redis serialization/hydration

## Security Notes

- ECS tasks run on private subnets (no direct internet access)
- ALB is in public subnets
- Redis is in private subnets, accessible only from ECS security group
- S3 bucket is private, accessed via CloudFront OAC
- Security groups are minimal and specific

## Implementation Checklist for Game Developers

- [ ] Implement `/health` endpoint in game server
- [ ] Add Redis client library (ioredis or redis)
- [ ] Implement `serialize()` method to save game state
- [ ] Implement state hydration on server startup
- [ ] Configure socket.io-redis adapter (if scaling to multiple nodes)
- [ ] Test crash recovery: kill container, verify game resumes
