# Build context: addon/ directory
# HA Supervisor uses the config.yaml directory as build context.

# Global ARG — must be before any FROM to be visible across stages
ARG BUILD_FROM=ghcr.io/hassio-addons/base:21.0.8

# Stage 1: Build MCP server and pre-index docs
# Use the same Alpine version as the HA base image (see MAINTENANCE.md in the
# repository root), so the builder installs the npm packages for the same libc
# (musl) and Node.js major that run them in the add-on.
FROM alpine:3.24 AS mcp-builder

# Pin the pnpm major version — pnpm 11 removed support for the "pnpm" field in
# package.json and renamed the build-script allowlist to allowBuilds in
# pnpm-workspace.yaml. An unpinned install broke this build once already (#4).
# No compiler: better-sqlite3 13 ships prebuilt binaries for musl (x64 and
# arm64), so nothing is compiled any more.
RUN apk add --no-cache nodejs npm git && \
    npm install -g pnpm@11

WORKDIR /build

# Install MCP server dependencies
# pnpm-workspace.yaml carries the allowBuilds allowlist and must be present
# before install, or pnpm refuses to run dependency build scripts.
COPY mcp-server/package.json mcp-server/pnpm-workspace.yaml mcp-server/pnpm-lock.yaml* ./mcp-server/
RUN cd mcp-server && \
    if [ -f pnpm-lock.yaml ]; then pnpm install --frozen-lockfile; \
    else pnpm install; fi

# Copy MCP server source
COPY mcp-server/ ./mcp-server/

# Clone docs from the repository (same repo, just need the docs/ directory).
# DOCS_STAMP is the git tree hash of docs/, refreshed by the weekly workflow
# when the docs change. A new value busts the Docker layer cache; otherwise the
# Supervisor keeps the clone from the first install forever. The clone comes
# after the dependency install so a docs change does not re-resolve npm deps.
ARG DOCS_REPO=https://github.com/dktzde/hass-claude-code.git
ARG DOCS_REF=main
ARG DOCS_STAMP=43055f1534ede37936978bf4ee0ec5fc661be837
RUN echo "Docs stamp: ${DOCS_STAMP}" && \
    git clone --depth 1 --branch "${DOCS_REF}" "${DOCS_REPO}" /tmp/repo && \
    cp -r /tmp/repo/docs /build/docs && \
    rm -rf /tmp/repo

# Build keyword-only index (needs tsx for TypeScript source)
RUN cd mcp-server && \
    DOCS_DB_PATH=/build/mcp-server/data/docs-search.db \
    DOCS_PATH=/build/docs \
    node --import tsx src/build-index.ts

# Compile TypeScript to JavaScript
RUN cd mcp-server && pnpm run build

# Prune dev dependencies (tsx, typescript, @types/*) from final output
RUN cd mcp-server && pnpm prune --prod

# Stage 2: Final add-on image
# hadolint ignore=DL3006
FROM ${BUILD_FROM}

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

ENV TERM="xterm-256color"

# Install system packages and upgrade the ones from the base image.
# PACKAGES_STAMP is a hash of addon/packages.txt (the package versions of the
# last CI build), refreshed by the weekly workflow when Alpine ships updates.
# A new value busts the Docker layer cache; otherwise the Supervisor keeps the
# versions from the first install forever.
ARG PACKAGES_STAMP=24249db91d79
# hadolint ignore=DL3017,DL3018
RUN echo "Packages stamp: ${PACKAGES_STAMP}" && \
    apk upgrade --no-cache && \
    apk add --no-cache \
    bash \
    ca-certificates \
    curl \
    git \
    github-cli \
    libgcc \
    libstdc++ \
    mosquitto-clients \
    nodejs \
    py3-yaml \
    python3 \
    ripgrep \
    tmux \
    ttyd

# Pinned so a version change busts the Docker layer cache; the Supervisor
# builds without --no-cache, so an unpinned install would stay stale forever.
ARG CLAUDE_CODE_VERSION=2.1.295
RUN curl -fsSL https://claude.ai/install.sh | bash -s "${CLAUDE_CODE_VERSION}"

# Add Claude Code to PATH and disable auto-updater
ENV PATH="/root/.local/bin:${PATH}" \
    DISABLE_AUTOUPDATER=1

# Copy MCP server from builder (compiled JS + prod deps + pre-built DB)
COPY --from=mcp-builder /build/mcp-server/dist /opt/mcp-server/dist
COPY --from=mcp-builder /build/mcp-server/node_modules /opt/mcp-server/node_modules
COPY --from=mcp-builder /build/mcp-server/data /opt/mcp-server/data
COPY --from=mcp-builder /build/mcp-server/package.json /opt/mcp-server/package.json

# Copy docs
COPY --from=mcp-builder /build/docs /opt/docs

# Copy rootfs overlay
COPY rootfs /

# Ensure scripts are executable
RUN chmod a+x /usr/bin/claude-entrypoint.sh \
    && find /etc/s6-overlay/s6-rc.d -name 'run' -exec chmod a+x {} \; \
    && find /etc/s6-overlay/s6-rc.d -name 'finish' -exec chmod a+x {} \;

# Build arguments for labels
ARG BUILD_ARCH
ARG BUILD_DATE
ARG BUILD_DESCRIPTION
ARG BUILD_NAME
ARG BUILD_REF
ARG BUILD_REPOSITORY
ARG BUILD_VERSION

# Labels
LABEL \
    io.hass.name="${BUILD_NAME}" \
    io.hass.description="${BUILD_DESCRIPTION}" \
    io.hass.arch="${BUILD_ARCH}" \
    io.hass.type="addon" \
    io.hass.version=${BUILD_VERSION}
