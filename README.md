# AnyOne Infrastructure

Deploy-only infrastructure repository for the AnyOne Project. This repo defines **how and where** Docker services run — it does not build application code.

## Architecture

```
Layer 1 (Build)                    Layer 2 (Deploy)
┌──────────────┐                   ┌──────────────────────┐
│  Team Repos  │                   │  This Infra Repo     │
│              │   push image      │                      │
│  edr-backend ├──────────────►    │  edr/                │
│  uba-backend │   to GHCR         │  uba/                │
│  llm-backend │                   │  llm/                │
│  llm-frontend│   trigger         │                      │
│              ├──────────────►    │  .github/workflows/  │
└──────────────┘  repository_      │                      │
                  dispatch         │  scripts/deploy.sh   │
                                   └─────────┬────────────┘
                                             │ SSH
                                   ┌─────────▼────────────┐
                                   │  VPS (Staging/Prod)   │
                                   │  docker compose up -d │
                                   └──────────────────────┘
```

**CI/CD flow:**
1. Team repo pushes Docker image to GHCR (`ghcr.io/anyone-project/<service>`)
2. Team repo triggers this infra repo via `repository_dispatch`
3. GitHub Actions SSHs into the correct VPS
4. Runs `docker compose pull && up -d` with the correct environment overlay

## Repo Structure

```
infra/
├── edr/                              # EDR stack (PostgreSQL + edr-backend)
│   ├── docker-compose.yml            # Base config (infra + app services)
│   ├── docker-compose.staging.yml    # Staging: adds pgAdmin, lower resources
│   ├── docker-compose.prod.yml       # Production: hardened, higher resources
│   ├── .env.example                  # Common env vars template
│   ├── .env.staging.example          # Staging-specific vars template
│   └── .env.prod.example             # Production-specific vars template
├── uba/                              # UBA stack (Kafka + Schema Registry + uba-backend)
│   └── (same pattern as edr/)
├── llm/                              # LLM stack (Neo4j + Redis + llm-backend + llm-frontend)
│   └── (same pattern as edr/)
├── shared/
│   └── network-init.sh              # Creates anyone_network if not exists
├── scripts/
│   └── deploy.sh                    # Main deploy orchestrator
├── .github/workflows/
│   ├── deploy-staging.yml           # Auto-deploy to staging VPS
│   └── deploy-production.yml        # Deploy to prod (manual approval gate)
├── examples/
│   └── team-build-workflow.yml      # Reference CI/CD workflow for team repos
├── .gitignore
└── README.md
```

## Stacks

### EDR Stack (`edr/`)
| Service | Image | Purpose |
|---------|-------|---------|
| postgres | `postgres:18-trixie` | Primary database |
| edr-backend | `ghcr.io/anyone-project/edr-backend` | Application server |
| pgadmin | `dpage/pgadmin4:9.13` | DB admin UI (staging only) |

### UBA Stack (`uba/`)
| Service | Image | Purpose |
|---------|-------|---------|
| kafka | `confluentinc/cp-kafka:7.8.7` | Message broker (KRaft mode) |
| schema-registry | `confluentinc/cp-schema-registry:7.8.7` | Avro/JSON schema management |
| uba-backend | `ghcr.io/anyone-project/uba-backend` | ML application server |
| kafka-ui | `provectuslabs/kafka-ui:v0.7.2` | Cluster dashboard (staging only) |

### LLM Stack (`llm/`)
| Service | Image | Purpose |
|---------|-------|---------|
| neo4j | `neo4j:5.26.22-community-trixie` | Graph database |
| redis | `redis:8.6-trixie` | Cache / message broker |
| llm-backend | `ghcr.io/anyone-project/llm-backend` | LLM application server |
| llm-frontend | `ghcr.io/anyone-project/llm-frontend` | Web UI |
| redis-insight | `redis/redisinsight:2.68` | Redis debug UI (staging only) |

## Setting Up a New VPS

### Prerequisites
- Docker Engine 24+
- Docker Compose v2 (plugin, not standalone)
- Git
- SSH access configured

### Steps

1. **Clone this repo:**
   ```bash
   git clone git@github.com:anyone-project/anyone-infra.git /opt/anyone-infra
   cd /opt/anyone-infra
   ```

2. **Initialize the shared network:**
   ```bash
   bash shared/network-init.sh
   ```

3. **Create environment files** for each stack you want to run:
   ```bash
   # For each stack (edr, uba, llm):
   cp edr/.env.example edr/.env
   cp edr/.env.staging.example edr/.env.staging   # or .env.prod for production

   # Edit and fill in actual values:
   nano edr/.env
   nano edr/.env.staging
   ```

4. **Deploy:**
   ```bash
   bash scripts/deploy.sh staging all
   # or for production:
   bash scripts/deploy.sh prod all
   ```

## Manual Deploy

```bash
# Deploy all stacks to staging
bash scripts/deploy.sh staging all

# Deploy only EDR to production
bash scripts/deploy.sh prod edr

# Dry run — shows commands without executing
bash scripts/deploy.sh --dry-run staging all
```

**What `deploy.sh` does:**
1. Creates `anyone_network` Docker network if missing
2. For each target stack, runs:
   ```
   docker compose \
     -f <stack>/docker-compose.yml \
     -f <stack>/docker-compose.<env>.yml \
     --env-file <stack>/.env \
     --env-file <stack>/.env.<env> \
     up -d --pull always --remove-orphans
   ```

## CI/CD

### How It Works

Team repos trigger deploys via GitHub's `repository_dispatch` API:

```bash
# Example: trigger staging deploy for EDR stack
curl -X POST \
  -H "Authorization: Bearer $GITHUB_PAT" \
  -H "Accept: application/vnd.github+json" \
  https://api.github.com/repos/anyone-project/anyone-infra/dispatches \
  -d '{"event_type": "deploy-staging", "client_payload": {"stack": "edr"}}'
```

- **Staging** (`deploy-staging.yml`): Runs automatically on dispatch
- **Production** (`deploy-production.yml`): Requires manual approval via GitHub environment protection rules

Both workflows also support manual trigger via `workflow_dispatch` in the GitHub Actions UI.

### Required GitHub Secrets

| Secret | Description |
|--------|-------------|
| `STAGING_SSH_HOST` | Staging VPS hostname or IP |
| `STAGING_SSH_USER` | SSH username for staging |
| `STAGING_SSH_KEY` | SSH private key for staging |
| `STAGING_INFRA_DIR` | Repo path on staging VPS (default: `/opt/anyone-infra`) |
| `PROD_SSH_HOST` | Production VPS hostname or IP |
| `PROD_SSH_USER` | SSH username for production |
| `PROD_SSH_KEY` | SSH private key for production |
| `PROD_INFRA_DIR` | Repo path on prod VPS (default: `/opt/anyone-infra`) |

### Setting Up Team Repos

Copy `examples/team-build-workflow.yml` into your team's repo at `.github/workflows/build-deploy.yml` and adjust the variables at the top:

```yaml
env:
  IMAGE_NAME: ghcr.io/anyone-project/your-service-name
  INFRA_REPO: anyone-project/anyone-infra
  STACK_NAME: edr  # your stack: edr, uba, or llm
```

Your repo also needs an `INFRA_REPO_PAT` secret — a GitHub PAT with `repo` scope for triggering the infra repo dispatch.

## Adding a New Team/Stack

1. Create a new directory (e.g., `newteam/`)
2. Add the standard files:
   - `docker-compose.yml` — base config with infra + app services
   - `docker-compose.staging.yml` — staging overrides (admin UIs, lower resources)
   - `docker-compose.prod.yml` — production overrides (hardened, no admin UIs)
   - `.env.example`, `.env.staging.example`, `.env.prod.example`
3. Follow the patterns from existing stacks:
   - All ports bound to `127.0.0.1`
   - Health checks on every service
   - `depends_on` with `condition: service_healthy`
   - Use `anyone_network` (external)
4. The deploy script (`scripts/deploy.sh`) needs to be updated to include the new stack in the `VALID_STACKS` array and the `all` deployment loop

## Environment Differences

| Feature | Staging | Production |
|---------|---------|------------|
| Admin UIs | Included (pgAdmin, Kafka UI, Redis Insight) | Excluded |
| Admin UI ports | `127.0.0.1` only (SSH tunnel) | N/A |
| Restart policy | `unless-stopped` | `always` |
| Filesystem | Writable | `read_only` + tmpfs |
| Resource limits | Lower (1-2G) | Higher (2-4G) |
| Log rotation | Default | `json-file` with 10m max, 3 files |
| Image tag | `staging` | `prod` |

## Networking

All stacks share a single external Docker network: `anyone_network`. This allows cross-stack communication (e.g., LLM backend talking to EDR's PostgreSQL if needed).

Services are accessible by their container names across the network.

### Port Access

All ports are bound to `127.0.0.1` — nothing is publicly exposed. Access services via:
- **SSH tunnel**: `ssh -L 5050:127.0.0.1:5050 user@vps` (then visit `localhost:5050`)
- **Reverse proxy**: Set up nginx/traefik in front of services that need public access

## Troubleshooting

**Containers not starting:**
```bash
# Check logs for a specific stack
docker compose -f edr/docker-compose.yml -f edr/docker-compose.staging.yml logs -f

# Check health status
docker ps --format "table {{.Names}}\t{{.Status}}"
```

**Network issues:**
```bash
# Verify network exists
docker network inspect anyone_network

# Recreate if needed
docker network rm anyone_network
bash shared/network-init.sh
```

**Image pull failures:**
```bash
# Verify GHCR authentication
docker login ghcr.io

# Pull manually
docker pull ghcr.io/anyone-project/edr-backend:staging
```

**Environment variable issues:**
```bash
# Validate compose config (shows resolved variables)
docker compose -f edr/docker-compose.yml -f edr/docker-compose.staging.yml \
  --env-file edr/.env --env-file edr/.env.staging config
```

**Disk space:**
```bash
# Check Docker disk usage
docker system df

# Clean up unused images/volumes
docker system prune -a --volumes
```
