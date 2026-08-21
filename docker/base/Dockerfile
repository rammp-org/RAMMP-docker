# rammp-base : ROS 2 Humble + Cyclone DDS + the RAMMP-interfaces robot contract.
#
# Build from the REPO ROOT (it copies RAMMP-interfaces/, which is at the root):
#   docker build -f docker/base/Dockerfile -t rammp-base:1.0.0 -t rammp-base:humble .
# (the Makefile does this for you: `make base`)
#
# This is the base every non-GPU module builds on. Because RAMMP-interfaces is
# compiled IN, a module repo inherits the robot-level topic/service/action types
# without copying any interface source - the base image is how those definitions
# reach a separate module repo.

FROM ros:humble

WORKDIR /ros2_ws

RUN apt-get update && \
    apt-get install -y ros-humble-rmw-cyclonedds-cpp python3-pip && \
    rm -rf /var/lib/apt/lists/*

RUN rosdep update --rosdistro humble

# The robot-level interface contract, compiled into the base.
# (Until you `git mv` the real packages into RAMMP-interfaces/, this builds an
# empty workspace - colcon just reports "no packages found" and succeeds.)
COPY RAMMP-interfaces/ /ros2_ws/src/RAMMP-interfaces/
RUN . /opt/ros/humble/setup.sh && \
    apt-get update && \
    rosdep install --from-paths src --ignore-src -y && \
    rm -rf /var/lib/apt/lists/* && \
    colcon build --symlink-install

# Entrypoint sources ROS + this workspace (so RAMMP-interfaces is importable);
# .bashrc does the same for interactive `docker exec` shells.
RUN printf '%s\n' \
      '#!/bin/bash' \
      'set -e' \
      'source /opt/ros/humble/setup.bash' \
      'if [ -f /ros2_ws/install/setup.bash ]; then source /ros2_ws/install/setup.bash; fi' \
      'exec "$@"' \
      > /ros_entrypoint.sh && chmod +x /ros_entrypoint.sh && \
    echo 'source /opt/ros/humble/setup.bash' >> /root/.bashrc && \
    echo 'if [ -f /ros2_ws/install/setup.bash ]; then source /ros2_ws/install/setup.bash; fi' >> /root/.bashrc

ENTRYPOINT ["/ros_entrypoint.sh"]
CMD ["bash"]
