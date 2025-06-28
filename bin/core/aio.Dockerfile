## All in one, multi stage compile + runtime Docker build for your architecture.

########################## Cross Compile Docker Helper Scripts ##########################
## We use the linux/amd64 no matter which Build Platform, since these are all bash scripts
## And these bash scripts do not have any significant difference if at all
FROM --platform=linux/amd64 docker.io/tonistiigi/xx@sha256:9c207bead753dda9430bdd15425c6518fc7a03d866103c516a2c6889188f5894 AS xx

# Build Core
FROM --platform=$BUILDPLATFORM rust:1.88.0-slim-bookworm AS core-builder
COPY --from=xx / /

ENV DEBIAN_FRONTEND=noninteractive

WORKDIR /builder
COPY Cargo.toml Cargo.lock ./
COPY ./lib ./lib
COPY ./client/core/rs ./client/core/rs
COPY ./client/periphery ./client/periphery
COPY ./bin/core ./bin/core

# Fetch dependencies for host arch, rest will be cross compiled
RUN cargo fetch

ARG TARGETARCH
ARG TARGETVARIANT
ARG TARGETPLATFORM

RUN apt-get update && \
    apt-get install -y \
        --no-install-recommends \
        clang \ 
        lld && \
    xx-apt-get install -y \
        --no-install-recommends \
        xx-c-essentials

# Compile app
RUN xx-cargo build -p komodo_core --release && \
    ln -vfsr "/builder/target/$(xx-cargo --print-target-triple)/release/core" /builder/target/release/core

# Build Frontend
FROM --platform=$BUILDPLATFORM node:24.3-bookworm-slim AS frontend-builder
WORKDIR /builder
COPY ./frontend ./frontend
COPY ./client/core/ts ./client
RUN cd client && yarn && yarn build && yarn link
RUN cd frontend && yarn link komodo_client && yarn --network-timeout 1000000 && yarn build

# Final Image
FROM --platform=$TARGETPLATFORM debian:bookworm-slim

COPY ./bin/core/starship.toml /config/starship.toml
COPY ./bin/core/debian-deps.sh .
RUN sh ./debian-deps.sh && rm ./debian-deps.sh

# Setup an application directory
WORKDIR /app

# Copy
COPY ./config/core.config.toml /config/config.toml
COPY --from=frontend-builder /builder/frontend/dist /app/frontend
COPY --from=core-builder /builder/target/release/core /usr/local/bin/core
COPY --from=denoland/deno:bin /deno /usr/local/bin/deno

# Set $DENO_DIR and preload external Deno deps
ENV DENO_DIR=/action-cache/deno
RUN mkdir /action-cache && \
  cd /action-cache && \
  deno install jsr:@std/yaml jsr:@std/toml

# Hint at the port
EXPOSE 9120

# Label for Ghcr
LABEL org.opencontainers.image.source=https://github.com/moghtech/komodo
LABEL org.opencontainers.image.description="Komodo Core"
LABEL org.opencontainers.image.licenses=GPL-3.0

ENTRYPOINT [ "core" ]
