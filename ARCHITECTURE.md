# Spaaace High Availability Architecture

## Overview

This document describes the high availability architecture for the Spaaace multiplayer game on AWS. The primary goal is to ensure the **game continues** even when infrastructure components fail.

## The Core Principle

> **ECS ensures your Server Software stays online.**
> **Redis ensures your Game State stays alive.**

When a node crashes, players **will** be momentarily disconnected. The "High Availability" goal is to ensure that when they automatically reconnect (seconds later), the game **resumes exactly where it left off** rather than resetting.

---

## Architecture Components

### 1. VPC (3 Availability Zones)

```
┌─────────────────────────────────────────────────────────────────┐
│                           VPC                                   │
│                     10.0.0.0/16                                 │
│  ┌──────────────┬──────────────┬──────────────┐                 │
│  │   AZ 1a      │   AZ 1b      │   AZ 1c      │                 │
│  │              │              │              │                 │
│  │ ┌──────────┐ │ ┌──────────┐ │ ┌──────────┐ │                 │
│  │ │ Public   │ │ │ Public   │ │ │ Public   │ │  <- ALB         │
│  │ │ 10.0.1/24│ │ │ 10.0.2/24│ │ │ 10.0.3/24│ │                 │
│  │ └────┬─────┘ │ └────┬─────┘ │ └────┬─────┘ │                 │
│  │      │       │      │       │      │       │                 │
│  │ ┌────┴─────┐ │ ┌────┴─────┐ │ ┌────┴─────┐ │                 │
│  │ │ Private  │ │ │ Private  │ │ │ Private  │ │  <- ECS/Redis   │
│  │ │10.0.11/24│ │ │10.0.12/24│ │ │10.0.13/24│ │                 │
│  │ └──────────┘ │ └──────────┘ │ └──────────┘ │                 │
│  └──────────────┴──────────────┴──────────────┘                 │
└─────────────────────────────────────────────────────────────────┘
```

**Why 3 AZs?**
- AWS recommends 3 AZs for true high availability
- If one AZ fails, you still have 2 AZs serving traffic
- Spreads risk across independent data centers

### 2. ECS Cluster with Capacity Provider

```
┌─────────────────────────────────────┐
│         ECS Cluster                 │
│                                     │
│  ┌─────────┐ ┌─────────┐ ┌────────┐ │
│  │ Node A  │ │ Node B  │ │ Node C │ │  EC2 Instances
│  │ (AZ 1a) │ │ (AZ 1b) │ │ (AZ 1c)│ │  (Auto Scaling Group)
│  └────┬────┘ └────┬────┘ └───┬────┘ │
│       │           │          │       │
│       └───────────┴──────────┘       │
│              Capacity Provider       │
│           (Managed Scaling)          │
└─────────────────────────────────────┘
```

**Features:**
- EC2-backed (not Fargate) for WebSocket stability
- Auto Scaling Group spans 3 AZs
- Capacity Provider for seamless scaling
- Instance refresh for zero-downtime updates

### 3. Application Load Balancer (ALB)

```
                    ┌─────────────┐
       ┌───────────>│   ALB       │
       │            │ (WebSocket  │
       │            │  Ready)     │
       │            └──────┬──────┘
       │                   │
       │    ┌──────────────┼──────────────┐
       │    │              │              │
   Sticky   │              │              │
  Sessions  ▼              ▼              ▼
       ┌────────┐    ┌────────┐    ┌────────┐
       │ Node A │    │ Node B │    │ Node C │
       │ (AZ 1a)│    │ (AZ 1b)│    │ (AZ 1c)│
       └────────┘    └────────┘    └────────┘
```

**Key Configuration:**
- **Session Stickiness**: Enabled (lb_cookie, 24 hours)
  - Critical for WebSocket connections
  - Ensures player stays connected to same server
- **Idle Timeout**: 120 seconds (long-lived WebSocket connections)
- **Health Checks**: `/health` endpoint
- **Cross-Zone Load Balancing**: Enabled

### 4. ElastiCache Redis (Multi-AZ)

```
┌─────────────────────────────────────────────┐
│        ElastiCache Redis Cluster            │
│                                             │
│   ┌─────────────┐      ┌─────────────┐      │
│   │   Primary   │<────>│   Replica   │      │
│   │  (AZ 1a)    │  Sync│  (AZ 1b)    │      │
│   │             │      │             │      │
│   │ Game State  │      │ Standby     │      │
│   │ (Active)    │      │ (Passive)   │      │
│   └──────┬──────┘      └─────────────┘      │
│          │                                  │
│          │ Writes & Reads                   │
│          ▼                                  │
│   ┌─────────────┐                           │
│   │   Game      │                           │
│   │   Servers   │                           │
│   └─────────────┘                           │
└─────────────────────────────────────────────┘
```

**Configuration:**
- **Multi-AZ**: Enabled (automatic failover)
- **Automatic Failover**: Enabled
- **Nodes**: 2 (primary + replica)
- **Persistence**: AOF (Append Only File) with `appendfsync everysec`
- **Snapshots**: Daily backups

---

## Failure Scenarios

### Scenario 1: Node (Container) Crash

```
BEFORE:                         AFTER:
┌────────┐                      ┌────────┐
│ Node A │──CRASH──>            │ Node A'│ (New Container)
│  [RAM] │                      │  [RAM] │
│  [===] │                      │  [   ] │
└───┬────┘                      └───┬────┘
    │                               │
    │  Game State?                  │  Redis?
    │  LOST!                        │  Fetch State
    ▼                               ▼
┌────────┐                      ┌────────┐
│ Player │   Disconnect         │ Player │   Reconnect
│Playing │ ───────────────────> │Resume │
└────────┘   2-3 seconds        └────────┘
```

**What Happens:**
1. ECS detects unhealthy task
2. New container starts immediately
3. New container checks Redis for active game sessions
4. If found, hydrates game state from Redis
5. Player auto-reconnects and game resumes

**Recovery Time**: 2-3 seconds

### Scenario 2: EC2 Instance Failure

```
BEFORE:                         AFTER:
                                 
┌────────┐                      ┌────────┐
│ Node A │──FAILS──>            │ Node B │ (Existing)
│(EC2 +  │                      │(EC2 in │
│Docker) │                      │AZ 1b)  │
└────────┘                      └───┬────┘
                                    │
ASG detects failure ────────────────┤
                                    │
┌────────┐    New EC2 launches      │
│ Node A'│<─────────────────────────┤
│(AZ 1a) │                          │
└────────┘                          │
    │                               │
    └───────────────────────────────┘
              Both serve traffic
```

**What Happens:**
1. ASG detects EC2 instance failure via health checks
2. ASG launches replacement EC2 instance
3. ECS schedules tasks onto healthy instances (including new one)
4. New tasks hydrate state from Redis
5. Player reconnects to healthy node

**Recovery Time**: 30-60 seconds (EC2 boot time + container startup)

### Scenario 3: AZ Outage

```
BEFORE (All 3 AZs):            AFTER (AZ 1a DOWN):

┌─────────┬─────────┬────────┐     ┌─────────┬────────┐
│  AZ 1a  │  AZ 1b  │  AZ 1c │     │  AZ 1b  │  AZ 1c │
│         │         │        │     │         │        │
│┌───────┐│┌───────┐│┌──────┐│     │┌───────┐│┌──────┐│
││ Node A│││ Node B│││Node C││     ││ Node B│││Node C││
││ Redis │││ Redis │││      ││     ││ Redis │││      ││
││Primary│││Replica│││      ││     ││PRIMARY│││      ││
││ FAILS │││       │││      ││     ││(Promo)│││      ││
│└───────┘│└───────┘│└──────┘│     │└───────┘│└──────┘│
└─────────┴─────────┴────────┘     └─────────┴────────┘
                                          ▲
                                          │
                                    ALB routes here
```

**What Happens:**
1. ALB stops routing to failed AZ (health checks fail)
2. Traffic routes to healthy AZs (1b, 1c)
3. ElastiCache promotes replica to primary (automatic)
4. Game state preserved in promoted Redis
5. Player reconnects to healthy node, state restored

**Recovery Time**: 1-2 minutes (Redis failover + reconnect)

---

## Implementation Guide for Game Server

### Required Code Changes

Your lance-gg game server must implement Redis integration:

#### 1. Add Dependencies

```javascript
// package.json
{
  "dependencies": {
    "redis": "^4.6.0",
    "@socket.io/redis-adapter": "^8.2.0"
  }
}
```

#### 2. Initialize Redis Connection

```javascript
// server.js or main.js
import { createClient } from 'redis';

const redisClient = createClient({
  url: process.env.REDIS_URL || 'redis://localhost:6379'
});

await redisClient.connect();
```

#### 3. Implement Health Check Endpoint

```javascript
// Health check for ALB and container
app.get('/health', (req, res) => {
  // Check Redis connection
  if (redisClient.isReady) {
    res.status(200).json({ status: 'healthy', redis: 'connected' });
  } else {
    res.status(503).json({ status: 'unhealthy', redis: 'disconnected' });
  }
});
```

#### 4. Serialize Game State to Redis

```javascript
// In your ServerEngine or GameEngine
class SpaaaceServerEngine extends ServerEngine {
  
  start() {
    super.start();
    
    // Save state every 5 seconds
    setInterval(() => this.saveGameState(), 5000);
    
    // Save on critical events
    this.gameEngine.on('playerJoined', () => this.saveGameState());
    this.gameEngine.on('playerLeft', () => this.saveGameState());
    this.gameEngine.on('missileHit', () => this.saveGameState());
  }
  
  async saveGameState() {
    const roomId = this.getRoomId(); // Your room identifier
    const snapshot = this.gameEngine.serialize();
    
    const state = {
      snapshot: snapshot,
      timestamp: Date.now(),
      scoreData: this.scoreData,
      players: this.getPlayerList()
    };
    
    await redisClient.set(
      `game_room_${roomId}`,
      JSON.stringify(state),
      { EX: 3600 } // Expire after 1 hour
    );
  }
}
```

#### 5. Hydrate State on Startup

```javascript
class SpaaaceServerEngine extends ServerEngine {
  
  async start() {
    // Try to restore existing game state
    await this.hydrateGameState();
    
    super.start();
  }
  
  async hydrateGameState() {
    const roomId = this.getRoomId();
    const savedState = await redisClient.get(`game_room_${roomId}`);
    
    if (savedState) {
      const state = JSON.parse(savedState);
      
      // Restore game world
      this.gameEngine.applySnapshot(state.snapshot);
      
      // Restore score data
      this.scoreData = state.scoreData;
      
      console.log(`[HYDRATION] Restored game state from ${new Date(state.timestamp)}`);
      return true;
    } else {
      console.log('[HYDRATION] No saved state found, starting fresh game');
      return false;
    }
  }
}
```

#### 6. Socket.io Redis Adapter (For Multi-Node Scaling)

```javascript
import { createAdapter } from '@socket.io/redis-adapter';

// If running multiple nodes, enable Redis adapter
// This allows nodes to communicate via Redis pub/sub
const pubClient = redisClient.duplicate();
const subClient = redisClient.duplicate();

io.adapter(createAdapter(pubClient, subClient));
```

---

## Environment Variables

The ECS service is configured with these environment variables:

| Variable | Description | Example |
|----------|-------------|---------|
| `REDIS_URL` | Redis connection string | `redis://spaaace-dev-redis.xxx.cache.amazonaws.com:6379` |
| `REDIS_ENABLED` | Enable Redis features | `true` |
| `GAME_HYDRATION_ENABLED` | Enable state hydration | `true` |
| `PORT` | Server port | `3000` |
| `NODE_ENV` | Environment | `production` |

---

## Testing Failover

### Test 1: Container Crash

```bash
# Find a running task
TASK_ARN=$(aws ecs list-tasks --cluster spaaace-dev --service spaaace-dev-game \
  --query 'taskArns[0]' --output text)

# Stop the task (simulates crash)
aws ecs stop-task --cluster spaaace-dev --task $TASK_ARN --reason "Chaos testing"

# Verify: New task starts, game state restored from Redis
```

### Test 2: Instance Termination

```bash
# Find an EC2 instance in the ASG
INSTANCE_ID=$(aws autoscaling describe-auto-scaling-groups \
  --auto-scaling-group-names spaaace-dev-ecs \
  --query 'AutoScalingGroups[0].Instances[0].InstanceId' --output text)

# Terminate it
aws ec2 terminate-instances --instance-ids $INSTANCE_ID

# Verify: ASG launches new instance, ECS tasks redistribute
```

### Test 3: AZ Failure Simulation

```bash
# Use AWS Fault Injection Simulator or manually:
# 1. Update ASG to use only 2 AZs
# 2. Stop all instances in one AZ
# 3. Verify: ALB routes to remaining AZs, Redis promotes replica
```

---

## Cost Optimization

### Development (Current Setup)

| Component | Instance | Monthly Cost |
|-----------|----------|-------------|
| ECS Nodes | t3.small (1x) | ~$15 |
| Redis | cache.t4g.micro | ~$12 |
| ALB | - | ~$16 |
| NAT Gateway | 1x | ~$35 |
| **Total** | | **~$78/month** |

### Production Recommendations

| Component | Instance | Monthly Cost |
|-----------|----------|-------------|
| ECS Nodes | m6g.medium (2x) | ~$60 |
| Redis | cache.m6g.large (2x) | ~$85 |
| ALB | - | ~$22 |
| NAT Gateway | 3x (1 per AZ) | ~$105 |
| **Total** | | **~$272/month** |

---

## Security Considerations

1. **Redis Security**
   - Redis runs in private subnets (no public access)
   - Security group allows only ECS instances on port 6379
   - Consider enabling `transit_encryption_enabled` and auth token for production

2. **Network Security**
   - ECS tasks in private subnets
   - ALB in public subnets
   - NAT Gateway for outbound only

3. **Encryption**
   - `at_rest_encryption_enabled`: true (production)
   - `transit_encryption_enabled`: true (production) + auth token

---

## References

- [AWS ECS High Availability](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/high_availability.html)
- [ElastiCache Multi-AZ](https://docs.aws.amazon.com/AmazonElastiCache/latest/red-ug/AutoFailover.html)
- [Lance-gg Documentation](https://lance-gg.github.io/docs/)
- [Socket.io Redis Adapter](https://socket.io/docs/v4/redis-adapter/)
