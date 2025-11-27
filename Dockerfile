# Multi-stage build for Claude Code UI
# Stage 1: Build dependencies and frontend
FROM node:20-alpine AS builder

# Install build dependencies for native modules (bcrypt, better-sqlite3, node-pty)
RUN apk add --no-cache \
    python3 \
    make \
    g++ \
    linux-headers

# Set working directory
WORKDIR /app

# Copy package files
COPY package*.json ./

# Install ALL dependencies (including devDependencies for build)
RUN npm ci --include=dev

# Copy source code
COPY . .

# Build frontend with Vite
RUN npm run build

# Stage 2: Production runtime
FROM node:20-alpine

# Install runtime dependencies for native modules
RUN apk add --no-cache \
    python3 \
    dumb-init

# Create non-root user for security
RUN addgroup -g 1001 -S nodejs && \
    adduser -S nodejs -u 1001

# Set working directory
WORKDIR /app

# Copy package files
COPY package*.json ./

# Install production dependencies only
# Use ci for reproducible builds and include native module rebuilding
RUN apk add --no-cache --virtual .build-deps \
    python3 \
    make \
    g++ \
    linux-headers && \
    npm ci --omit=dev && \
    apk del .build-deps

# Copy built frontend from builder stage
COPY --from=builder --chown=nodejs:nodejs /app/dist ./dist

# Copy server code
COPY --chown=nodejs:nodejs server ./server
COPY --chown=nodejs:nodejs index.html ./
COPY --chown=nodejs:nodejs vite.config.js ./
COPY --chown=nodejs:nodejs tailwind.config.js ./
COPY --chown=nodejs:nodejs postcss.config.js ./
COPY --chown=nodejs:nodejs .env.example ./

# Create directory for database with proper permissions
RUN mkdir -p /app/data && chown -R nodejs:nodejs /app/data

# Switch to non-root user
USER nodejs

# Expose backend port (Express + WebSocket)
EXPOSE 3001

# Environment variables (can be overridden at runtime)
ENV NODE_ENV=production
ENV PORT=3001
ENV DATABASE_PATH=/app/data/auth.db

# Health check for Express server
HEALTHCHECK --interval=30s --timeout=3s --start-period=10s --retries=3 \
    CMD node -e "require('http').get('http://localhost:3001/health', (r) => {process.exit(r.statusCode === 200 ? 0 : 1)})" || exit 1

# Use dumb-init to handle signals properly
ENTRYPOINT ["/usr/bin/dumb-init", "--"]

# Start the server
CMD ["node", "server/index.js"]
