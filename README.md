# RAMMP Docker Base Images

The base Docker images every RAMMP module builds on: ROS 2 Humble, Cyclone DDS,
and the RAMMP robot interface contract. This repository is the foundation of our
software system — each module lives in its own repository and builds its
container `FROM` one of these published base images.

> **These images are `linux/arm64` only.** The robot's only compute target is an
> NVIDIA Jetson Orin, so no amd64 variant is built or published. Build and test
> them [on the Jetson](#building-and-testing-on-the-jetson), or let CI build
> them on native arm64 runners.

## Target hardware

| | |
|---|---|
| Module | Jetson Orin NX (Seeed reComputer J4012) → Orin AGX |
| SoC | Tegra234, compute capability **sm_87** |
| JetPack | 6.1 / 6.2 (L4T **r36.4.x**) |
| CUDA | 12.6 |
| OS in image | Ubuntu 22.04, Python 3.10 |

Orin NX and AGX Orin are the same SoC at the same compute capability, so **one
image serves both** and a result obtained on an NX carries to an AGX. Two things
do not carry: serialized TensorRT engines, which are device-specific and must be
rebuilt on the target, and anything memory-bound, since the NX has considerably
less RAM.

## In the registry

```bash
docker pull ghcr.io/rammp-org/rammp-base:humble   # latest lightweight base
docker pull ghcr.io/rammp-org/rammp-cuda:humble   # latest CUDA base
```

Or reference it in a module's `Dockerfile`:

```dockerfile
FROM ghcr.io/rammp-org/rammp-cuda:1.0.0
```

## The two images

### `rammp-base`

ROS 2 Humble, Cyclone DDS (selected, not merely installed), and
`RAMMP-interfaces` compiled in. Use this for **hardware drivers and light sensor
nodes** — anything that doesn't need the GPU.

### `rammp-cuda`

Everything in `rammp-base`, plus the CUDA 12.6 runtime libraries and
CUDA-enabled PyTorch. **Only use it if your node needs the GPU**; it is several
gigabytes larger.

It is built `FROM rammp-base`, so both images share one lineage and the
interface contract is identical by construction rather than by convention. CUDA
comes from NVIDIA's Tegra apt repository and PyTorch from the
`pypi.jetson-ai-lab.io` aarch64 wheel index.

The image ships CUDA **runtime libraries but no driver** — `libcuda.so` is
injected by the Jetson's container runtime. That means any `rammp-cuda`
container **must** be run with `--runtime nvidia`; without it,
`torch.cuda.is_available()` returns `False`.

If you build a module `FROM rammp-cuda`, remove `torch`/`torchvision` from that
module's `requirements.txt`. Reinstalling them from PyPI replaces the
Jetson-specific wheels with ones that cannot drive the GPU.

## Running on the robot

```bash
docker run --rm --runtime nvidia --network host --ipc host \
  ghcr.io/rammp-org/rammp-cuda:1.0.0
```

- `--runtime nvidia` — required for every `rammp-cuda` image (see above).
- `--network host` — required for DDS discovery. On a bridge network Cyclone
  binds the bridge interface and nodes in other containers never find each
  other. This is the single most common ROS-in-Docker failure.
- `--ipc host` — lets Cyclone use shared-memory transport between containers.

The images set `RMW_IMPLEMENTATION=rmw_cyclonedds_cpp` and point
`CYCLONEDDS_URI` at `/etc/cyclonedds/config.xml`. Override it by mounting your
own file and setting the variable.

## This repo contains

- **`RAMMP-interfaces/`** — the robot contract: `arm_interfaces` and
  `rammp_prototype_interfaces`, each its own colcon package. Task-specific
  interfaces do **not** live here; they live in their own module repos.
- **`docker/`** — the Dockerfiles, the shared entrypoint, and the default
  Cyclone DDS configuration.
- **`templates/`** — `module.Dockerfile` and `dockerignore.txt` for a new module.
- **`scripts/smoke-test.sh`** — verifies a built image. One script; it skips
  the GPU checks when there is no GPU, so CI and the robot run the same tests.
- **`.github/workflows/`** — CI that builds both images on native arm64 runners
  and publishes them on a version tag.

## Versioning

- **A pinned version**, e.g. `rammp-cuda:1.0.0` — immutable. **Pin this in your
  module's `FROM`.** It records exactly which interface version your module was
  built against, which is what stops independently-built module repos from
  drifting out of sync. Mismatched interface versions make topics and actions
  quietly stop working.
- **A floating tag**, `rammp-cuda:humble` — always the latest release.
  Convenient, but it *moves*, and Docker will happily reuse a stale cached copy.
  Refresh with `docker pull` or `docker build --pull`.

When `RAMMP-interfaces` or the base setup changes, bump `VERSION`, tag a
release, and rebuild the modules against the new version. That
rebuild-on-change step is the price of baking interfaces into the base; it is
acceptable only because the robot contract changes rarely.

## Building and testing on the Jetson

```bash
git clone https://github.com/rammp-org/RAMMP-docker.git
cd RAMMP-docker

make base          # rammp-base:1.0.0 (+ :humble)
make cuda          # rammp-cuda:1.0.0 (+ :humble)
make test          # smoke-test both images
```

Plain `docker build`, so no buildx plugin is needed on the robot. The first
build pulls `ros:humble` and the CUDA packages, so allow time and a few GB of
disk.

`make test` runs `scripts/smoke-test.sh` against each image. It checks that the
image is arm64, that Cyclone is the selected middleware, that all eleven
interface types resolve and import, and — on the Jetson — that
`torch.cuda.is_available()` is true, that the GPU reports **sm_87**, that a
matmul and a cuDNN convolution actually execute, and that two containers can
discover each other over DDS.

The same script runs in CI, where it automatically skips the GPU section
because a hosted runner has no GPU. That split is the whole point: CI proves
the images *build* and that the CUDA and PyTorch stacks install and link, and
the Jetson proves CUDA *runs*.

## Publishing

Tag a release and CI does the rest — it builds both images on GitHub's native
arm64 runners, smoke-tests them, and pushes to GHCR:

```bash
git tag v1.0.0
git push origin v1.0.0
```

Pushes to `main` build and test but publish nothing, so only a tag can change
what is in the registry. To publish by hand from the Jetson instead:

```bash
docker login ghcr.io
make push
```

## Creating a new module (in its own repo)

1. Copy `templates/module.Dockerfile` to your module repo root as `Dockerfile`,
   and `templates/dockerignore.txt` to `.dockerignore`.
2. Replace `<your_module>`, pick the base (`rammp-base` unless you need the
   GPU), and **pin the version** in `FROM`.
3. Put your node package — and any task-specific interface package — in the
   repo. They build automatically into `/module_ws`, an overlay on top of the
   base; the robot interface comes from the base image and is not rebuilt.
4. Set the `CMD` to your launch file or `ros2 run` target.
