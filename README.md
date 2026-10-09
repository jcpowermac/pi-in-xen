# pi-in-xen

Pi agent (pi.dev) in a Xen PVH virtual machine: fast boot, minimal attack surface, Alpine-based initramfs.

## Architecture

Three-layer isolation:

1. **Xen PVH direct boot** — no BIOS/UEFI, no QEMU/device model. Hardware VT-x/AMD-V CPU isolation with PV drivers.
2. **Minimal Alpine kernel** — linux-virt (Option A) or custom minimal kernel with CONFIG_MODULES=n (Option B). Stripped subsystems: sound, USB, GPU, etc.
3. **Alpine initramfs rootfs** — no persistent disk, no ostree, no systemd. busybox init + Node.js + pi agent. Boots entirely from memory.

Network isolation via existing [qlvm](https://github.com/jcpowermac/qlvm) OVN/OVS subnet.

## Why not Fedora/ostree?

This project deliberately uses **Alpine** (not Fedora) as the base OS:

- Smallest libc (musl), static binaries, mdev (not udev), busybox init
- Alpine cannot practically use [BlueBuild](https://blue-build.org)/ostree (RPM-based tooling)
- ostree requires RPM packages + dracut + systemd. Alpine uses apk + musl + OpenRC
- No official Alpine bootc image exists
- For a stateless agent VM, the initramfs approach is faster and has smaller TCB

## Why not containers?

The VM is the isolation boundary. No Docker, podman, or containerd. The pi agent runs directly in the VM with Xen hypervisor providing hardware isolation.

## Requirements

- Xen dom0 (Fedora or any distro with Xen PVH support)
- [qlvm](https://github.com/jcpowermac/qlvm) installed (for VM lifecycle management)
- Docker (for building kernel and rootfs images)
- Go 1.22+ (for build tooling)

## Build

```bash
make build
  → make kernel-a    # Option A: Alpine linux-virt kernel (fast)
  → make rootfs      # apk install packages + pi agent + pack initramfs
  → make template    # create qlvm initramfs template
```

## Usage

```bash
qlvm vm create pi-agent --template pi-agent --memory 1024 --vcpus 2
qlvm vm start pi-agent
xl console pi-agent        # interactive pi prompt
qlvm vm stop pi-agent
qlvm vm delete pi-agent
```

## Design

- **PVH direct boot**: Fastest possible boot path (no BIOS/UEFI, no device model)
- **initramfs-only**: No disk, no filesystem, no journal, no persistent state
- **Minimal kernel**: CONFIG_MODULES=n (Option B) or module loading disabled at boot (Option A)
- **seccomp-BPF**: Runtime syscall whitelist for the pi agent process
- **Routed networking**: /32 point-to-point via qlvm OVN (no bridge, no L2 attacks)

## Project Structure

```
pi-in-xen/
├── README.md
├── Makefile                    # top-level build orchestration
├── build/
│   ├── kernel/
│   │   ├── Dockerfile.a        # Option A: extract Alpine linux-virt
│   │   ├── Dockerfile.b        # Option B: custom minimal kernel
│   │   ├── minimalize-config.sh # adapted from xen-guest-kernel
│   │   └── config-alpine       # base kernel config for Option B
│   └── rootfs/
│       ├── Dockerfile          # Alpine rootfs build
│       ├── apk-list.txt        # package list
│       ├── init                # busybox init script
│       └── etc/                # passwd, group, ssl
├── internal/
│   ├── kernel/                 # Go kernel build tooling
│   ├── rootfs/                 # Go rootfs build tooling
│   └── security/               # kernel audit, seccomp policy
├── docs/
│   └── superpowers/
│       ├── plans/
│       │   └── 2026-10-09-pi-agent-xen-minimal-vm.md
│       └── specs/
└── .gitignore
```

## Plan

See [docs/superpowers/plans/2026-10-09-pi-agent-xen-minimal-vm.md](docs/superpowers/plans/2026-10-09-pi-agent-xen-minimal-vm.md) for the full implementation plan.

## Related Projects

- [qlvm](https://github.com/jcpowermac/qlvm) — Qubes-like VM isolation on Xen, in Go
- [os](https://github.com/jcpowermac/os) — Fedora-based ostree/BlueBuild images (dom0, bolt, xenguest)
- [xen-guest-kernel](https://github.com/jcpowermac/xen-guest-kernel) — Minimal Fedora Xen PV guest kernel
- [pi.dev](https://pi.dev) — The pi coding agent
