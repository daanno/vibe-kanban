# -----------------------------
# Build stage
# -----------------------------
FROM node:20-bookworm AS builder

# Install system dependencies
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        curl \
        build-essential \
        pkg-config \
        libssl-dev \
        git \
    && rm -rf /var/lib/apt/lists/*

# Install Rust
RUN curl https://sh.rustup.rs -sSf | sh -s -- -y
ENV PATH="/root/.cargo/bin:${PATH}"

WORKDIR /app

# Install pnpm
RUN npm install -g pnpm

# Copy dependency manifests first (for layer caching)
COPY pnpm-lock.yaml pnpm-workspace.yaml package.json ./
COPY frontend/package.json frontend/package.json
COPY remote-frontend/package.json remote-frontend/package.json

RUN pnpm install --frozen-lockfile

# Copy full source
COPY . .

# Build frontend
RUN pnpm -C remote-frontend build

# 🔥 Build Rust backend with ALL features enabled
RUN cargo build --release \
    --manifest-path crates/remote/Cargo.toml \
    --bin remote \
    --all-features

# -----------------------------
# Runtime stage
# -----------------------------
FROM debian:bookworm-slim AS runtime

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        ca-certificates \
        wget \
        libssl3 \
    && rm -rf /var/lib/apt/lists/* \
    && useradd --system --create-home --uid 10001 appuser

WORKDIR /srv

# Copy compiled backend binary
COPY --from=builder /app/target/release/remote /usr/local/bin/remote

# Copy built frontend
COPY --from=builder /app/remote-frontend/dist /srv/static

USER appuser

# Railway provides PORT automatically
ENV HOST=0.0.0.0

EXPOSE 8080

ENTRYPOINT ["/usr/local/bin/remote"]
