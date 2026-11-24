# Build context: addon/ directory
# HA Supervisor uses the config.yaml directory as build context.

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
# apk retries after 20 s and 2 min: the Supervisor builds on the user's own
# network, where a short outage otherwise fails the whole update.
RUN for wait in 20 120 0; do \
        apk add --no-cache nodejs npm git && break; \
        [ "${wait}" -eq 0 ] && exit 1; \
        echo "apk failed, retrying in ${wait} s"; sleep "${wait}"; \
    done && \
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
ARG DOCS_STAMP=53f48c015c1b62e5ad738331301f4728b09cbaf7
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
# The base image is set here and nowhere else (there is no build.yaml). It is a
# fixed FROM, not ARG BUILD_FROM: a Supervisor before 2026.04.0 passes its own
# BUILD_FROM when there is no build.yaml, which would override an ARG default.
FROM ghcr.io/hassio-addons/base:21.0.11

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

ENV TERM="xterm-256color"

# Install system packages and upgrade the ones from the base image.
# PACKAGES_STAMP is a hash of addon/packages.txt (the package versions of the
# last CI build), refreshed by the weekly workflow when Alpine ships updates.
# A new value busts the Docker layer cache; otherwise the Supervisor keeps the
# versions from the first install forever.
ARG PACKAGES_STAMP=43b5f37c3032
# hadolint ignore=DL3017,DL3018
# apk retries after 20 s and 2 min (see the builder stage).
RUN echo "Packages stamp: ${PACKAGES_STAMP}" && \
    for wait in 20 120 0; do \
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
        ttyd \
        && break; \
        [ "${wait}" -eq 0 ] && exit 1; \
        echo "apk failed, retrying in ${wait} s"; sleep "${wait}"; \
    done

# Save ttyd's built-in page, so the ttyd service can add the browser scripts
# from /usr/share/ttyd-addon/ to it (see ttyd/run). ttyd has no option to
# print the page, so serve it briefly on a UNIX socket. This layer comes
# right after the package install, so a new ttyd version saves its new page.
# The page must contain window.term (the terminal the scripts use); if it is
# missing, the add-on runs with ttyd's own page.
RUN mkdir -p /usr/share/ttyd-addon; \
    ttyd -i /tmp/ttyd.sock true > /dev/null 2>&1 & \
    ttyd_pid=$!; \
    for _ in $(seq 1 20); do \
        curl -fsS --unix-socket /tmp/ttyd.sock http://localhost/ \
            -o /usr/share/ttyd-addon/ttyd-index.html 2>/dev/null && break; \
        sleep 0.5; \
    done; \
    kill "${ttyd_pid}"; \
    rm -f /tmp/ttyd.sock; \
    if grep -q 'window.term=' /usr/share/ttyd-addon/ttyd-index.html 2>/dev/null; then \
        echo "Saved the page of $(ttyd --version)"; \
    else \
        echo "WARNING: could not save ttyd's page" && \
        rm -f /usr/share/ttyd-addon/ttyd-index.html; \
    fi

# Pinned so a version change busts the Docker layer cache; the Supervisor
# builds without --no-cache, so an unpinned install would stay stale forever.
ARG CLAUDE_CODE_VERSION=2.1.330
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
RUN chmod a+x /usr/bin/claude-entrypoint.sh /usr/bin/tmux-tab-info \
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
