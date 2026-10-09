# Alpine rootfs build for pi agent Xen PVH VM
# Installs Alpine packages into /rootfs, then packs as initramfs cpio.gz.
# No ostree, no systemd, no persistent disk.

FROM alpine:3.21

# Copy build files
COPY init /init
COPY etc/passwd /etc/passwd.template
COPY etc/group /etc/group.template

# Install packages normally (apk has repo access)
RUN set -eux \
 && apk add --no-cache \
        nodejs-lts \
        npm \
        git \
        ripgrep \
        ca-certificates \
        busybox

# Create rootfs structure
RUN set -eux \
 && mkdir -p /rootfs/bin /rootfs/sbin /rootfs/etc /rootfs/proc /rootfs/sys /rootfs/dev \
 && mkdir -p /rootfs/usr/bin /rootfs/usr/sbin /rootfs/usr/local/bin /rootfs/usr/lib /rootfs/usr/share /rootfs/usr/include \
 && mkdir -p /rootfs/var /rootfs/workspace /rootfs/app /rootfs/etc/ssl/certs /rootfs/tmp /rootfs/root /rootfs/lib /rootfs/lib64

# Copy installed packages into rootfs
# Copy /usr (node, git, rg, node_modules)
RUN set -eux \
 && cp -a /usr/bin/node /rootfs/usr/bin/ \
 && cp -a /usr/bin/npm /rootfs/usr/bin/ \
 && cp -a /usr/bin/npx /rootfs/usr/bin/ \
 && cp -a /usr/bin/git /rootfs/usr/bin/ \
 && cp -a /usr/bin/rg /rootfs/usr/bin/ \
 && cp -a /usr/lib /rootfs/usr/lib/ \
 && [ -d /usr/share ] && cp -a /usr/share /rootfs/usr/share/ || true

# Copy busybox and create symlinks (mdev is a busybox applet)
RUN set -eux \
 && cp -a /bin/busybox /rootfs/bin/ \
 && /rootfs/bin/busybox --install -s /rootfs/bin \
 && /rootfs/bin/busybox --install -s /rootfs/sbin \
 && ln -sf /bin/busybox /rootfs/bin/sh 2>/dev/null || true \
 && ln -sf /bin/busybox /rootfs/sbin/mdev 2>/dev/null || true \
 && ln -sf /bin/busybox /rootfs/sbin/ifup 2>/dev/null || true \
 && ln -sf /bin/busybox /rootfs/sbin/ifdown 2>/dev/null || true \
 && ln -sf /bin/busybox /rootfs/sbin/ip 2>/dev/null || true

# Copy ca-certificates
RUN set -eux \
 && cp -a /etc/ssl /rootfs/etc/ssl

# Copy essential libraries (musl, etc.)
RUN set -eux \
 && cp -a /lib /rootfs/lib \
 && cp -a /lib64 /rootfs/lib64 2>/dev/null || true

# Install pi agent in main container (npm works here), then copy to rootfs
WORKDIR /app
RUN set -eux \
 && npm install -g --ignore-scripts @earendil-works/pi-coding-agent --prefix /usr/local \
 && rm -rf /var/cache/apk /root/.npm /tmp/*

# Copy installed pi agent to rootfs
RUN set -eux \
 && cp -a /usr/local/bin /rootfs/usr/local/bin \
 && cp -a /usr/local/lib /rootfs/usr/local/lib

# Set up init and passwd/group
RUN set -eux \
 && cp /etc/passwd.template /rootfs/etc/passwd \
 && cp /etc/group.template /rootfs/etc/group \
 && cp /init /rootfs/init \
 && chmod +x /rootfs/init

# Clean up rootfs (remove unnecessary files)
RUN set -eux \
 && find /rootfs -name "*.a" -delete 2>/dev/null || true \
 && find /rootfs -name "*.o" -delete 2>/dev/null || true \
 && find /rootfs -name "test" -type d -exec rm -rf {} + 2>/dev/null || true

# Pack as initramfs cpio.gz
RUN set -eux \
 && mkdir -p /out \
 && cd /rootfs \
 && find . | cpio -H newc -o | gzip -9 > /out/initramfs.cpio.gz \
 && echo "initramfs built: $(ls -lh /out/initramfs.cpio.gz)"
