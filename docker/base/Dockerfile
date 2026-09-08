# syntax=docker/dockerfile:1

# rammp-base : ROS 2 Humble + Cyclone DDS + the RAMMP interface contract.
#
# linux/arm64 is what is PUBLISHED -- the robot's compute target is a Jetson
# Orin. Nothing here is arm64-specific, so it builds on amd64 too; publishing
# both is tracked separately.
#
# Build from the REPO ROOT (it copies docker/), on the Jetson or on a native
# arm64 CI runner:
#   make base
#
# This is the base every non-GPU module builds on. Because the interfaces are
# compiled IN, a module repo inherits the robot-level topic/service/action types
# without copying any interface source -- the base image is how those
# definitions reach a separate module repo.

FROM ros:humble

ARG VERSION=dev
ARG INTERFACES_VERSION=unknown
LABEL org.opencontainers.image.source="https://github.com/rammp-org/RAMMP-docker" \
      org.opencontainers.image.description="ROS 2 Humble + Cyclone DDS + rammp-interfaces-ros2" \
      org.opencontainers.image.version="${VERSION}" \
      org.rammp.interfaces="${INTERFACES_VERSION}"
# org.rammp.interfaces is the rammp-interfaces-ros2 REF that was compiled in.
# It is the repo tag, which is a checkout coordinate -- individual packages
# carry their own <version> and can differ from it. It is a label, not part of
# the tag, so `docker inspect` answers it without the tag encoding everything.

# Build-time only: ARG rather than ENV so the setting does not leak into the
# runtime environment of every downstream module.
ARG DEBIAN_FRONTEND=noninteractive

WORKDIR /ros2_ws

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
         ros-humble-rmw-cyclonedds-cpp \
         python3-pip \
         curl \
         ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Actually select Cyclone. Installing the RMW package alone does nothing -- ROS
# 2 defaults to Fast DDS unless RMW_IMPLEMENTATION says otherwise.
COPY docker/cyclonedds.xml /etc/cyclonedds/config.xml
ENV RMW_IMPLEMENTATION=rmw_cyclonedds_cpp \
    CYCLONEDDS_URI=file:///etc/cyclonedds/config.xml

# The robot-level interface contract, compiled into the base.
#
# Fetched from rammp-interfaces-ros2 at a PINNED tag, not vendored here. One
# repo owns the contract, and every image that compiles it in names the exact
# version it compiled -- so "which contract does this image speak" is answered
# by a tag rather than by whatever happened to be committed in this repo.
#
# A tarball rather than a clone: the repo is public and curl is already
# installed above, so this needs neither git nor vcstool in the image, and no
# .git directory lands in a layer.
ARG INTERFACES_REF=v1.0.0
RUN mkdir -p /ros2_ws/src/rammp-interfaces-ros2 \
    && curl -fsSL "https://github.com/rammp-org/rammp-interfaces-ros2/archive/refs/tags/${INTERFACES_REF}.tar.gz" \
       | tar xz -C /ros2_ws/src/rammp-interfaces-ros2 --strip-components=1 \
    && . /opt/ros/humble/setup.sh \
    && apt-get update \
    && rosdep update --rosdistro humble \
    && rosdep install --from-paths src --ignore-src -y \
    && colcon build \
    && rm -rf /ros2_ws/build /ros2_ws/log /var/lib/apt/lists/* /root/.ros

# Note: plain `colcon build`, NOT --symlink-install. A published base image must
# survive having build/ removed; --symlink-install leaves install/ pointing into
# build/ and src/, so pruning either one silently breaks every downstream image.

COPY docker/entrypoint.sh /ros_entrypoint.sh
RUN chmod +x /ros_entrypoint.sh \
    && printf '%s\n' \
         'source /opt/ros/humble/setup.bash' \
         'if [ -f /ros2_ws/install/setup.bash ]; then source /ros2_ws/install/setup.bash; fi' \
         'if [ -f /module_ws/install/setup.bash ]; then source /module_ws/install/setup.bash; fi' \
         >> /root/.bashrc

ENTRYPOINT ["/ros_entrypoint.sh"]
CMD ["bash"]
