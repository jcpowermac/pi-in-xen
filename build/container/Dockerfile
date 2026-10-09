# Pi agent Xen PVH VM container image
# This container is NOT meant to be run. It's a transport mechanism for the
# kernel and initramfs. qlvm extracts them and creates a PVH domain directly.
#
# Container layout (similar to bootc):
#   /usr/lib/modules/<version>/vmlinuz      # kernel
#   /usr/lib/modules/<version>/initramfs.img # initramfs (full Alpine rootfs)
#   /etc/os-release                         # metadata
#   /etc/kernel-version                     # kernel version string
#
# Build with:
#   docker build -t pi-in-xen:latest -f build/container/Dockerfile build/container/

FROM scratch

# Kernel and initramfs (built separately, copied here)
ARG KERNEL_VERSION
COPY vmlinuz /usr/lib/modules/${KERNEL_VERSION}/vmlinuz
COPY initramfs.img /usr/lib/modules/${KERNEL_VERSION}/initramfs.img

# Metadata
COPY os-release /etc/os-release
COPY kernel-version /etc/kernel-version

# Labels for qlvm to identify this as a PVH initramfs image
LABEL org.opencontainers.image.title="pi-agent-xen-pvh"
LABEL org.opencontainers.image.description="Pi agent in Xen PVH VM — kernel + initramfs container"
LABEL org.opencontainers.image.version="${KERNEL_VERSION}"
LABEL io.qlvm.type="pvh-initramfs"
LABEL io.qlvm.kernel="/usr/lib/modules/${KERNEL_VERSION}/vmlinuz"
LABEL io.qlvm.initramfs="/usr/lib/modules/${KERNEL_VERSION}/initramfs.img"
