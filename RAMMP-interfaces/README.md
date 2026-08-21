# RAMMP-interfaces

The **robot-level** interface contract: the messages, services, and actions for
the shared hardware and sensors that every module talks to. Compiled into the
base images, so any module that builds `FROM` a base image inherits these types
without copying interface source.

This holds exactly two packages, each kept as its own colcon package:

- `arm_interfaces/`
- `rammp_prototype_interfaces/`

## What does NOT go here

Task-specific interfaces (e.g. `cmu_door_opener_interfaces`, the drink action)
live in their **own module repos**, built alongside the node that owns them.
Only the stable, robot-wide contract belongs here — the part that changes rarely.
