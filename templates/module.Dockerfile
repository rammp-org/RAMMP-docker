# syntax=docker/dockerfile:1

# Template Dockerfile for a RAMMP module repo.
#
# Copy this to your module repo root as `Dockerfile`, replace every
# <your_module>, and set the run command. Also copy templates/dockerignore.txt
# to `.dockerignore`.
#
# The base image already contains ROS 2 Humble, Cyclone DDS, and
# RAMMP-interfaces (the robot-level contract), so this copies ONLY your own
# repo -- your node plus any task-specific interface package this repo defines.
# No interface source is copied from anywhere else.

# ── Pick and pin your base ──────────────────────────────────────────────────
# Pin an explicit VERSION, not the floating :humble tag, so this image records
# exactly which robot-interface version it was built against. That pin is what
# prevents silent type-mismatch drift between independently-built module repos.
#
# Use rammp-cuda ONLY if your node needs the GPU; rammp-base is far smaller.
# If you use rammp-cuda, REMOVE torch/torchvision from your requirements.txt --
# the base already provides them, and reinstalling from PyPI would replace the
# Jetson-specific wheels with ones that cannot use the GPU.
#
# These images are arm64/Jetson only -- build your module on the Jetson, or on
# a native arm64 CI runner.
FROM ghcr.io/rammp-org/rammp-cuda:1.0.0

# ── Build your packages into their own overlay ──────────────────────────────
# /module_ws is a separate workspace layered on top of the base's /ros2_ws. The
# entrypoint sources it automatically. Building here rather than into /ros2_ws
# means your build does not recompile the robot interfaces (much faster) and
# cannot accidentally ship a modified copy of them.
WORKDIR /module_ws

COPY . /module_ws/src/<your_module>/

# colcon finds every package.xml under src/, so both your node package and any
# task-specific interface package in this repo are built.
RUN . /opt/ros/humble/setup.sh \
    && . /ros2_ws/install/setup.sh \
    && apt-get update \
    && rosdep install --from-paths src --ignore-src -y \
    && rm -rf /var/lib/apt/lists/* \
    && colcon build \
    && rm -rf /module_ws/build /module_ws/log

# Your node's launch file (or `ros2 run <pkg> <exe>`). Override per module.
CMD ["ros2", "launch", "<your_module>", "<your_module>.launch.py"]

# ── Running on the robot ────────────────────────────────────────────────────
#   docker run --rm --runtime nvidia --network host --ipc host \
#     ghcr.io/rammp-org/<your_module>:<version>
#
#   --runtime nvidia  required for any rammp-cuda image. The image ships CUDA
#                     runtime libraries but no driver; the driver is injected
#                     by the Jetson's container runtime. Omit it and
#                     torch.cuda.is_available() is False.
#   --network host    required for DDS discovery. On a bridge network Cyclone
#                     binds the bridge interface and nodes in other containers
#                     never discover each other.
#   --ipc host        lets Cyclone use shared memory between containers.
