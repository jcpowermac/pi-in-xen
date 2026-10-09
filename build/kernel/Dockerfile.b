# Option B: Build custom minimal Alpine kernel (slower, smaller TCB)
# Builds Alpine kernel from source with minimal config.
# Target: CONFIG_MODULES=n, stripped subsystems (sound, USB, GPU, etc.)

FROM alpine:3.21

# Install build dependencies
RUN apk add --no-cache build-base linux-source linux-headers

# Copy config and minimalization script
COPY minimalize-config.sh /minimalize-config.sh
COPY config-alpine /config-alpine

# Build kernel
RUN chmod +x /minimalize-config.sh && set -eux \
 && cd /usr/src/linux \
 && cp /config-alpine .config \
 && bash /minimalize-config.sh .config .config.minimal \
 && mv .config.minimal .config \
 && make olddefconfig \
 && make -j$(nproc) bzImage \
 && mkdir -p /out \
 && cp arch/x86/boot/bzImage /out/vmlinuz \
 && cp .config /out/.config \
 && echo "Custom minimal Alpine kernel built" > /out/source.txt
