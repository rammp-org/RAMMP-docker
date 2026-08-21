# Build and publish the RAMMP base images.
#
# Version the images explicitly. Bump VERSION when RAMMP-interfaces or the base
# setup changes, then rebuild + repush; modules pin this version in their FROM.
REGISTRY ?= ghcr.io/rammp-org
VERSION  ?= 1.0.0
DISTRO   ?= humble

# Jetson only: the L4T ROS+PyTorch image matching your JetPack (see docker/cuda).
JETSON_BASE ?= dustynv/ros:humble-pytorch-l4t-r36.2.0

# Both images build from the REPO ROOT because they COPY RAMMP-interfaces/.
.PHONY: help base cuda cuda-jetson push-base push-cuda

help:
	@echo "Local builds (run on the target arch):"
	@echo "  make base          - rammp-base:$(VERSION) (+ :$(DISTRO))"
	@echo "  make cuda          - rammp-cuda on x86 (FROM rammp-base + CUDA torch)"
	@echo "  make cuda-jetson   - rammp-cuda on a Jetson (FROM JETSON_BASE)"
	@echo "Publish to $(REGISTRY) (run 'docker login ghcr.io' first):"
	@echo "  make push-base / make push-cuda"
	@echo "Override: VERSION=$(VERSION) REGISTRY=$(REGISTRY) JETSON_BASE=$(JETSON_BASE)"

base:
	docker build -f docker/base/Dockerfile \
	  -t rammp-base:$(VERSION) -t rammp-base:$(DISTRO) .

cuda: base
	docker build -f docker/cuda/Dockerfile \
	  --build-arg CUDA_BASE=rammp-base:$(VERSION) \
	  -t rammp-cuda:$(VERSION) -t rammp-cuda:$(DISTRO) .

cuda-jetson: base
	docker build -f docker/cuda/Dockerfile \
	  --build-arg CUDA_BASE=$(JETSON_BASE) \
	  -t rammp-cuda:$(VERSION) -t rammp-cuda:$(DISTRO) .

# ── publish ──────────────────────────────────────────────────────────────────
# Run on the arch you're publishing (x86 from an x86 box, arm64 from a Jetson).
# To serve both arches under one pullable tag, push arch-suffixed tags and then
# combine with `docker buildx imagetools create` (see README).
push-base: base
	docker tag  rammp-base:$(VERSION) $(REGISTRY)/rammp-base:$(VERSION)
	docker tag  rammp-base:$(DISTRO)  $(REGISTRY)/rammp-base:$(DISTRO)
	docker push $(REGISTRY)/rammp-base:$(VERSION)
	docker push $(REGISTRY)/rammp-base:$(DISTRO)

push-cuda: cuda
	docker tag  rammp-cuda:$(VERSION) $(REGISTRY)/rammp-cuda:$(VERSION)
	docker tag  rammp-cuda:$(DISTRO)  $(REGISTRY)/rammp-cuda:$(DISTRO)
	docker push $(REGISTRY)/rammp-cuda:$(VERSION)
	docker push $(REGISTRY)/rammp-cuda:$(DISTRO)
