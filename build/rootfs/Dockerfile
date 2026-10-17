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
 && cp -a /usr/lib/. /rootfs/usr/lib/ \
 && [ -d /usr/share ] && cp -a /usr/share/. /rootfs/usr/share/ || true

# Copy essential libraries (musl, etc.) BEFORE busybox install so chroot works
RUN set -eux \
 && cp -a /lib/. /rootfs/lib/ \
 && [ -d /lib64 ] && cp -a /lib64/. /rootfs/lib64/ || true

# Copy busybox and create symlinks using chroot so paths are correct
RUN set -eux \
 && cp -a /bin/busybox /rootfs/bin/ \
 && chroot /rootfs /bin/busybox --install -s /bin \
 && chroot /rootfs /bin/busybox --install -s /sbin

# Add missing symlinks needed by pi agent and node
RUN set -eux \
 && ln -sf /bin/env /rootfs/usr/bin/env \
 && ln -sf /bin/busybox /rootfs/sbin/mdev 2>/dev/null || true \
 && ln -sf /bin/busybox /rootfs/sbin/ifup 2>/dev/null || true \
 && ln -sf /bin/busybox /rootfs/sbin/ifdown 2>/dev/null || true \
 && ln -sf /bin/busybox /rootfs/sbin/ip 2>/dev/null || true

# Copy ca-certificates
RUN set -eux \
 && cp -a /etc/ssl/. /rootfs/etc/ssl

# Install pi agent in main container via the official managed installer,
# then copy the managed layout to rootfs.
#
# "Not npm": the legacy path was `npm install -g` (floating registry
# resolution, unpinned transitive deps). The managed installer pins the
# release via pi.dev's installer API (metadata.json with sourceCommit +
# per-package integrity hashes) and installs it with `npm ci` against the
# published package-lock.json. The resulting layout (~/.pi/agent with
# bin/pi launcher + install/releases/<version>/) is what `pi update`
# expects, so in-guest updates keep working.
# Requires node >= 22.19 on PATH (alpine:3.21 nodejs-lts = 22.23.x) for a
# non-interactive run (no /dev/tty in docker build).
WORKDIR /app
RUN set -eux \
 && curl -fsSL https://pi.dev/install.sh | sh \
 && test -x /root/.pi/agent/bin/pi \
 && test -f /root/.pi/agent/install/current-version \
 && rm -rf /var/cache/apk /root/.npm /tmp/*

# Copy the managed pi layout to rootfs at /.pi (absolute paths, so it
# works regardless of which user's HOME runs it), plus the pi-node dir if
# the installer ever ships its own node. The launcher resolves the
# install tree relative to its own path, so moving it is safe.
RUN set -eux \
 && cp -a /root/.pi /rootfs/.pi \
 && if [ -d /root/.local/share/pi-node ]; then mkdir -p /rootfs/.local/share && cp -a /root/.local/share/pi-node /rootfs/.local/share/pi-node; fi \
 && ln -sf /.pi/agent/bin/pi /rootfs/usr/local/bin/pi

# Set up init and passwd/group
RUN set -eux \
 && cp /etc/passwd.template /rootfs/etc/passwd \
 && cp /etc/group.template /rootfs/etc/group \
 && cp /init /rootfs/init \
 && chmod +x /rootfs/init

# Set ownership: piagent (uid=1000) needs /workspace and /var
RUN set -eux \
 && chown -R 1000:1000 /rootfs/workspace /rootfs/var

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
