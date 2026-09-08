# Build and publish the RAMMP base images.
#
# These images are linux/arm64 ONLY -- the robot's only compute target is a
# Jetson Orin. There is no amd64 variant, so there are no multi-arch manifests
# to combine and no architecture-suffixed tags: one platform, one tag.
#
# Run these ON THE JETSON (or let CI do it). Plain `docker build`, so no buildx
# plugin is required on the robot.
#
# VERSION is <semver>-jp<N>, e.g. 1.2.0-jp6. The semver tracks the interface
# contract and base setup: major/minor for interface-contract changes, patch for
# base plumbing. The -jp suffix names the JetPack generation the image runs on
# (jp6 = JetPack 6.1+ on L4T r36.4+; NOT 6.0, whose driver predates CUDA 12.6)
# and changes only when the robot moves to a new JetPack. Bump it, tag a
# release (git tag v1.2.0-jp6), and modules pin the full version in their FROM.

REGISTRY ?= ghcr.io/rammp-org
VERSION  ?= 1.0.0-jp6
DISTRO   ?= humble

# The rammp-interfaces-ros2 tag compiled into the image. Change this to move
# the contract; it is recorded as an OCI label (org.rammp.interfaces) so
# `docker inspect` answers "which contract is in this image" without the image
# tag having to encode it.
#
# It is the REPO tag, which is a checkout coordinate. Individual packages carry
# their own <version> and may differ from it -- see that repo's README.
INTERFACES_REF ?= v1.0.0

# Both images build from the REPO ROOT because they copy docker/.
BUILD = docker build --build-arg VERSION=$(VERSION) \
                     --build-arg INTERFACES_REF=$(INTERFACES_REF) \
                     --build-arg INTERFACES_VERSION=$(INTERFACES_REF)

.PHONY: help base cuda test push clean

help:
	@echo "RAMMP base images -- arm64/Jetson only (VERSION=$(VERSION))"
	@echo
	@echo "  make base    build rammp-base:$(VERSION) (+ :$(DISTRO))"
	@echo "  make cuda    build rammp-cuda:$(VERSION) (+ :$(DISTRO))"
	@echo "  make test    smoke-test the built images"
	@echo "  make push    publish both to $(REGISTRY) (docker login ghcr.io first)"
	@echo
	@echo "Normally you don't push by hand: tagging a release (git tag v1.0.0-jp6)"
	@echo "makes CI build and publish both images."

base:
	$(BUILD) -f docker/base/Dockerfile \
	  -t rammp-base:$(VERSION) -t rammp-base:$(DISTRO) .

cuda: base
	$(BUILD) -f docker/cuda/Dockerfile \
	  -t rammp-cuda:$(VERSION) -t rammp-cuda:$(DISTRO) .

test:
	./scripts/smoke-test.sh rammp-base:$(VERSION)
	./scripts/smoke-test.sh rammp-cuda:$(VERSION)

push: cuda
	for img in rammp-base rammp-cuda; do \
	  docker tag  $$img:$(VERSION) $(REGISTRY)/$$img:$(VERSION); \
	  docker tag  $$img:$(VERSION) $(REGISTRY)/$$img:$(DISTRO); \
	  docker push $(REGISTRY)/$$img:$(VERSION); \
	  docker push $(REGISTRY)/$$img:$(DISTRO); \
	done

clean:
	-docker rmi rammp-base:$(VERSION) rammp-base:$(DISTRO) \
	            rammp-cuda:$(VERSION) rammp-cuda:$(DISTRO)
