---
name: docker-deployment
description: Use when generating, reviewing, or refining Dockerfiles and docker-compose.yml configs. Triggers on: dockerize, container, image size, deployment config, compose.
---

Use when working with Docker deployment configs - generating new ones, reviewing existing, or iterative refinement.

## Entry Points

| Request Pattern | Mode |
|-----------------|------|
| "Dockerize this", "create Dockerfile" | Generate |
| "Review my Dockerfile", "check this config" | Review |
| "How can I improve...", "make this smaller" | Refine |

---

## Generate Mode

### 1. Analyze Project

```
Project analysis:
├─ Framework (FastAPI, Streamlit, Dagster, Airflow)
├─ Dependencies (pyproject.toml, uv.lock)
├─ Entry point (main.py, app.py)
└─ Multi-service? (frontend + backend, workers, schedulers)
```

### 2. Select Base Image

| Use Case | Base | Notes |
|----------|------|-------|
| Python app | `python:3.12-slim` | Default choice |
| Minimal (static analysis only) | `python:3.12-alpine` | Smaller but may need build deps |

**Minimal base decision tree:**
```
Need shell for debugging in prod?
├─ Yes → slim
└─ No → Is it a static binary?
    ├─ Yes → scratch (no OS)
    └─ No → distroless (no shell, minimal attack surface)
```

### 3. Dockerfile Pattern (uv)

```dockerfile
FROM python:3.12-slim AS base
WORKDIR /app
RUN adduser --disabled-password --gecos "" appuser

FROM base AS deps
COPY --from=ghcr.io/astral-sh/uv:latest /uv /usr/local/bin/uv
COPY pyproject.toml uv.lock ./
RUN --mount=type=cache,target=/root/.cache/uv uv sync --frozen --no-dev

FROM deps AS runtime
COPY --chown=appuser:appuser . .
USER appuser
EXPOSE 8000
CMD ["uv", "run", "uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000"]
```

### 4. Generate .dockerignore

Exclude: `.git`, `__pycache__`, `.env*`, `.venv`, `tests/`, `docs/`, `*.md`. Add project-specific patterns as needed.

### 5. docker-compose.yml Patterns

**YAML anchors for shared config:**
```yaml
x-app-common: &app-common
  image: myapp:${VERSION:-latest}
  env_file:
    - "app.env"
  networks:
    - app-network
  restart: unless-stopped
```

**Service with health dependency:**
```yaml
services:
  backend:
    <<: *app-common
    depends_on:
      postgres:
        condition: service_healthy
```

**Init service pattern (migrations, setup):**
```yaml
  app-init:
    <<: *app-common
    command: ["python", "-m", "app.migrate"]
    restart: on-failure
    profiles: [init]

  app-web:
    <<: *app-common
    depends_on:
      app-init:
        condition: service_completed_successfully
```

**Profiles for selective startup:**
```yaml
profiles:
  - local      # docker compose --profile local up
  - deploy
  - build      # one-off build tasks
```

**User permissions (host UID mapping):**
```yaml
user: "${APP_UID:-1000}:0"
```

**Resource limits:**
```yaml
deploy:
  resources:
    limits:
      memory: 512M
```

---

## Health Checks by Service

| Service | Health Check | start_period |
|---------|--------------|--------------|
| FastAPI | `curl --fail http://localhost:8000/health` | 10s |
| Streamlit | `curl --fail http://localhost:8501/_stcore/health` | 45s |
| Airflow webserver | `curl --fail http://localhost:8080/health` | 60s |
| Airflow scheduler | `curl --fail http://localhost:8974/health` | 30s |
| Dagster gRPC | `dagster api grpc-health-check -p 4000` | 30s |
| Postgres | `pg_isready -U ${POSTGRES_USER} -d ${POSTGRES_DB}` | 10s |
| OpenSearch | `curl -s localhost:9200/_cluster/health \| grep -qE '(green\|yellow)'` | 30s |
| OpenSearch Dashboards | `curl -s localhost:5601/api/status \| grep -q 'available'` | 45s |

**Health check template:**
```yaml
healthcheck:
  test: ["CMD", "curl", "--fail", "http://localhost:8000/health"]
  interval: 10s
  timeout: 10s
  retries: 5
  start_period: 30s
```

---

## Review Mode

### Security
- [ ] Non-root user? (`USER` directive)
- [ ] No secrets in build args or ENV?
- [ ] Minimal base image?
- [ ] No `latest` tags in production?
- [ ] `.dockerignore` excludes sensitive files?

### Efficiency
- [ ] Multi-stage build?
- [ ] uv cache mount? (`--mount=type=cache,target=/root/.cache/uv`)
- [ ] Dependencies before code copy?
- [ ] Combined RUN commands?

### Reliability
- [ ] Health check defined with appropriate start_period?
- [ ] Exec form for CMD? (`CMD ["app"]` not `CMD app`)
- [ ] Logs to stdout/stderr?

### Compose
- [ ] `condition: service_healthy` on dependencies?
- [ ] Resource limits defined?
- [ ] Restart policy set?
- [ ] Profiles for environment separation?

**Output format:**
```markdown
## Review

### Critical
- [Issue]: [Why] → [Fix]

### Improvements
- [Suggestion]: [Benefit]

### Good
- [What's done well]
```

---

## Refine Mode

```
Goal?
├─ Smaller image → multi-stage, slim base, cleanup
├─ Faster builds → uv cache mount, layer ordering
├─ Security → non-root, distroless, no secrets in image
├─ CI/CD → build args, cache mounts
└─ Production → health checks, logging, signals
```

---

## Dagster Multi-Container Pattern

Dagster requires three cooperating services:

```
┌─────────────────┐     ┌─────────────────┐
│  webserver      │     │  daemon         │
│  (UI, GraphQL)  │     │  (schedules,    │
│  port 3000      │     │   sensors,      │
└────────┬────────┘     │   run queue)    │
         │              └────────┬────────┘
         │                       │
         └───────────┬───────────┘
                     │ gRPC
         ┌───────────▼───────────┐
         │  user-code            │
         │  (definitions,        │
         │   your pipeline code) │
         │  port 4000            │
         └───────────────────────┘
```

**Key points:**
- `user-code` is the only service with your pipeline code
- `webserver` and `daemon` load definitions via gRPC from `user-code`
- Hot reload: restart only `user-code` when changing pipeline definitions
- All three share `dagster.yaml` (run storage, event log config)
- All three need `workspace.yaml` pointing to `user-code` gRPC location

**Compose pattern:**
```yaml
x-dagster-common: &dagster-common
  build:
    context: .
    dockerfile: infrastructure/dagster/Dockerfile
  environment: *dagster-env
  volumes:
    - ./dagster_home/dagster.yaml:/opt/dagster/dagster_home/dagster.yaml:ro
    - ./dagster_home/workspace.yaml:/opt/dagster/dagster_home/workspace.yaml:ro
  depends_on:
    postgres:
      condition: service_healthy

services:
  dagster-user-code:
    build:
      dockerfile: infrastructure/Dockerfile.user_code  # different image with your code
    entrypoint: ["dagster", "api", "grpc", "-h", "0.0.0.0", "-p", "4000", "-m", "pipeline.definitions"]
    healthcheck:
      test: ["CMD", "dagster", "api", "grpc-health-check", "-p", "4000"]

  dagster-webserver:
    <<: *dagster-common
    entrypoint: ["dagster-webserver", "-h", "0.0.0.0", "-p", "3000", "-w", "workspace.yaml"]
    depends_on:
      dagster-user-code:
        condition: service_healthy

  dagster-daemon:
    <<: *dagster-common
    entrypoint: ["dagster-daemon", "run"]
    depends_on:
      dagster-user-code:
        condition: service_healthy
```

---

## Makefile Targets

```makefile
.PHONY: up down build reset infra infra-down

up:
	docker compose --profile full up -d

down:
	docker compose --profile full down

build:
	docker compose --profile full build

reset:
	docker compose --profile full --profile infra down -v --remove-orphans

infra:
	docker compose --profile infra up -d

infra-down:
	docker compose --profile infra down
```

---

## Edge Cases

| Scenario | Approach |
|----------|----------|
| Monorepo | Per-service Dockerfiles, shared base if common runtime |
| No pyproject.toml | Ask about dependencies before generating |
| Existing partial Dockerfile | Review mode, suggest additions |
| Package builder (shared deps) | Build wheel, copy to dependent images |

---

## Anti-Patterns

| Pattern | Problem | Fix |
|---------|---------|-----|
| **COPY . . first** | Breaks cache on any change | Copy deps manifest, install, then source |
| **latest tag** | Non-reproducible | Pin versions |
| **Root user** | Security risk | `adduser` + `USER` directive |
| **Shell form CMD** | Signals not forwarded | Exec form: `CMD ["app"]` |
| **Secrets in ENV** | Visible in history | Runtime secrets, env_file |
| **No health check** | Orchestrator can't verify readiness | Add with appropriate start_period |
