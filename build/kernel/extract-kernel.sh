#!/bin/sh
# Extract Alpine linux-virt kernel image and config
set -eux

mkdir -p /out

# List boot files for debugging
ls -la /boot/

# Copy kernel image
cp /boot/vmlinuz-virt /out/vmlinuz

# Copy kernel config (for auditing) — may not exist in all builds
if [ -f /boot/config-virt ]; then
    cp /boot/config-virt /out/.config
else
    echo "No kernel config found at /boot/config-virt" > /out/.config
fi

# Record version
echo "$(cat /boot/vmlinuz-virt | head -c 64 | od -A n -t x1)" > /out/kernel-id.txt
echo "Alpine linux-virt kernel extracted" > /out/source.txt
