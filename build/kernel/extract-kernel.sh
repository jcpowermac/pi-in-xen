#!/bin/sh
# Extract Alpine linux-virt kernel image and config
set -eux

mkdir -p /out

# Copy kernel image
cp /boot/vmlinuz-virt /out/vmlinuz

# Copy kernel config (for auditing)
cp /boot/config-virt /out/.config

# Record version
echo "$(cat /boot/vmlinuz-virt | head -c 64 | od -A n -t x1)" > /out/kernel-id.txt
echo "Alpine linux-virt kernel extracted" > /out/source.txt
