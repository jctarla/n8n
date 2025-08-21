# Multi-stage Dockerfile for n8n - Complete build from source
# Usage: docker build -f Dockerfile.complete -t n8n:local .

ARG NODE_VERSION=22
ARG ALPINE_VERSION=3.22

# ==============================================================================
# STAGE 1: Base Dependencies
# ==============================================================================
FROM node:${NODE_VERSION}-alpine AS base-deps

# Install system dependencies and fonts
RUN echo "http://dl-cdn.alpinelinux.org/alpine/edge/main" >> /etc/apk/repositories && \
    apk update && apk upgrade && \
    apk add --no-cache \
        git \
        openssh \
        openssl \
        graphicsmagick \
        tini \
        tzdata \
        ca-certificates \
        libc6-compat \
        jq \
        python3 \
        make \
        g++ \
        sqlite \
        sqlite-dev && \
    # Install fonts
    apk --no-cache add --virtual .build-deps-fonts msttcorefonts-installer fontconfig && \
    update-ms-fonts && \
    fc-cache -f && \
    apk del .build-deps-fonts && \
    find /usr/share/fonts/truetype/msttcorefonts/ -type l -exec unlink {} \; && \
    # Install npm and full-icu
    npm install -g full-icu@1.5.0 npm@11.4.2 && \
    # Cleanup build cache
    rm -rf /tmp/* /root/.npm /root/.cache/node /var/cache/apk/*

# Set environment variables
ENV NODE_ICU_DATA=/usr/local/lib/node_modules/full-icu
ENV PNPM_HOME="/pnpm"
ENV PATH="$PNPM_HOME:$PATH"

# Install pnpm with exact version
RUN corepack enable && corepack prepare pnpm@10.12.1 --activate

# ==============================================================================
# STAGE 2: Build Stage
# ==============================================================================
FROM base-deps AS builder

WORKDIR /app

# Copy package manager files
COPY package.json pnpm-lock.yaml pnpm-workspace.yaml ./
COPY turbo.json ./

# Copy all package.json files to install dependencies correctly
COPY packages/ packages/
RUN find packages -name "*.ts" -o -name "*.js" -o -name "*.vue" | head -1 > /dev/null || find packages -type f ! -name "package.json" -delete

# Copy patches and scripts (needed for preinstall hooks)
COPY patches/ patches/
COPY scripts/ scripts/

# Install all dependencies (including dev dependencies for building)
RUN pnpm install --frozen-lockfile

# Copy source code
COPY . .

# Build the application
RUN pnpm build

# Create production deployment
RUN mkdir -p /compiled && \
    NODE_ENV=production DOCKER_BUILD=true pnpm --filter=n8n --prod deploy --no-optional /compiled

# ==============================================================================
# STAGE 3: Task Runner Launcher
# ==============================================================================
FROM alpine:${ALPINE_VERSION} AS launcher-downloader

ARG TARGETPLATFORM
ARG LAUNCHER_VERSION=1.1.5

RUN set -e; \
    case "$TARGETPLATFORM" in \
        "linux/amd64") ARCH_NAME="amd64" ;; \
        "linux/arm64") ARCH_NAME="arm64" ;; \
        "linux/arm/v7") ARCH_NAME="amd64" ;; \
        *) echo "Unsupported platform: $TARGETPLATFORM, defaulting to amd64" && ARCH_NAME="amd64" ;; \
    esac; \
    mkdir /launcher-temp && cd /launcher-temp; \
    wget -q "https://github.com/n8n-io/task-runner-launcher/releases/download/${LAUNCHER_VERSION}/task-runner-launcher-${LAUNCHER_VERSION}-linux-${ARCH_NAME}.tar.gz" || exit 0; \
    wget -q "https://github.com/n8n-io/task-runner-launcher/releases/download/${LAUNCHER_VERSION}/task-runner-launcher-${LAUNCHER_VERSION}-linux-${ARCH_NAME}.tar.gz.sha256" || exit 0; \
    if [ -f "task-runner-launcher-${LAUNCHER_VERSION}-linux-${ARCH_NAME}.tar.gz.sha256" ]; then \
        echo "$(cat task-runner-launcher-${LAUNCHER_VERSION}-linux-${ARCH_NAME}.tar.gz.sha256) task-runner-launcher-${LAUNCHER_VERSION}-linux-${ARCH_NAME}.tar.gz" > checksum.sha256; \
        sha256sum -c checksum.sha256; \
        mkdir -p /launcher-bin; \
        tar xzf task-runner-launcher-${LAUNCHER_VERSION}-linux-${ARCH_NAME}.tar.gz -C /launcher-bin; \
    else \
        mkdir -p /launcher-bin; \
    fi; \
    cd / && rm -rf /launcher-temp

# ==============================================================================
# STAGE 4: Runtime Base
# ==============================================================================
FROM node:${NODE_VERSION}-alpine AS runtime-base

# Install runtime dependencies
RUN apk update && apk add --no-cache \
        tini \
        tzdata \
        ca-certificates \
        sqlite \
        graphicsmagick \
        libc6-compat && \
    # Install npm and full-icu
    npm install -g full-icu@1.5.0 npm@11.4.2 && \
    # Install fonts
    apk --no-cache add --virtual .build-deps-fonts msttcorefonts-installer fontconfig && \
    update-ms-fonts && \
    fc-cache -f && \
    apk del .build-deps-fonts && \
    find /usr/share/fonts/truetype/msttcorefonts/ -type l -exec unlink {} \; && \
    rm -rf /var/cache/apk/*

# Set environment variables
ENV NODE_ICU_DATA=/usr/local/lib/node_modules/full-icu
ENV NODE_ENV=production
ENV N8N_RELEASE_TYPE=stable
ENV SHELL=/bin/sh

# Ensure node user exists with correct permissions
RUN if ! getent group node > /dev/null 2>&1; then addgroup -g 1000 node; fi && \
    if ! getent passwd node > /dev/null 2>&1; then adduser -u 1000 -G node -s /bin/sh -D node; fi

# ==============================================================================
# STAGE 5: Final Runtime Image
# ==============================================================================
FROM runtime-base AS runtime

ARG N8N_VERSION=local

WORKDIR /home/node

# Copy built application from builder stage
COPY --from=builder --chown=node:node /compiled /usr/local/lib/node_modules/n8n

# Copy task runner launcher if available (handle case where directory might be empty)
RUN mkdir -p /tmp/launcher-temp
COPY --from=launcher-downloader /launcher-bin /tmp/launcher-temp/
RUN if [ -n "$(ls -A /tmp/launcher-temp/ 2>/dev/null)" ]; then \
      cp /tmp/launcher-temp/* /usr/local/bin/ 2>/dev/null || true; \
    fi && \
    rm -rf /tmp/launcher-temp

# Copy the actual entrypoint script from the source
COPY docker/images/n8n/docker-entrypoint.sh /docker-entrypoint.sh

# Copy task runner config if it exists in the source
COPY docker/images/n8n/n8n-task-runners.json /etc/n8n-task-runners.json

# Setup the application
RUN cd /usr/local/lib/node_modules/n8n && \
    # Rebuild native dependencies for runtime environment
    npm rebuild sqlite3 && \
    # Create symlink for n8n binary
    ln -s /usr/local/lib/node_modules/n8n/bin/n8n /usr/local/bin/n8n && \
    # Install canvas for PDF processing
    cd /usr/local/lib/node_modules/n8n/node_modules/pdfjs-dist && npm install @napi-rs/canvas && \
    # Setup user directory
    mkdir -p /home/node/.n8n && \
    chown -R node:node /home/node && \
    # Make entrypoint executable
    chmod +x /docker-entrypoint.sh

# Expose port
EXPOSE 5678

# Switch to non-root user
USER node

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=60s --retries=3 \
  CMD wget --no-verbose --tries=1 --spider http://localhost:5678/healthz || exit 1

# Entry point
ENTRYPOINT ["tini", "--", "/docker-entrypoint.sh"]
CMD []

# Labels
LABEL org.opencontainers.image.title="n8n" \
      org.opencontainers.image.description="Workflow Automation Tool - Complete Build" \
      org.opencontainers.image.source="https://github.com/n8n-io/n8n" \
      org.opencontainers.image.url="https://n8n.io" \
      org.opencontainers.image.version="${N8N_VERSION}"