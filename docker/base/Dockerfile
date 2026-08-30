# syntax=docker/dockerfile:1

# rammp-base : ROS 2 Humble + Cyclone DDS + the RAMMP-interfaces robot contract.
#
# linux/arm64 ONLY. The robot's only compute target is a Jetson Orin, so no
# amd64 variant is built or published.
#
# Build from the REPO ROOT (it copies RAMMP-interfaces/ and docker/), on the
# Jetson or on a native arm64 CI runner:
#   make base
#
# This is the base every non-GPU module builds on. Because RAMMP-interfaces is
# compiled IN, a module repo inherits the robot-level topic/service/action types
# without copying any interface source -- the base image is how those
# definitions reach a separate module repo.

FROM ros:humble

ARG VERSION=dev
LABEL org.opencontainers.image.source="https://github.com/rammp-org/RAMMP-docker" \
      org.opencontainers.image.description="ROS 2 Humble + Cyclone DDS + RAMMP-interfaces (Jetson/arm64)" \
      org.opencontainers.image.version="${VERSION}"

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
COPY RAMMP-interfaces/ /ros2_ws/src/RAMMP-interfaces/
RUN . /opt/ros/humble/setup.sh \
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
