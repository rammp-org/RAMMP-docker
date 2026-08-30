# Build and publish the RAMMP base images.
#
# These images are linux/arm64 ONLY -- the robot's only compute target is a
# Jetson Orin. There is no amd64 variant, so there are no multi-arch manifests
# to combine and no architecture-suffixed tags: one platform, one tag.
#
# Run these ON THE JETSON (or let CI do it). Plain `docker build`, so no buildx
# plugin is required on the robot.
#
# Bump VERSION when RAMMP-interfaces or the base setup changes, then tag a
# release; modules pin this version in their FROM.

REGISTRY ?= ghcr.io/rammp-org
VERSION  ?= 1.0.0
DISTRO   ?= humble

# Both images build from the REPO ROOT because they COPY RAMMP-interfaces/.
BUILD = docker build --build-arg VERSION=$(VERSION)

.PHONY: help base cuda test push clean

help:
	@echo "RAMMP base images -- arm64/Jetson only (VERSION=$(VERSION))"
	@echo
	@echo "  make base    build rammp-base:$(VERSION) (+ :$(DISTRO))"
	@echo "  make cuda    build rammp-cuda:$(VERSION) (+ :$(DISTRO))"
	@echo "  make test    smoke-test the built images"
	@echo "  make push    publish both to $(REGISTRY) (docker login ghcr.io first)"
	@echo
	@echo "Normally you don't push by hand: tagging a release (git tag v1.0.0)"
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
