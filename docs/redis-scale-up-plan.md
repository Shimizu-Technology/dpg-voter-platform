# Redis Scale-Up Plan

**Status:** Not needed yet (async ActionCable adapter works for single instance)  
**Trigger:** When any of these happen:
- Multiple Render instances needed (load balancing)
- WebSocket broadcasts unreliable under concurrent load
- Background job queuing needed (Sidekiq)

---

## Current Setup

- ActionCable adapter: `async` (in-process, single instance only)
- No Redis dependency
- Works fine for <50 concurrent users on a single Starter instance

## When Ready to Scale

### 1. Create Upstash Redis (Singapore)
- Upgrade Upstash to **Pay as you go** ($0.2/100K commands)
- Create new Redis database: `campaign-tracker-redis`, region: `ap-southeast-1`
- Copy the Redis URL (format: `rediss://default:PASSWORD@HOST:PORT`)

### 2. Set Environment Variable
```bash
# On Render (use restart, not deploy)
REDIS_URL=rediss://default:PASSWORD@HOST:PORT
```

### 3. Update cable.yml
```yaml
# config/cable.yml
production:
  adapter: redis
  url: <%= ENV.fetch("REDIS_URL") %>
  channel_prefix: campaign_tracker_production
```

### 4. Restart
```bash
# Restart picks up env vars without rebuild
curl -X POST "https://api.render.com/v1/services/srv-d679ccggjchc73ahc6eg/restart" \
  -H "Authorization: Bearer $RENDER_KEY"
```

## Estimated Cost
- **Pay-as-you-go:** ~$0.10-$1/mo for campaign-scale ActionCable usage
- ActionCable pub/sub generates minimal commands (subscribe/publish per channel)
- Even on election day with 50+ concurrent users: well under 100K commands/mo

## Future: Sidekiq
If background jobs grow beyond Solid Queue (Rails default):
- Same Redis instance works for Sidekiq
- Add `sidekiq` gem, configure with same `REDIS_URL`
- No additional infrastructure needed
