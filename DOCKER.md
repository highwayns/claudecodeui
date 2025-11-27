# Docker Deployment Guide

This guide explains how to build and run Claude Code UI using Docker.

## Quick Start

### Using Docker Compose (Recommended)

```bash
# Build and start the container
docker-compose up -d

# View logs
docker-compose logs -f

# Stop the container
docker-compose down

# Stop and remove volumes (WARNING: deletes database)
docker-compose down -v
```

Access the application at `http://localhost:3001`

### Using Docker CLI

```bash
# Build the image
docker build -t claude-code-ui:latest .

# Run the container
docker run -d \
  --name claude-code-ui \
  -p 3001:3001 \
  -v claude-data:/app/data \
  --restart unless-stopped \
  claude-code-ui:latest

# View logs
docker logs -f claude-code-ui

# Stop the container
docker stop claude-code-ui

# Remove the container
docker rm claude-code-ui
```

## Configuration

### Environment Variables

Configure the application by setting environment variables:

| Variable | Default | Description |
|----------|---------|-------------|
| `PORT` | `3001` | Backend server port |
| `DATABASE_PATH` | `/app/data/auth.db` | SQLite database location |
| `CONTEXT_WINDOW` | `160000` | Claude context window size |
| `VITE_CONTEXT_WINDOW` | `160000` | Frontend context window size |
| `CLAUDE_CLI_PATH` | `claude` | Path to Claude CLI executable |
| `NODE_ENV` | `production` | Node environment |

#### Using .env File

Create a `.env` file based on `.env.example`:

```bash
cp .env.example .env
# Edit .env with your configuration
```

Then mount it in docker-compose.yml:

```yaml
volumes:
  - ./.env:/app/.env:ro
```

#### Using Docker Compose Environment

Edit `docker-compose.yml`:

```yaml
environment:
  - PORT=3001
  - DATABASE_PATH=/app/data/auth.db
  - CONTEXT_WINDOW=160000
```

#### Using Docker CLI

```bash
docker run -d \
  -e PORT=3001 \
  -e DATABASE_PATH=/app/data/auth.db \
  -e CONTEXT_WINDOW=160000 \
  claude-code-ui:latest
```

## Data Persistence

The SQLite database is stored in `/app/data/auth.db` inside the container. Use Docker volumes to persist data:

### Named Volume (Recommended)

```bash
# Docker Compose (already configured)
volumes:
  - claude-data:/app/data

# Docker CLI
docker run -v claude-data:/app/data claude-code-ui:latest
```

### Bind Mount

```bash
# Docker Compose
volumes:
  - ./data:/app/data

# Docker CLI
docker run -v $(pwd)/data:/app/data claude-code-ui:latest
```

### Backup Database

```bash
# Using Docker Compose
docker-compose exec claude-code-ui cp /app/data/auth.db /app/data/auth.db.backup

# Copy to host
docker cp claude-code-ui:/app/data/auth.db ./backup-auth.db
```

## Port Mapping

The application exposes port `3001` by default. To use a different port:

```bash
# Docker Compose
ports:
  - "8080:3001"  # Access at http://localhost:8080

# Docker CLI
docker run -p 8080:3001 claude-code-ui:latest
```

## Health Checks

The container includes a health check that monitors the Express server:

```bash
# Check health status
docker inspect --format='{{.State.Health.Status}}' claude-code-ui

# View health check logs
docker inspect --format='{{range .State.Health.Log}}{{.Output}}{{end}}' claude-code-ui
```

Health check configuration:
- Interval: 30 seconds
- Timeout: 3 seconds
- Retries: 3
- Start period: 10 seconds

## Resource Limits

Configure resource limits in `docker-compose.yml`:

```yaml
deploy:
  resources:
    limits:
      cpus: '2'
      memory: 2G
    reservations:
      cpus: '1'
      memory: 1G
```

Or with Docker CLI:

```bash
docker run \
  --cpus="2" \
  --memory="2g" \
  --memory-reservation="1g" \
  claude-code-ui:latest
```

## Multi-Stage Build

The Dockerfile uses a multi-stage build for optimization:

1. **Builder Stage**: Compiles native modules and builds frontend
   - Base: `node:20-alpine`
   - Installs build tools (python, make, g++)
   - Runs `npm ci` with dev dependencies
   - Builds frontend with Vite

2. **Production Stage**: Creates minimal runtime image
   - Base: `node:20-alpine`
   - Installs only production dependencies
   - Copies built frontend from builder
   - Runs as non-root user
   - Includes health checks

## Security

### Non-Root User

The container runs as a non-root user (`nodejs:1001`) for security:

```dockerfile
USER nodejs
```

### Signal Handling

Uses `dumb-init` for proper signal handling and zombie process reaping:

```dockerfile
ENTRYPOINT ["/usr/bin/dumb-init", "--"]
```

### Read-Only Root Filesystem (Optional)

For enhanced security, run with read-only root filesystem:

```bash
docker run \
  --read-only \
  --tmpfs /tmp \
  -v claude-data:/app/data \
  claude-code-ui:latest
```

## Troubleshooting

### Container Won't Start

```bash
# View logs
docker-compose logs claude-code-ui

# Check for port conflicts
lsof -i :3001

# Verify build completed successfully
docker-compose build --no-cache
```

### Native Module Issues

If you encounter errors with native modules (bcrypt, better-sqlite3, node-pty):

```bash
# Rebuild with no cache
docker-compose build --no-cache

# Verify Alpine version matches Node.js
docker run --rm node:20-alpine node --version
```

### Permission Issues

```bash
# Check volume permissions
docker-compose exec claude-code-ui ls -la /app/data

# Fix permissions (if using bind mount)
sudo chown -R 1001:1001 ./data
```

### Database Locked

```bash
# Stop all containers using the database
docker-compose down

# Remove lock files
rm -f data/auth.db-journal data/auth.db-shm data/auth.db-wal

# Restart
docker-compose up -d
```

## Development

For development with hot-reload:

```yaml
# docker-compose.dev.yml
version: '3.8'
services:
  claude-code-ui-dev:
    build:
      context: .
      dockerfile: Dockerfile
      target: builder
    command: npm run dev
    ports:
      - "3001:3001"
      - "5173:5173"
    volumes:
      - .:/app
      - /app/node_modules
    environment:
      - NODE_ENV=development
```

```bash
docker-compose -f docker-compose.dev.yml up
```

## Production Deployment

### Build Optimization

```bash
# Build with specific platform
docker buildx build --platform linux/amd64 -t claude-code-ui:latest .

# Build multi-platform
docker buildx build \
  --platform linux/amd64,linux/arm64 \
  -t claude-code-ui:latest \
  --push \
  .
```

### Docker Registry

```bash
# Tag image
docker tag claude-code-ui:latest registry.example.com/claude-code-ui:1.12.0

# Push to registry
docker push registry.example.com/claude-code-ui:1.12.0
```

### Kubernetes Deployment

Example Kubernetes manifest:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: claude-code-ui
spec:
  replicas: 2
  selector:
    matchLabels:
      app: claude-code-ui
  template:
    metadata:
      labels:
        app: claude-code-ui
    spec:
      containers:
      - name: claude-code-ui
        image: claude-code-ui:latest
        ports:
        - containerPort: 3001
        env:
        - name: DATABASE_PATH
          value: /app/data/auth.db
        volumeMounts:
        - name: data
          mountPath: /app/data
        livenessProbe:
          httpGet:
            path: /health
            port: 3001
          initialDelaySeconds: 10
          periodSeconds: 30
        resources:
          limits:
            memory: "2Gi"
            cpu: "2"
          requests:
            memory: "1Gi"
            cpu: "1"
      volumes:
      - name: data
        persistentVolumeClaim:
          claimName: claude-data-pvc
---
apiVersion: v1
kind: Service
metadata:
  name: claude-code-ui
spec:
  selector:
    app: claude-code-ui
  ports:
  - port: 80
    targetPort: 3001
  type: LoadBalancer
```

## Monitoring

### Logs

```bash
# Follow logs
docker-compose logs -f

# Last 100 lines
docker-compose logs --tail=100

# Specific service logs
docker-compose logs -f claude-code-ui
```

### Metrics

```bash
# Container stats
docker stats claude-code-ui

# Detailed inspection
docker inspect claude-code-ui
```

### Health Monitoring

```bash
# Continuous health check
watch -n 5 'docker inspect --format="{{.State.Health.Status}}" claude-code-ui'
```

## Cleanup

```bash
# Stop and remove containers
docker-compose down

# Remove volumes (WARNING: deletes data)
docker-compose down -v

# Remove images
docker rmi claude-code-ui:latest

# Prune unused Docker resources
docker system prune -a --volumes
```
