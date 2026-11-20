.PHONY: build kernel-a kernel-b rootfs container extract template test clean

# Container runtime (dom0 has podman, not docker).
DOCKER ?= podman

# Default build: Option B kernel (minimized Xen PVH + 9p trans=xen built-in)
# + rootfs + container.
build: kernel-b rootfs container

# Option A: Alpine linux-virt kernel (fast, pre-built; 9p still a module)
kernel-a:
	@echo "Building Option A: Alpine linux-virt kernel..."
	$(DOCKER) build -t alpine-kernel:a -f build/kernel/Dockerfile.a build/kernel/
	@mkdir -p build/kernel/out
	CONTAINER=$$($(DOCKER) create alpine-kernel:a); \
	$(DOCKER) cp $$CONTAINER:/out/. build/kernel/out/; \
	$(DOCKER) rm $$CONTAINER
	@echo "Kernel extracted to build/kernel/out/vmlinuz"

# Option B: Minimized Xen PVH kernel from aports source (9p built-in)
kernel-b:
	@echo "Building Option B: Minimized Alpine virt kernel (Xen PVH + 9p)..."
	$(DOCKER) build --no-cache -t alpine-kernel:b -f build/kernel/Dockerfile.b build/kernel/
	@mkdir -p build/kernel/out
	CONTAINER=$$($(DOCKER) create alpine-kernel:b); \
	$(DOCKER) cp $$CONTAINER:/out/. build/kernel/out/; \
	$(DOCKER) rm $$CONTAINER
	@echo "Kernel built to build/kernel/out/vmlinuz"

# Build rootfs: apk install packages + pi agent + pack initramfs
rootfs:
	@echo "Building rootfs..."
	$(DOCKER) build -t alpine-rootfs -f build/rootfs/Dockerfile build/rootfs/
	@mkdir -p build/rootfs/out
	CONTAINER=$$($(DOCKER) create alpine-rootfs); \
	$(DOCKER) cp $$CONTAINER:/out/initramfs.cpio.gz build/rootfs/out/; \
	$(DOCKER) rm $$CONTAINER
	@echo "initramfs built: $(ls -lh build/rootfs/out/initramfs.cpio.gz)"

# Create container image (transport for kernel + initramfs)
container:
	@echo "Building container image..."
	mkdir -p build/container/context
	cp build/kernel/out/vmlinuz build/container/context/
	cp build/rootfs/out/initramfs.cpio.gz build/container/context/initramfs.img
	cp build/container/os-release build/container/context/
	echo "local-build" > build/container/context/kernel-version
	$(DOCKER) build \
		--build-arg KERNEL_VERSION=local-build \
		-t pi-in-xen:latest \
		-f build/container/Dockerfile \
		build/container/context/
	@echo "Container built: pi-in-xen:latest"

# Extract kernel + initramfs from container for qlvm
extract:
	@echo "Extracting from container..."
	CONTAINER=$$($(DOCKER) create pi-in-xen:latest); \
	mkdir -p build/kernel/out build/rootfs/out; \
	$(DOCKER) cp $$CONTAINER:/usr/lib/modules/local-build/vmlinuz build/kernel/out/; \
	$(DOCKER) cp $$CONTAINER:/usr/lib/modules/local-build/initramfs.img build/rootfs/out/initramfs.cpio.gz; \
	$(DOCKER) rm $$CONTAINER
	@echo "Extracted to build/kernel/out/vmlinuz and build/rootfs/out/initramfs.cpio.gz"

# Bake the qlvm agent-VM template from the CI-published image on ghcr.io.
# qlvm's `template create` uses podman's docker (registry) transport only, so
# the image must come from a registry -- CI publishes it to ghcr.io on every
# push to main. So: push, wait for the GH Actions build, then `make template`.
# Creates /var/lib/qlvm/templates/jcpowermac-pi-in-xen-sha256:<digest>/.
TEMPLATE_REF ?= ghcr.io/jcpowermac/pi-in-xen:latest
template:
	@echo "Baking qlvm agent template from $(TEMPLATE_REF)..."
	qlvm template create $(TEMPLATE_REF)

# Test VM boot
test: template
	@echo "Testing VM boot..."
	qlvm vm create pi-test --template jcpowermac-pi-in-xen --type agent --memory 2048 --vcpus 2
	qlvm vm start pi-test
	@echo "VM started. Check console: xl console pi-test"
	@echo "Stop with: qlvm vm stop pi-test && qlvm vm delete pi-test"

# Clean build artifacts
clean:
	rm -rf build/*/out/
