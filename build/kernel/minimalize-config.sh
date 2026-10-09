#!/bin/bash
# Transform Alpine's x86_64 kernel config into a minimal Xen PVH guest kernel config.
# Strategy: Only disable major subsystems with no dependencies in what we keep.
# Target: CONFIG_MODULES=n (monolithic kernel) for minimal attack surface.
#
# Differences from Fedora version (xen-guest-kernel):
#   - CONFIG_MODULES=n (monolithic, no module loading)
#   - No ostree options (no BTRFS, no OVERLAY_FS, no DM)
#   - No systemd options (no TIMERFD, no full NAMESPACES)
#   - Keep EXT4 (for any mounted filesystems, e.g. p9 workspace)
#   - Keep devtmpfs, proc, sysfs (required for initramfs)
#
# Usage: minimalize-config.sh <input-config> [output-config]

set -euo pipefail

INPUT="${1:?Usage: $0 <input-config> [output-config]}"
OUTPUT="${2:-/dev/stdout}"

# Return 0 to disable, 1 to keep
should_disable() {
    local opt="$1"

    # ===== CRITICAL: Disable all modules (monolithic kernel) =====
    if [[ "$opt" == "CONFIG_MODULES" ]]; then
        return 0
    fi

    # ===== SOUND — nothing we keep depends on this =====
    if [[ "$opt" == SND* ]] || [[ "$opt" == SOUND ]] || [[ "$opt" == AC97* ]] || \
       [[ "$opt" == ALSA* ]] || [[ "$opt" == SOUNDWIRE* ]] || [[ "$opt" == HDA* ]]; then
        return 0
    fi

    # ===== GPU/Display — Xen provides virtual framebuffer =====
    # Keep FB_EFI — needed for proper x86_64 boot flags
    [[ "$opt" == FB_EFI ]] && return 1
    if [[ "$opt" == DRM* ]] || [[ "$opt" == FB_* ]] || [[ "$opt" == VGA_CONSOLE ]] || \
       [[ "$opt" == VIDEO* ]] || [[ "$opt" == GSPMI* ]] || [[ "$opt" == MIPI* ]] || \
       [[ "$opt" == MEDIA* ]] || [[ "$opt" == DVB_* ]] || [[ "$opt" == V4L* ]] || \
       [[ "$opt" == ANALOGTV ]] || [[ "$opt" == DAC1010 ]] || [[ "$opt" == DAC7010A ]] || \
       [[ "$opt" == DAC7512 ]] || [[ "$opt" == DAC7561 ]] || [[ "$opt" == DAC756 ]] || \
       [[ "$opt" == ADC* ]] && [[ "$opt" != ADC_EXYNOS ]] || \
       [[ "$opt" == GPU_VID_MEM ]] || [[ "$opt" == DRM_KMS_HELPER ]] || \
       [[ "$opt" == DRM_KMS_FB_HELPER ]] || [[ "$opt" == DRM_KMS_CMA_HELPER ]] || \
       [[ "$opt" == DRM_TTM ]] || [[ "$opt" == DRM_GEM ]] || \
       [[ "$opt" == DRM_DP_AUX_BUS ]] || [[ "$opt" == DRM_DP_CEC ]] || \
       [[ "$opt" == DRM_DP_HELPER ]] || [[ "$opt" == DRM_DP_AUX_NATIVE ]] || \
       [[ "$opt" == DRM_I2C_* ]] || [[ "$opt" == DRM_KMS_HELPER ]] || \
       [[ "$opt" == DRM_LOAD_EDID_FIRMWARE ]] || [[ "$opt" == DRM_MIPI_DSI ]] || \
       [[ "$opt" == DRM_PANEL ]] || [[ "$opt" == DRM_TINYDRM ]] || \
       [[ "$opt" == DRM_VGEM ]] || [[ "$opt" == DRM_VKMS ]] || \
       [[ "$opt" == DRM_XGBe ]] || [[ "$opt" == DRM_XEN ]] || \
       [[ "$opt" == FRAMEBUFFER ]] || [[ "$opt" == FB ]] || \
       [[ "$opt" == BACKLIGHT ]] || [[ "$opt" == BACKLIGHT_* ]] || \
       [[ "$opt" == LEDS ]] || [[ "$opt" == LEDS_* ]] || \
       [[ "$opt" == VIDEO_OUTPUT ]] || [[ "$opt" == VIDEO_SELECT ]]; then
        return 0
    fi

    # ===== USB — guests don't need USB =====
    # Disable all USB (core, host, gadget, storage)
    if [[ "$opt" == USB* ]] || [[ "$opt" == USB ]] || [[ "$opt" == UDC* ]]; then
        return 0
    fi

    # ===== Firewire, IEEE1394 =====
    if [[ "$opt" == FIREWIRE ]] || [[ "$opt" == IEEE1394 ]]; then
        return 0
    fi

    # ===== Networking — keep only what Xen PV needs =====
    # Disable real network hardware, keep PV network
    if [[ "$opt" == ETHERNET ]] || [[ "$opt" == PHYLIB ]] || [[ "$opt" == MDIO ]] || \
       [[ "$opt" == WIRELESS ]] || [[ "$opt" == WLAN ]] || [[ "$opt" == CFG80211 ]] || \
       [[ "$opt" == RFKILL ]] || [[ "$opt" == BLUETOOTH ]] || [[ "$opt" == BT ]] || \
       [[ "$opt" == CAN ]] || [[ "$opt" == ATM ]] || [[ "$opt" == HSI ]] || \
       [[ "$opt" == PHONET ]] || [[ "$opt" == 6LOWPAN ]] || [[ "$opt" == IEEE802154 ]]; then
        return 0
    fi

    # Disable specific network drivers (keep xen-netfront)
    if [[ "$opt" == CONFIG_NETDEVICES ]] || [[ "$opt" == CONFIG_ETHERNET ]] || \
       [[ "$opt" == CONFIG_USB_NET ]] || [[ "$opt" == CONFIG_WAN ]]; then
        return 0
    fi

    # ===== Storage — keep only Xen PV block =====
    # Disable real block devices, keep xen-blkfront
    if [[ "$opt" == ATA ]] || [[ "$opt" == SCSI ]] || [[ "$opt" == NVME ]] || \
       [[ "$opt" == MMC ]] || [[ "$opt" == MTD ]] || [[ "$opt" == NBD ]] || \
       [[ "$opt" == LOOP ]] || [[ "$opt" == DM ]] || [[ "$opt" == MD ]]; then
        return 0
    fi

    # Disable specific block drivers (keep xen-blkfront)
    if [[ "$opt" == CONFIG_SCSI ]] || [[ "$opt" == CONFIG_BLK_DEV ]] || \
       [[ "$opt" == CONFIG_BLK_DEV_SD ]] || [[ "$opt" == CONFIG_BLK_DEV_SR ]] || \
       [[ "$opt" == CONFIG_BLK_DEV_NULL_BLK ]] || [[ "$opt" == CONFIG_BLK_DEV_LOOP ]]; then
        return 0
    fi

    # ===== Virtualization — keep only Xen PV/PVH =====
    # Disable KVM, virtio, VSOCK, etc.
    if [[ "$opt" == KVM ]] || [[ "$opt" == VIRTIO ]] || [[ "$opt" == VSOCK ]] || \
       [[ "$opt" == VFIO ]] || [[ "$opt" == VHOST ]] || [[ "$opt" == VDPA ]]; then
        return 0
    fi

    # ===== Platform devices — not needed in PV guest =====
    if [[ "$opt" == X86_PLATFORM_DEVICES ]] || [[ "$opt" == ACPI ]] || \
       [[ "$opt" == APM ]] || [[ "$opt" == PNP ]] || [[ "$opt" == PARPORT ]] || \
       [[ "$opt" == SERIAL ]] || [[ "$opt" == SERIO ]]; then
        return 0
    fi

    # ===== Input — not needed in headless agent VM =====
    if [[ "$opt" == INPUT ]] || [[ "$opt" == HID ]] || [[ "$opt" == TOUCHSCREEN ]] || \
       [[ "$opt" == KEYBOARD ]] || [[ "$opt" == MOUSE ]] || [[ "$opt" == JOYSTICK ]]; then
        return 0
    fi

    # ===== Thermal, Power, Watchdog =====
    if [[ "$opt" == THERMAL ]] || [[ "$opt" == POWER ]] || [[ "$opt" == WATCHDOG ]] || \
       [[ "$opt" == HWMON ]] || [[ "$opt" == POWER_SUPPLY ]] || [[ "$opt" == LEDS ]]; then
        return 0
    fi

    # ===== Debug, Tracing, Profiling =====
    if [[ "$opt" == DEBUG ]] || [[ "$opt" == TRACING ]] || [[ "$opt" == PROFILING ]] || \
       [[ "$opt" == KPROBE ]] || [[ "$opt" == FTRACE ]] || [[ "$opt" == BPF ]] || \
       [[ "$opt" == PERF ]] || [[ "$opt" == KGDB ]] || [[ "$opt" == KASAN ]] || \
       [[ "$opt" == KMSAN ]] || [[ "$opt" == KCSAN ]] || [[ "$opt" == UBSAN ]]; then
        return 0
    fi

    # ===== Misc =====
    if [[ "$opt" == Staging ]] || [[ "$opt" == STAGING ]] || [[ "$opt" == DRM ]] || \
       [[ "$opt" == SOUND ]] || [[ "$opt" == IIO ]] || [[ "$opt" == INDUSTRIALIO ]]; then
        return 0
    fi

    # Keep everything else
    return 1
}

# Process the config
while IFS= read -r line || [[ -n "$line" ]]; do
    # Skip comments and empty lines
    [[ "$line" =~ ^# ]] && { echo "$line"; continue; }
    [[ -z "$line" ]] && { echo "$line"; continue; }

    # Extract option name (CONFIG_XXX)
    opt=$(echo "$line" | sed -n 's/^\(CONFIG_[A-Z0-9_]*\).*/\1/p')
    [[ -z "$opt" ]] && { echo "$line"; continue; }

    # Check if should disable
    if should_disable "$opt"; then
        echo "# $opt is not set"
    else
        echo "$line"
    fi
done < "$INPUT"

# Append explicit settings for Alpine Xen PVH minimal kernel
cat << 'EOF'

# ===== Alpine Xen PVH minimal kernel — explicit settings =====

# CRITICAL: No module loading (monolithic kernel)
CONFIG_MODULES=n
CONFIG_MODULE_UNLOAD=n
CONFIG_MODULE_FORCE_UNLOAD=n
CONFIG_MODVERSIONS=n
CONFIG_MODULE_SRCVERSION_ALL=n
CONFIG_KMOD=n

# Xen PV/PVH support (must be built-in)
CONFIG_XEN=y
CONFIG_XEN_PV=y
CONFIG_XEN_PVHVM=y
CONFIG_XEN_PVH=y
CONFIG_XEN_PV_Spinlocks=y
CONFIG_XEN_PCI_STUB=y
CONFIG_XEN_BLKDEV_FRONTEND=y
CONFIG_XEN_NETDEV_FRONTEND=y
CONFIG_XEN_CONSOLE_FRONTEND=y
CONFIG_XENFS=y
CONFIG_XEN_XENBUS_FRONTEND=y
CONFIG_XEN_GRANT_DEV_ALLOC=y
CONFIG_XEN_EVTCHN=y
CONFIG_XEN_GNTDEV=y
CONFIG_XEN_PVFIFO=y
CONFIG_XEN_ACPI_PROCESSOR=y
CONFIG_XEN_PCIDEV_FRONTEND=n

# Filesystems (minimal set)
CONFIG_EXT4_FS=y
CONFIG_PROC_FS=y
CONFIG_SYSFS=y
CONFIG_DEVTMPFS=y
CONFIG_TMPFS=y
CONFIG_SQUASHFS=y
CONFIG_NFS_FS=y
CONFIG_NFS_V3=y
CONFIG_NFS_V4=y
CONFIG_9P_FS=y
CONFIG_9P_FS_POSIX_ACL=y
CONFIG_9P_FS_SECURITY=y

# Network (minimal set)
CONFIG_INET=y
CONFIG_IP_ADVANCED_ROUTER=y
CONFIG_INET_AH=y
CONFIG_INET_ESP=y
CONFIG_INET_IPCOMP=y
CONFIG_IPV6=y
CONFIG_PACKET=y
CONFIG_NETDEVICES=y
CONFIG_XEN_NETDEV_FRONTEND=y
CONFIG_BONDING=y
CONFIG_VLAN_8021Q=y
CONFIG_TUN=y
CONFIG_VETH=y

# Security
CONFIG_STRICT_KERNEL_RWX=y
CONFIG_STRICT_MODULE_RWX=y
CONFIG_STACKPROTECTOR_STRONG=y
CONFIG_FORTIFY_SOURCE=y
CONFIG_SLAB_FREELIST_RANDOM=y
CONFIG_SLAB_FREELIST_HARDENED=y
CONFIG_RANDOMIZE_KSTACK_OFFSET=y
CONFIG_RANDOMIZE_BASE=y
CONFIG_BPF_SYSCALL=n
CONFIG_KPROBES=n
CONFIG_KPROBE_EVENTS=n
CONFIG_DYNAMIC_FTRACE=n
CONFIG_KALLSYMS=y
CONFIG_KALLSYMS_ALL=n
CONFIG_SECCOMP=y
CONFIG_SECCOMP_FILTER=y
CONFIG_SECURITY=y
CONFIG_SECURITY_SELINUX=n
CONFIG_SECURITY_APPARMOR=n
CONFIG_SECURITY_TOMOYO=n
CONFIG_IMA=n
CONFIG_EVM=n

# Fast boot
CONFIG_PRINTK=y
CONFIG_BLK_DEV_INITRD=y
CONFIG_BINFMT_ELF=y
CONFIG_BINFMT_SCRIPT=y
CONFIG_KERNEL_GZIP=y
CONFIG_SMP=y
CONFIG_PREEMPT_VOLUNTARY=y

# Console
CONFIG_SERIAL_8250=y
CONFIG_SERIAL_8250_CONSOLE=y
CONFIG_SERIAL_8250_NR_UARTS=4
CONFIG_SERIAL_8250_RUNTIME_UARTS=4
CONFIG_VT=y
CONFIG_VT_CONSOLE=y
CONFIG_HVC_DRIVER=y
CONFIG_HVC_XEN=y
CONFIG_HVC_XEN_FRONTEND=y

# Crypto (minimal set for TLS)
CONFIG_CRYPTO=y
CONFIG_CRYPTO_AES=y
CONFIG_CRYPTO_SHA256=y
CONFIG_CRYPTO_SHA512=y
CONFIG_CRYPTO_CBC=y
CONFIG_CRYPTO_CTR=y
CONFIG_CRYPTO_GCM=y
CONFIG_CRYPTO_CCM=y
CONFIG_CRYPTO_AEAD=y
CONFIG_CRYPTO_AKCIPHER=y
CONFIG_CRYPTO_KDF=y
CONFIG_CRYPTO_HMAC=y
CONFIG_CRYPTO_NULL=y
CONFIG_CRYPTO_DEFLATE=y

# Misc
CONFIG_MAGIC_SYSRQ=n
CONFIG_SYSCTL=y
CONFIG_KMSG_SYSLOG=y
CONFIG_PRINTK_TIME=y
CONFIG_BUG=y
CONFIG_BUG_ON_DATA_CORRUPTION=y
CONFIG_EARLY_PRINTK=y
CONFIG_X86_ESPFIX64=y
CONFIG_X86_VSYSCALL_EMULATION=y
EOF
