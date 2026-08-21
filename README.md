# RAMMP Docker Base Images

The base Docker images every RAMMP module builds on, which include ROS2 Humble, Cyclone DDS, and the ROS2 interface for RAMMP. This repository is the foundation of our software system: each module lives in its own repository and builds its container `FROM` one of these published base images.

## In the registry

The images are published to GitHub Container Registry and pulled to build off of them.

Pull one directly:

```bash
docker pull ghcr.io/rammp-org/rammp-cuda:humble      # latest CUDA base
docker pull ghcr.io/rammp-org/rammp-base:humble      # latest lightweight base
```

Or reference it in a module's `Dockerfile`:

```dockerfile
FROM ghcr.io/rammp-org/rammp-cuda:1.0.0
```

## Base image (`rammp-base`)

- ROS 2 Humble
- Cyclone DDS
- `RAMMP-interfaces`

Portable across JetPack versions and builds natively on x86 and arm64. Use this
for **hardware drivers and light/sensor nodes** — anything that doesn't need the
GPU.

## CUDA image (`rammp-cuda`)

- Everything in `rammp-base`, **plus** CUDA-enabled PyTorch
- **Only use if your node needs CUDA/torch.** Otherwise use `rammp-base`

If you build a module `FROM rammp-cuda`, remove `torch`/`torchvision` from that
module's `requirements.txt` — the base already provides them.

## This repo contains

- **`RAMMP-interfaces/`** — the robot contract: `arm_interfaces` and
  `rammp_prototype_interfaces` (each its own colcon package). See
  `RAMMP-interfaces/README.md`. Task-specific interfaces do **not** live here;
  they live in their own module repos.
- **`docker/`** — the versioned Dockerfiles (`base/`, `cuda/`).
- **`templates/`** — `module.Dockerfile` and `dockerignore.txt` for creating a
  new module repo.
- **`.github/workflows/`** — CI to build and push the images on a version tag.

## Versioning — and keeping current

Images carry two kinds of tag:

- **A pinned version**, e.g. `rammp-cuda:1.0.0` — immutable. **Pin this in your
  module `FROM`.** It records exactly which robot-interface version your module
  was built against, which is what keeps independently-built module repos from
  silently drifting out of sync (mismatched interface versions cause actions and
  topics to quietly stop working).
- **A floating tag**, `rammp-cuda:humble` — always points at the latest release.
  Convenient for a quick pull, but it *moves*.

> **Ensure you always have the latest base image — if not, repull.**
> If you build against the floating `:humble` tag, Docker will happily reuse a
> stale cached copy. Run `docker pull ghcr.io/rammp-org/rammp-cuda:humble` (or
> `docker build --pull`) to refresh it. Better: pin a version and bump it
> deliberately when you intend to move.

When `RAMMP-interfaces` or the base setup changes, bump `VERSION`, rebuild and
repush the base images, then rebuild the modules against the new version. That
rebuild-on-change step is the price of baking interfaces into the base — it's
acceptable only because the robot contract changes rarely.

## Building and publishing

```bash
# x86 dev box
make base            # rammp-base:1.0.0 (+ :humble)
make cuda            # rammp-cuda:1.0.0 (+ :humble)

# Jetson (set JETSON_BASE to the L4T ROS+PyTorch image for your JetPack)
make cuda-jetson JETSON_BASE=dustynv/ros:humble-pytorch-l4t-r36.2.0

# publish (after `docker login ghcr.io`)
make push-base
make push-cuda
```

CI publishes the amd64 images automatically on a `v*` tag. The arm64 (Jetson)
images must be built and pushed **from a Jetson** — cloud runners can't build
them — and combined with the amd64 images into one multi-arch tag. The workflow
file documents the exact steps.

## Creating a new module (in its own repo)

1. Copy `templates/module.Dockerfile` to your module repo root as `Dockerfile`,
   and `templates/dockerignore.txt` to `.dockerignore`.
2. Set `<your_module>`, pick the base (`rammp-base` unless you need CUDA), and
   **pin the version** in `FROM`.
3. Put your node package — and any task-specific interface package — in the repo.
   They build automatically; the robot interface comes from the base image.
4. Set the `CMD` to your launch file or `ros2 run` target.
