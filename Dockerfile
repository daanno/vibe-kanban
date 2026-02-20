# ---------------------------------
# BUILD STAGE
# ---------------------------------
FROM node:20-alpine AS builder

# Install build deps
RUN apk add --no-cache \
    curl \
    build-base \
    perl \
    llvm-dev \
    clang-dev \
    git

# Allow linking libclang on musl
ENV RUSTFLAGS="-C target-feature=-crt-static"

# Install Rust
RUN curl https://sh.rustup.rs -sSf | sh -s -- -y
ENV PATH="/root/.cargo/bin:${PATH}"

WORKDIR /app

# Install pnpm
RUN npm install -g pnpm

# Copy dependency manifests first (better caching)
COPY pnpm-lock.yaml pnpm-workspace.yaml package.json ./
COPY frontend/package.json frontend/package.json
COPY remote-frontend/package.json remote-frontend/package.json

RUN pnpm install --frozen-lockfile

# Copy rest of source
COPY . .

# Build frontend
RUN pnpm -C remote-frontend build

# --------------------------------------------------
# REMOVE PRIVATE BILLING DEPENDENCY (SELF-HOSTED)
# --------------------------------------------------
RUN sed -i '/^billing = {.*vibe-kanban-private.*/d' crates/remote/Cargo.toml && \
    sed -i '/^# private crate for billing/d' crates/remote/Cargo.toml && \
    sed -i '/^vk-billing = \["dep:billing"\]/d' crates/remote/Cargo.toml && \
    rm -f crates/remote/Cargo.lock

# Build Rust binary
RUN cargo build --release --manifest-path crates/remote/Cargo.toml

# ---------------------------------
# RUNTIME STAGE
# ---------------------------------
FROM debian:bookworm-slim AS runtime

RUN apt-get update \
  && apt-get install -y --no-install-recommends \
     ca-certificates \
     wget \
     libssl3 \
  && rm -rf /var/lib/apt/lists/* \
  && useradd --system --create-home --uid 10001 appuser

WORKDIR /srv

# Copy compiled binary
COPY --from=builder /app/target/release/remote /usr/local/bin/remote

# Copy built frontend
COPY --from=builder /app/remote-frontend/dist /srv/static

USER appuser

ENV SERVER_LISTEN_ADDR=0.0.0.0:8081
ENV RUST_LOG=info

EXPOSE 8081

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD wget --spider -q http://127.0.0.1:8081/v1/health || exit 1

ENTRYPOINT ["/usr/local/bin/remote"]
