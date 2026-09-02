# surfpool-grpc

[Surfpool](https://github.com/solana-foundation/surfpool) packaged with the
[Yellowstone gRPC](https://github.com/rpcpool/yellowstone-grpc) geyser plugin,
published as a multi-arch image so consumers do not compile it.

```
ghcr.io/santy311/surfpool-grpc:<tag>
```

| Port | Purpose |
| --- | --- |
| 8899 | Solana RPC |
| 8900 | Solana WebSocket |
| 10000 | Yellowstone gRPC |
| 8999 | Prometheus metrics |

## Why this exists

Surfpool publishes an official image, but it ships no geyser plugin, and rpcpool
publishes the plugin only as an `x86_64` release asset. A geyser plugin is
`dlopen`'d into the validator, so it has to match the host architecture — which
left every arm64 consumer compiling the plugin from source.

This repository compiles the plugin once per architecture in CI and layers it
onto the official surfpool image.

## What is pinned, and why it matters

| Component | Pin |
| --- | --- |
| Surfpool | `surfpool/surfpool:1.5.0` (official image, not a source build) |
| Yellowstone geyser | commit `7e9774196b48eaff09e286df84d76ecbd730b882` |

A geyser plugin is ABI-coupled to the agave version the validator embeds. A
mismatch loads cleanly and then fails at runtime, which is harder to diagnose
than a build error, so the plugin is pinned to a commit proven against this
surfpool version rather than to a tag that merely looks current. The pinned
commit's parent is `958e1403` "bump to geyser 4.2.2".

The builder runs on Debian trixie. Bookworm ships git 2.39.5, which GitHub now
answers with a `401` auth challenge, so the fetch dies before anything builds.
A tarball sidesteps git entirely but breaks the build, which calls
`git_version!()` and needs a real `.git` — so the source is fetched by pinned
commit into a shallow repository instead. The build this replaces cloned an
unpinned branch and had tracked yellowstone master for eight months.

## Publishing a new version

Bump `YELLOWSTONE_REF` or the surfpool base in the `Dockerfile`, then:

```
git tag v1.5.0-geyser-<short-sha>
git push --tags
```

The workflow builds `linux/amd64` and `linux/arm64` on native runners and merges
them into one tag. `workflow_dispatch` also works for a test build.

## Consuming it

```yaml
services:
  surfpool:
    image: ghcr.io/santy311/surfpool-grpc:v1.5.0-geyser-7e97741
    command: ["start", "--host", "0.0.0.0", "--geyser-plugin-config", "/geyser/config.json"]
```

The plugin config lives at `/geyser/config.json` and can be replaced with a
volume mount.
