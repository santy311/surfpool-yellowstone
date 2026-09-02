# Surfpool with the Yellowstone gRPC geyser plugin.
#
# Surfpool itself is the official image rather than a source build. Only the
# geyser plugin is compiled, because rpcpool publishes it for x86_64 only and a
# geyser plugin must match the architecture of the validator that dlopens it.
#
# Sources are fetched as pinned tarballs, not cloned: Debian bookworm ships git
# 2.39.5, which GitHub answers with a 401 auth challenge, and an unpinned clone
# silently tracks a moving branch.

# =============================================================================
# Stage 1: Build the Yellowstone gRPC geyser plugin
# =============================================================================
# Matches rust-toolchain.toml at the pinned yellowstone commit.
FROM rust:1.96-bookworm AS yellowstone-builder

# Install build dependencies
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

# Pinned to the commit the working image was built from; "bump to geyser 4.2.2"
# (958e1403) is its parent, so this matches surfpool v1.5.0's agave version.
ARG YELLOWSTONE_REF=7e9774196b48eaff09e286df84d76ecbd730b882
WORKDIR /build/yellowstone-grpc
RUN curl -fsSL "https://github.com/rpcpool/yellowstone-grpc/archive/${YELLOWSTONE_REF}.tar.gz" \
    | tar xz --strip-components=1

# Build the geyser plugin shared library
RUN cargo build --release -p yellowstone-grpc-geyser

# =============================================================================
# Stage 2: Runtime, on the official Surfpool image
# =============================================================================
FROM surfpool/surfpool:1.5.0 AS runtime

USER root

# Create directories
RUN mkdir -p /geyser

# Copy Yellowstone gRPC geyser plugin shared library
COPY --from=yellowstone-builder /build/yellowstone-grpc/target/release/libyellowstone_grpc_geyser.so /geyser/libyellowstone_grpc_geyser.so

# Copy the default geyser config (can be overridden via volume mount)
COPY config.json /geyser/config.json

# Expose ports:
# - 8899: Solana RPC
# - 8900: WebSocket
# - 10000: Yellowstone gRPC
# - 8999: Prometheus metrics
EXPOSE 8899 8900 10000 8999

# The official entrypoint execs `surfpool "$@"`, so compose's command applies.
CMD ["start", "--network", "devnet", "--no-tui", "--host", "0.0.0.0", "--geyser-plugin-config", "/geyser/config.json"]
