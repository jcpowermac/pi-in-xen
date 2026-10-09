.PHONY: build kernel-a kernel-b rootfs template test clean

# Default build: Option A kernel (fast) + rootfs + template
build: kernel-a rootfs template

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

# Create qlvm initramfs template
template:
	@echo "Creating qlvm template..."
	qlvm template create-initramfs pi-agent \
		--kernel build/kernel/out/vmlinuz \
		--initramfs build/rootfs/out/initramfs.cpio.gz

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
