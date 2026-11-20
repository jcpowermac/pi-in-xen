# Option B: Build the minimized Alpine "virt" Xen PVH guest kernel with 9p
# (trans=xen) built in — the source of truth for the pi agent VM kernel.
#
# Mirrors the standard Alpine kernel build (wiki.alpinelinux.org, "How to build
# the Alpine Linux kernel"): the source is kernel.org's linux-7.3.tar.xz plus
# the stable patch (patch-7.3.5.xz); the base config is aports' virt.x86_64.config
# (version-agnostic — `make olddefconfig` picks up new 7.3 options with defaults).
# We then run
# minimalize-config.sh to strip it to "only what's required for Xen hardware"
# (PV frontends + console + grant table) and force 9p + netfs built-in, so the
# busybox init can `mount -t 9p -o trans=xen` without loading any modules.

FROM alpine:3.21

# Kernel build toolchain: alpine-sdk (gcc/make/binutils) + the rest of the
# aports linux-lts makedepends.
RUN apk add --no-cache \
        alpine-sdk bash bc perl python3 openssl-dev elfutils-dev zstd pahole \
        gmp-dev mpc1-dev mpfr-dev mawk flex bison diffutils findutils \
        linux-headers \
    && adduser -D -H builder

# aports main/linux-lts virt.x86_64.config (base for the minimized kernel config).
COPY minimalize-config.sh /build/minimalize-config.sh
# Fetch just the virt config as a single raw file, with retries. A full
# `git clone` of aports over HTTPS intermittently hits GitLab's HTTP 418
# rate-limit from shared CI runner IPs; a one-file fetch is small and far
# less likely to trip it. wget is busybox's; grep verifies a real config landed.
RUN set -eux \
 && for i in $(seq 1 6); do \
        wget -q -O /build/virt.x86_64.config \
          "https://gitlab.alpinelinux.org/alpine/aports/-/raw/3.21-stable/main/linux-lts/virt.x86_64.config" \
      && break || { echo "aports virt config fetch (attempt $i) failed, retrying..."; sleep 5; }; \
    done \
 && grep -q '^CONFIG_' /build/virt.x86_64.config

# Fetch the exact kernel source aports builds, apply the stable patch to reach
# 7.3.5 (not 7.2: 7.2 is non-LTS, deprecated once 7.3 shipped; 7.4 is only -rc).
RUN set -eux \
 && mkdir -p /src/linux && cd /src/linux \
 && KO=https://cdn.kernel.org/pub/linux/kernel/v7.x \
 && wget -q -O linux-7.3.tar.xz "$KO/linux-7.3.tar.xz" \
 && wget -q -O patch-7.3.5.xz "$KO/patch-7.3.5.xz" \
 && tar -xf linux-7.3.tar.xz \
 && xz -dc patch-7.3.5.xz > patch-7.3.5 \
 && cd linux-7.3 \
 && patch -p1 < ../patch-7.3.5

# Minimalize the real virt config to "only Xen hardware" + force 9p built-in,
# resolve the config, and build just the PVH-bootable bzImage.
RUN set -eux \
 && bash /build/minimalize-config.sh /build/virt.x86_64.config \
        /src/linux/linux-7.3/.config \
 && cd /src/linux/linux-7.3 \
 && make olddefconfig \
 && make -j"$(nproc)" bzImage \
 && mkdir -p /out \
 && cp arch/x86/boot/bzImage /out/vmlinuz \
 && cp .config /out/.config \
 && echo "minimized alpine virt kernel (Xen PVH, 9p trans=xen built-in)" \
        > /out/source.txt
