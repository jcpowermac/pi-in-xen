# pi-in-xen

Pi agent (pi.dev) in a Xen PVH virtual machine: fast boot, minimal attack surface, Alpine-based initramfs.

## Architecture

Three-layer isolation:

1. **Xen PVH direct boot** — no BIOS/UEFI, no QEMU/device model. Hardware VT-x/AMD-V CPU isolation with PV drivers.
2. **Minimal Alpine kernel** — a minimized Xen PVH kernel (Option B, the default) with 9p `trans=xen` built-in, so the pi home 9p share mounts at boot with no module load. Option A (Alpine linux-virt, 9p as a module) is kept for fast pre-built boots. Stripped subsystems: sound, USB, GPU, etc.
3. **Alpine initramfs rootfs** — no persistent disk, no ostree, no systemd. busybox init + Node.js + pi agent. The OS boots entirely from memory; the pi's `$HOME` is a separate persistent 9p share (below).

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
- podman (for building kernel and rootfs images; the Makefile defaults to `podman` — dom0 ships podman, not docker — and accepts `DOCKER=docker make ...` to override)
- Go 1.22+ (for build tooling)

## Build

```bash
make build
  → make kernel-b    # Option B: minimized Xen PVH kernel (9p trans=xen built-in)
  → make rootfs      # apk install packages (incl. fd + ripgrep) + pi agent + pack initramfs
  → make container   # build the qlvm agent-VM template image
```

## Usage

```bash
qlvm vm create pi-agent --template <tpl> --type agent --memory 2048 --vcpus 2
qlvm vm start pi-agent
sudo qlvm vm console pi-agent   # interactive pi prompt (the console needs root)
qlvm vm stop pi-agent
qlvm vm delete pi-agent
```

## Design

- **PVH direct boot**: Fastest possible boot path (no BIOS/UEFI, no device model)
- **initramfs OS + persistent 9p home**: the OS is RAM-only (no disk, no journal); the pi's `$HOME` (`/var/data`) is a persistent 9p share backed by an isolated per-VM dom0 dir, so config/secrets/sessions survive reboots
- **Minimal kernel**: CONFIG_MODULES=n (Option B, 9p trans=xen built-in) or module loading disabled at boot (Option A)
- **seccomp-BPF**: Runtime syscall whitelist for the pi agent process
- **Routed networking**: /32 point-to-point via qlvm OVN (no bridge, no L2 attacks)

## Persistent workspace (9p)

The pi agent's `$HOME` is the guest path `/var/data` — a 9p share (9P2000.u,
`trans=xen`) backed by an isolated per-VM dom0 directory
(`/var/lib/qlvm/9p/<name>/data`). qlvm creates and chowns the dom0 side to the
pi agent uid at VM create; the busybox `init` mounts it with a retry loop
(the dom0 `xen-9pfsd` backend and the guest 9p frontend may not be ready
immediately after boot). Each agent VM gets its own home, so multiple agent
VMs run side by side without sharing state — the rest of the OS stays RAM-only.

`fd` and `ripgrep` are baked into the rootfs so the pi agent's search tools
work without a runtime download.

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
│   ├── container/              # qlvm agent-VM template image
│   └── rootfs/
│       ├── Dockerfile          # Alpine rootfs build (bakes fd + ripgrep)
│       ├── apk-list.txt        # package list (incl. fd, ripgrep)
│       ├── init                # busybox init (mounts the 9p pi home with retry)
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
