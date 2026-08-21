# rammp-cuda : rammp-base + CUDA PyTorch, for GPU / ML / perception modules.
#
# Same RAMMP-interfaces contract as rammp-base, plus CUDA-enabled torch. Use this
# ONLY for nodes that need the GPU/ML stack; use rammp-base for everything else,
# so lightweight modules don't haul around gigabytes of CUDA.
#
# Build from the REPO ROOT:
#   x86:     make cuda
#   Jetson:  make cuda-jetson JETSON_BASE=<your L4T ROS+PyTorch image>
#
# ── Architecture split (CUDA_BASE build arg) ────────────────────────────────
#   x86_64 (default): CUDA_BASE=rammp-base:<ver>. Inherits the interfaces, then
#       pip-installs CUDA torch from PyPI.
#   Jetson (arm64):   CUDA_BASE=<jetson-containers L4T ROS+PyTorch image matching
#       your JetPack>, e.g. dustynv/ros:humble-pytorch-l4t-r36.2.0 (verify the tag
#       for your JetPack at github.com/dusty-nv/jetson-containers). torch is
#       inherited from that base - NOT fetched from the wheel index that failed
#       before. The interface/Cyclone steps below then add the RAMMP pieces the
#       L4T base doesn't have.
# The interface + Cyclone steps are idempotent: a few seconds of redundant
# rebuild on x86 (already in rammp-base), and genuinely required on the Jetson.
# ────────────────────────────────────────────────────────────────────────────

ARG CUDA_BASE=rammp-base:1.0.0
FROM ${CUDA_BASE}

WORKDIR /ros2_ws

# Cyclone + pip (no-op on rammp-base; needed on a bare L4T base).
RUN apt-get update && \
    apt-get install -y ros-humble-rmw-cyclonedds-cpp python3-pip && \
    rm -rf /var/lib/apt/lists/*
RUN rosdep update --rosdistro humble

# RAMMP-interfaces: inherited already-built on x86 (rebuilds in seconds); built
# from scratch on the Jetson L4T base. Guarantees every rammp-cuda image carries
# the robot contract regardless of which base it started from.
COPY RAMMP-interfaces/ /ros2_ws/src/RAMMP-interfaces/
RUN . /opt/ros/humble/setup.sh && \
    apt-get update && \
    rosdep install --from-paths src --ignore-src -y && \
    rm -rf /var/lib/apt/lists/* && \
    colcon build --symlink-install

# Entrypoint (ensure present when FROM a bare L4T base).
RUN printf '%s\n' \
      '#!/bin/bash' 'set -e' \
      'source /opt/ros/humble/setup.bash' \
      'if [ -f /ros2_ws/install/setup.bash ]; then source /ros2_ws/install/setup.bash; fi' \
      'exec "$@"' \
      > /ros_entrypoint.sh && chmod +x /ros_entrypoint.sh && \
    echo 'source /opt/ros/humble/setup.bash' >> /root/.bashrc && \
    echo 'if [ -f /ros2_ws/install/setup.bash ]; then source /ros2_ws/install/setup.bash; fi' >> /root/.bashrc

# PyTorch: x86 from PyPI (CUDA build); arm64 inherited from the L4T base.
ARG TORCH_X86=2.10.0
ARG TORCHVISION_X86=0.25.0
RUN set -eux; \
    if [ "$(uname -m)" = "x86_64" ]; then \
        pip install --no-cache-dir "torch==${TORCH_X86}" "torchvision==${TORCHVISION_X86}"; \
    else \
        python3 -c "import torch; print('inherited torch', torch.__version__, 'cuda?', torch.cuda.is_available())" \
          || echo "WARNING: no torch in the L4T base image - pick a jetson-containers image that includes PyTorch."; \
    fi

ENTRYPOINT ["/ros_entrypoint.sh"]
CMD ["bash"]
