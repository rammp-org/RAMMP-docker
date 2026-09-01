# syntax=docker/dockerfile:1

# rammp-cuda : rammp-base + CUDA 12.6 runtime + PyTorch, for GPU/perception nodes.
#
# JETSON (linux/arm64) ONLY. There is no amd64 variant.
#
# Target hardware: Jetson Orin (NX or AGX) on JetPack 6.1/6.2, L4T r36.4.x.
# Both Orin modules are the same Tegra234 SoC at compute capability sm_87, so a
# single image serves both -- an image validated on an Orin NX is valid on an
# AGX Orin. (What does NOT transfer between them: serialized TensorRT engines,
# which are device-specific and must be rebuilt on the target.)
#
# Build from the REPO ROOT, after `make base`:
#   make cuda
#
# ── How the GPU stack is assembled ──────────────────────────────────────────
# Same lineage as every other RAMMP image: FROM rammp-base, so the ROS 2 and
# RAMMP-interfaces layers are shared and the interface contract is identical by
# construction rather than by convention.
#
# CUDA comes from NVIDIA's Tegra apt repo (repos/ubuntu2204/arm64 -- the arm64
# tree is Tegra/Jetson; sbsa is server ARM and is NOT interchangeable). We
# install the RUNTIME libraries only (cuda-libraries + the extra libs the
# torch wheels hard-link -- see the apt step):
#   * not cuda-toolkit  -- nvcc and headers are build tooling no runtime needs,
#     and they roughly triple the image size.
#   * no driver package -- libcuda.so is injected at run time by the Jetson's
#     nvidia container runtime. A driver baked into the image would collide
#     with the one the host mounts.
# Hence this image MUST be run with `--runtime nvidia` on the Jetson; without
# it there is no libcuda.so and torch.cuda.is_available() returns False.
#
# PyTorch comes from the jetson-ai-lab index, which serves aarch64 wheels built
# against CUDA 12.6 for Python 3.10 (matching Ubuntu 22.04 / ROS Humble).
# NOTE the host: pypi.jetson-ai-lab.IO. The old .dev domain is dead and is the
# likely reason an earlier attempt at this approach failed.
# ────────────────────────────────────────────────────────────────────────────

ARG VERSION=dev
FROM rammp-base:${VERSION}

ARG VERSION
LABEL org.opencontainers.image.source="https://github.com/rammp-org/RAMMP-docker" \
      org.opencontainers.image.description="rammp-base + CUDA 12.6 runtime + PyTorch (Jetson Orin, JetPack 6.1/6.2)" \
      org.opencontainers.image.version="${VERSION}"

ARG DEBIAN_FRONTEND=noninteractive

# Pinned so a rebuild six months from now produces the same stack. To move the
# GPU stack, change these -- nothing else in the file should need touching.
ARG CUDA_SERIES=12-6
ARG CUDA_DOTTED=12.6
ARG CUDA_VERSION=12.6.3-1
ARG CUPTI_VERSION=12.6.80-1
ARG CUDSS_VERSION=0.8.0.10-1
ARG CUDNN_VERSION=9.20.0.48-1
ARG TORCH_VERSION=2.10.0
ARG TORCHVISION_VERSION=0.25.0
ARG NUMPY_VERSION=1.26.4
ARG JETSON_PIP_INDEX=https://pypi.jetson-ai-lab.io/jp6/cu126

# Exact component versions as labels (org.rammp.interfaces is inherited from
# rammp-base). The image TAG only carries <semver>-jp<N>; everything finer
# lives here, where `docker inspect` can read it:
#   docker inspect --format '{{json .Config.Labels}}' rammp-cuda:<tag>
LABEL org.rammp.jetpack="6 (L4T r36.4)" \
      org.rammp.cuda="${CUDA_VERSION}" \
      org.rammp.cudnn="${CUDNN_VERSION}" \
      org.rammp.torch="${TORCH_VERSION}"

# Fail loudly and early rather than producing a broken amd64 image.
RUN if [ "$(uname -m)" != "aarch64" ]; then \
        echo "ERROR: rammp-cuda is Jetson/arm64 only, but this build is $(uname -m)." >&2; \
        echo "       Build it on the Jetson, or on a native arm64 runner." >&2; \
        exit 1; \
    fi

RUN curl -fsSL -o /tmp/cuda-keyring.deb \
      "https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2204/arm64/cuda-keyring_1.1-1_all.deb" \
    && dpkg -i /tmp/cuda-keyring.deb \
    && rm -f /tmp/cuda-keyring.deb \
    && apt-get update \
    && apt-get install -y --no-install-recommends \
         "cuda-libraries-${CUDA_SERIES}=${CUDA_VERSION}" \
         "cuda-cupti-${CUDA_SERIES}=${CUPTI_VERSION}" \
         "libcudss0-cuda-12=${CUDSS_VERSION}" \
         "libcudnn9-cuda-12=${CUDNN_VERSION}" \
         libopenblas0 \
         libnuma1 \
         libatomic1 \
         libjpeg-turbo8 \
         libpng16-16 \
    && rm -rf /var/lib/apt/lists/*

# Everything above is a hard link-time dependency of the jetson-ai-lab torch/
# torchvision wheels (verified with readelf against the exact pinned wheels):
# cuda-libraries is not enough on its own -- libtorch_cpu links CUPTI and
# libtorch_cuda links cuDSS, neither of which cuda-libraries provides, and
# torchvision links the system libjpeg/libpng.

# cuda-libraries installs to a versioned prefix and does not create the
# conventional /usr/local/cuda symlink (that comes with cuda-toolkit), so make
# it ourselves -- plenty of downstream code assumes CUDA_HOME=/usr/local/cuda.
ENV CUDA_HOME=/usr/local/cuda
RUN ln -sfn "/usr/local/cuda-${CUDA_DOTTED}" /usr/local/cuda \
    && printf '%s\n' \
         "/usr/local/cuda/lib64" \
         "/usr/lib/aarch64-linux-gnu/libcudss/12" \
         > /etc/ld.so.conf.d/000_cuda.conf \
    && ldconfig
# The cudss entry is required: its deb installs into that subdirectory but
# registers no loader path of its own, and the torch libs' RUNPATH is only
# $ORIGIN, so without this line libcudss.so.0 is unresolvable.
# Registered with ldconfig rather than prepended to LD_LIBRARY_PATH: when that
# variable is unset, "$CUDA/lib64:${LD_LIBRARY_PATH}" expands with a trailing
# colon, which the loader reads as "also search the current directory".

# Two-step install, and the order is load-bearing.
#
# Step 1 -- torch/torchvision from the jetson index ALONE, --no-deps. pip
# gives --index-url no priority over --extra-index-url: every index's
# candidates compete, and for the same version the tie is broken by wheel-tag
# specificity, where PyPI's manylinux_2_28_aarch64 outranks the jetson
# wheels' plain linux_aarch64 tag. With pypi.org in the same command, PyPI's
# aarch64 torch -- a CPU-only build -- silently wins. So the CUDA wheels are
# installed with no competing index in sight.
RUN pip install --no-cache-dir --no-deps \
      --index-url "${JETSON_PIP_INDEX}" \
      "torch==${TORCH_VERSION}" \
      "torchvision==${TORCHVISION_VERSION}"

# Step 2 -- their dependencies (pure-Python, safe from anywhere). torch and
# torchvision are already satisfied at these exact pins, so pip does not
# touch them; it only fills in what --no-deps skipped.
#
# numpy is pinned EXPLICITLY even though the wheels only ask for "numpy": the
# base image carries jammy's apt numpy 1.21 (a ROS dependency), which pip
# accepts as satisfying that requirement and torch then imports. That numpy
# resolves BLAS through the system alternatives, which the libopenblas0
# install above switches to jammy's OpenBLAS 0.3.20 -- broken on some arm64
# CPUs (numpy's own sanity check fails on GitHub's Neoverse runners). The
# pip numpy lands in /usr/local, shadows the apt one, and bundles its own
# BLAS, so it behaves the same everywhere.
RUN pip install --no-cache-dir \
      --index-url "${JETSON_PIP_INDEX}" \
      --extra-index-url https://pypi.org/simple \
      "torch==${TORCH_VERSION}" \
      "torchvision==${TORCHVISION_VERSION}" \
      "numpy==${NUMPY_VERSION}"

# Build-time sanity check. Importing torch and reading the CUDA it was compiled
# against needs no GPU, so this runs on a GPU-less CI runner and still catches
# the common failures: wrong wheel arch, missing cuDNN, broken linkage.
# Whether CUDA actually *runs* can only be checked on the Jetson --
# scripts/smoke-test.sh does that.
RUN python3 -c "\
import numpy, torch, torchvision; \
assert numpy.__file__.startswith('/usr/local/'), f'apt numpy shadowed pip numpy: {numpy.__file__}'; \
print('numpy', numpy.__version__, 'from', numpy.__file__); \
print('torch', torch.__version__, '/ torchvision', torchvision.__version__); \
print('compiled against CUDA', torch.version.cuda, '/ cuDNN', torch.backends.cudnn.version()); \
assert torch.version.cuda == '${CUDA_DOTTED}', f'torch built for CUDA {torch.version.cuda}, expected ${CUDA_DOTTED} -- wrong wheel source'"

ENTRYPOINT ["/ros_entrypoint.sh"]
CMD ["bash"]
