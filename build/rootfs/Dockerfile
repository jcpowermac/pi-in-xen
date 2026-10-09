# Alpine rootfs build for pi agent Xen PVH VM
# Installs Alpine packages into /rootfs, then packs as initramfs cpio.gz.
# No ostree, no systemd, no persistent disk.

FROM alpine:3.21

# Copy build scripts
COPY apk-list.txt /apk-list.txt
COPY init /init
COPY etc/passwd /etc/passwd.template
COPY etc/group /etc/group.template

# Create rootfs structure and install packages
RUN set -eux \
 && mkdir -p /rootfs/{bin,sbin,etc,proc,sys,dev,usr/bin,usr/sbin,usr/local/bin,var,workspace,app} \
 && apk add --root /rootfs --initdb --no-cache \
        busybox \
        nodejs-lts \
        npm \
        git \
        ripgrep \
        ca-certificates \
        mdev \
 && /rootfs/bin/busybox --install -s /rootfs/bin \
 && cp /etc/passwd.template /rootfs/etc/passwd \
 && cp /etc/group.template /rootfs/etc/group \
 && cp /init /rootfs/init \
 && chmod +x /rootfs/init

# Install pi agent into rootfs
WORKDIR /rootfs/app
RUN apk add --root /rootfs --no-cache npm \
 && /rootfs/usr/bin/npm install -g --ignore-scripts @earendil-works/pi-coding-agent --prefix /rootfs/usr/local \
 && rm -rf /rootfs/var/cache/apk /rootfs/root/.npm /rootfs/tmp/*

# Pack as initramfs cpio.gz
WORKDIR /rootfs
RUN find . | cpio -H newc -o | gzip -9 > /out/initramfs.cpio.gz \
 && echo "initramfs built: $(ls -lh /out/initramfs.cpio.gz)"
