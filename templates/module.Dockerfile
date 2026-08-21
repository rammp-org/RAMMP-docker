# Template Dockerfile for a RAMMP module repo.
#
# Copy this to your module repo root as `Dockerfile`, replace <your_module>, and
# set the run command. Also copy templates/dockerignore.txt to `.dockerignore`.
#
# The base image already contains ROS 2 Humble, Cyclone, and RAMMP-interfaces
# (the robot-level contract), so this copies ONLY your own repo - your node plus
# any task-specific interface package this repo defines. No interface source is
# copied from anywhere else; the robot interface comes from the base image.

# Pin an explicit base VERSION (not the floating :humble) so this image records
# exactly which robot-interface version it was built against - that pin is what
# prevents silent type-mismatch drift across independently-built module repos.
#
# Use rammp-cuda ONLY if your node needs CUDA/torch; otherwise use rammp-base
# (much smaller). If you use rammp-cuda, REMOVE torch/torchvision from your
# requirements.txt - the base already provides them.
FROM ghcr.io/rammp-org/rammp-cuda:1.0.0

# Copy this repo into the workspace. colcon finds every package.xml under here,
# so both your node package and any task-interface package in this repo build.
COPY . /ros2_ws/src/<your_module>/

RUN . /opt/ros/humble/setup.sh && \
    apt-get update && \
    rosdep install --from-paths src --ignore-src -y && \
    rm -rf /var/lib/apt/lists/* && \
    colcon build --symlink-install

# Your node's launch file (or `ros2 run <pkg> <exe>`). Override per module.
CMD ["ros2", "launch", "<your_module>", "<your_module>.launch.py"]
