## All in one, multi stage compile + runtime Docker build for your architecture.

########################## Cross Compile Docker Helper Scripts ##########################
## We use the linux/amd64 no matter which Build Platform, since these are all bash scripts
## And these bash scripts do not have any significant difference if at all
FROM --platform=linux/amd64 docker.io/tonistiigi/xx@sha256:9c207bead753dda9430bdd15425c6518fc7a03d866103c516a2c6889188f5894 AS xx

FROM --platform=$BUILDPLATFORM rust:1.87.0-slim-bookworm AS builder
COPY --from=xx / /

ENV DEBIAN_FRONTEND=noninteractive

WORKDIR /builder
COPY Cargo.toml Cargo.lock ./
COPY ./lib ./lib
COPY ./client/core/rs ./client/core/rs
COPY ./client/periphery ./client/periphery
COPY ./bin/periphery ./bin/periphery

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
RUN xx-cargo build -p komodo_periphery --release && \
    ln -vfsr "/builder/target/$(xx-cargo --print-target-triple)/release/periphery" /builder/target/release/periphery

# Final Image
FROM --platform=$TARGETPLATFORM debian:bookworm-slim

COPY ./bin/periphery/starship.toml /config/starship.toml
COPY ./bin/periphery/debian-deps.sh .
RUN sh ./debian-deps.sh && rm ./debian-deps.sh

COPY --from=builder /builder/target/release/periphery /usr/local/bin/periphery

EXPOSE 8120

LABEL org.opencontainers.image.source=https://github.com/moghtech/komodo
LABEL org.opencontainers.image.description="Komodo Periphery"
LABEL org.opencontainers.image.licenses=GPL-3.0

CMD [ "periphery" ]
