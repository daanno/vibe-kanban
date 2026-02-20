############################
# Builder stage
############################
FROM node:20-alpine AS builder

# Install system deps (including OpenSSL for Rust)
RUN apk add --no-cache \
    curl \
    build-base \
    perl \
    llvm-dev \
    clang-dev \
    git \
    openssl-dev \
    pkgconfig \
    musl-dev

# Install Rust
RUN curl https://sh.rustup.rs -sSf | sh -s -- -y
ENV PATH="/root/.cargo/bin:${PATH}"

WORKDIR /app

# Install pnpm
RUN npm install -g pnpm

# Copy workspace files
COPY pnpm-lock.yaml pnpm-workspace.yaml package.json ./
COPY frontend/package.json frontend/package.json
COPY remote-frontend/package.json remote-frontend/package.json

# Install JS deps
RUN pnpm install --frozen-lockfile

# Copy full repo
COPY . .

# Build frontend
RUN pnpm -C remote-frontend build

# Remove private billing crate references
RUN sed -i '/^billing = {.*vibe-kanban-private.*/d' crates/remote/Cargo.toml && \
    sed -i '/^# private crate for billing/d' crates/remote/Cargo.toml && \
    sed -i '/^vk-billing = \["dep:billing"\]/d' crates/remote/Cargo.toml && \
    rm -f crates/remote/Cargo.lock

# Build Rust binary
RUN cargo build --release --manifest-path crates/remote/Cargo.toml

############################
# Runtime stage
############################
FROM debian:bookworm-slim AS runtime

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        ca-certificates \
        wget \
        libssl3 && \
    rm -rf /var/lib/apt/lists/* && \
    useradd --system --create-home --uid 10001 appuser

WORKDIR /srv

COPY --from=builder /app/target/release/remote /usr/local/bin/remote
COPY --from=builder /app/remote-frontend/dist /srv/static

USER appuser

EXPOSE 8080

CMD ["remote"]
