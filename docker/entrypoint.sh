#!/bin/bash
# Entrypoint for every RAMMP image.
#
# Sources three layers in order, each optional after the first:
#   1. /opt/ros/humble      the ROS 2 underlay
#   2. /ros2_ws/install     RAMMP-interfaces, the robot-level contract
#   3. /module_ws/install   the module's own packages, if this is a module image
#
# Layer 3 is the extension point for module repos: a module builds into its own
# workspace rather than rebuilding the base's interfaces from source, which
# keeps module builds fast and makes it impossible for a module to accidentally
# ship a modified copy of the robot contract.
set -e

source /opt/ros/humble/setup.bash

# Guarded with if/then rather than `[ -f x ] && source x`, which would abort
# the whole script under `set -e` whenever the optional file is absent.
if [ -f /ros2_ws/install/setup.bash ]; then
    source /ros2_ws/install/setup.bash
fi

if [ -f /module_ws/install/setup.bash ]; then
    source /module_ws/install/setup.bash
fi

exec "$@"
