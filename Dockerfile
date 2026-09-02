# Surfpool with the Yellowstone gRPC geyser plugin.
#
# Only the plugin is compiled. Surfpool itself is copied out of the official
# image, because rpcpool publishes the plugin for x86_64 only and a geyser
# plugin is dlopen'd into the validator, so it must match its architecture.
#
# Every stage is bookworm on purpose. A geyser plugin also has to match the
# runtime's glibc: built on trixie (2.41) it loads into surfpool's own bullseye
# image (2.31) and fails with "GLIBC_2.32 not found". Surfpool's binary is
# bullseye-built, and older binaries run fine on newer glibc, so bookworm (2.36)
# is the version everything agrees on.

# =============================================================================
# Stage 1: Fetch the pinned source
# =============================================================================
# Bookworm ships git 2.39.5, which GitHub now answers with a 401 auth
# challenge, so the source is fetched by a modern git and carried forward.
# A tarball would avoid git entirely but drops .git, and build.rs calls
# git_version!(), which shells out to `git describe`.
FROM alpine/git:latest AS source

# Pinned to a commit proven against surfpool v1.5.0 rather than the newest tag:
# a geyser ABI mismatch loads cleanly and then fails at runtime. Its parent is
# 958e1403 "bump to geyser 4.2.2".
ARG YELLOWSTONE_REF=7e9774196b48eaff09e286df84d76ecbd730b882
WORKDIR /src
RUN git init -q . \
    && git remote add origin https://github.com/rpcpool/yellowstone-grpc.git \
    && git fetch -q --depth 1 origin "${YELLOWSTONE_REF}" \
    && git checkout -q FETCH_HEAD

# =============================================================================
# Stage 2: Build the geyser plugin
# =============================================================================
FROM rust:1.96-bookworm AS yellowstone-builder

RUN apt-get update && apt-get install -y \
    build-essential \
    pkg-config \
    libssl-dev \
    protobuf-compiler \
    libprotobuf-dev \
    cmake \
    libudev-dev \
    libclang-dev \
    && rm -rf /var/lib/apt/lists/*

# The .git comes with it; bookworm's older git reads it fine for `git describe`.
COPY --from=source /src /build/yellowstone-grpc
WORKDIR /build/yellowstone-grpc

RUN cargo build --release -p yellowstone-grpc-geyser

# =============================================================================
# Stage 3: Runtime
# =============================================================================
FROM debian:bookworm-slim AS runtime

RUN apt-get update && apt-get install -y \
    ca-certificates \
    libssl3 \
    curl \
    && rm -rf /var/lib/apt/lists/*

RUN mkdir -p /geyser

# Surfpool is taken from the official image rather than compiled.
COPY --from=surfpool/surfpool:1.5.0 /bin/surfpool /usr/local/bin/surfpool

COPY --from=yellowstone-builder \
    /build/yellowstone-grpc/target/release/libyellowstone_grpc_geyser.so \
    /geyser/libyellowstone_grpc_geyser.so

# Overridable with a volume mount.
COPY config.json /geyser/config.json

# 8899 RPC, 8900 WebSocket, 10000 Yellowstone gRPC, 8999 Prometheus metrics
EXPOSE 8899 8900 10000 8999

ENTRYPOINT ["/usr/local/bin/surfpool"]
CMD ["start", "--network", "devnet", "--no-tui", "--host", "0.0.0.0", "--geyser-plugin-config", "/geyser/config.json"]
