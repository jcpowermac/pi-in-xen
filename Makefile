.PHONY: build kernel-a kernel-b rootfs container extract test clean

# Default build: Option A kernel (fast) + rootfs + container
build: kernel-a rootfs container

# Option A: Alpine linux-virt kernel (fast, practical)
kernel-a:
	@echo "Building Option A: Alpine linux-virt kernel..."
	docker build -t alpine-kernel:a -f build/kernel/Dockerfile.a build/kernel/
	@mkdir -p build/kernel/out
	CONTAINER=$$(docker create alpine-kernel:a)
	docker cp $$CONTAINER:/out/. build/kernel/out/
	docker rm $$CONTAINER
	@echo "Kernel extracted to build/kernel/out/vmlinuz"

# Option B: Custom minimal kernel (slow, smaller TCB)
kernel-b:
	@echo "Building Option B: Custom minimal Alpine kernel..."
	docker build -t alpine-kernel:b -f build/kernel/Dockerfile.b build/kernel/
	@mkdir -p build/kernel/out
	CONTAINER=$$(docker create alpine-kernel:b)
	docker cp $$CONTAINER:/out/. build/kernel/out/
	docker rm $$CONTAINER
	@echo "Kernel built to build/kernel/out/vmlinuz"

# Build rootfs: apk install packages + pi agent + pack initramfs
rootfs:
	@echo "Building rootfs..."
	docker build -t alpine-rootfs -f build/rootfs/Dockerfile build/rootfs/
	@mkdir -p build/rootfs/out
	CONTAINER=$$(docker create alpine-rootfs)
	docker cp $$CONTAINER:/out/initramfs.cpio.gz build/rootfs/out/
	docker rm $$CONTAINER
	@echo "initramfs built: $(ls -lh build/rootfs/out/initramfs.cpio.gz)"

# Create container image (transport for kernel + initramfs)
container:
	@echo "Building container image..."
	mkdir -p build/container/context
	cp build/kernel/out/vmlinuz build/container/context/
	cp build/rootfs/out/initramfs.cpio.gz build/container/context/initramfs.img
	cp build/container/os-release build/container/context/
	echo "local-build" > build/container/context/kernel-version
	docker build \
		--build-arg KERNEL_VERSION=local-build \
		-t pi-in-xen:latest \
		-f build/container/Dockerfile \
		build/container/context/
	@echo "Container built: pi-in-xen:latest"

# Extract kernel + initramfs from container for qlvm
extract:
	@echo "Extracting from container..."
	CONTAINER=$$(docker create pi-in-xen:latest)
	mkdir -p build/kernel/out build/rootfs/out
	docker cp $$CONTAINER:/usr/lib/modules/local-build/vmlinuz build/kernel/out/
	docker cp $$CONTAINER:/usr/lib/modules/local-build/initramfs.img build/rootfs/out/initramfs.cpio.gz
	docker rm $$CONTAINER
	@echo "Extracted to build/kernel/out/vmlinuz and build/rootfs/out/initramfs.cpio.gz"

# Test VM boot
test: template
	@echo "Testing VM boot..."
	qlvm vm create pi-test --template pi-agent --memory 1024 --vcpus 2
	qlvm vm start pi-test
	@echo "VM started. Check console: xl console pi-test"
	@echo "Stop with: qlvm vm stop pi-test && qlvm vm delete pi-test"

# Clean build artifacts
clean:
	rm -rf build/*/out/
