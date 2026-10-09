# Pi Agent in Xen — Fast Boot, Minimal Attack Surface

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Run the pi agent (pi.dev) in a Xen PVH domU with sub-10-second boot, minimal TCB, and hardened attack surface. Integrate with existing `qlvm` lifecycle management and `os` image build system.

**Architecture:** Three-layer isolation: (1) Xen hypervisor PVH direct boot (no BIOS/UEFI, no QEMU/device model), (2) minimal Alpine kernel (linux-virt or custom) with stripped subsystems, (3) Alpine-based initramfs rootfs (no persistent disk, no ostree, no systemd) running busybox init + Node.js + pi agent. Network isolation via existing qlvm OVN/OVS subnet.

**Tech Stack:** Xen PVH (type="pvh"), Alpine Linux base (musl, busybox init), Alpine linux-virt kernel or custom minimal kernel, Node.js 24 (musl), initramfs cpio.gz rootfs, Go (for build tooling), existing qlvm libxl/ovn integration.

**Container-based transport:** The kernel + initramfs are packaged into a container image (similar to bootc). qlvm extracts them from the container and creates a PVH domain directly. This allows:
- Building in GitHub Actions (container images are the output)
- Distribution via ghcr.io (same as os images)
- qlvm integration (pull container, extract kernel + initramfs, create domain)

**Why not ostree:** Alpine cannot practically use BlueBuild/ostree (RPM-based tooling). This approach uses a pure initramfs — no ostree, no systemd, no dracut. This is faster and has smaller TCB than the ostree path.

**Spec:** This plan documents the design; see inline rationale for each decision.

## Background: Existing Infrastructure

The current environment (see `../os` and `../qlvm`) provides:

- **qlvm**: Go CLI managing Xen PVH VMs via libxl (no .xl files), OVN/OVS network isolation, bootc/ostree container images, waypipe GUI forwarding, p9 mounts. VMs created with `qlvm vm create`.
- **os**: BlueBuild recipes producing:
  - Main Fedora Sway Atomic dom0 image (with xen, xen-libs, xen-runtime)
  - `os-bolt`: Headless minimal bootc image for disposable waypipe UI VMs (waypipe, firefox, systemd-networkd, nmap-ncat, xwayland-satellite)
  - `os-xenguest`: Headless Xen PV guest with minimal kernel RPMs (stripped ~70% of modules vs stock Fedora kernel)
- **xen-guest-kernel**: Minimal Fedora Xen PV guest kernel (stripped subsystems, 643 modules vs 4551 stock)
- **Current VM boot**: Container images (bootc/ostree) → dracut initrd → kernel → systemd. Attack surface includes: full kernel module set, systemd, ostree, bootc, container runtime layers.

**Gap:** No support for Alpine-based minimal VMs. Pi agent needs Node.js + minimal deps; Fedora-based approach is overkill and user doesn't want Fedora.

## Design Decisions

### D1: PVH Direct Boot (not HVM, not PV)
- **Why:** Hardware VT-x/AMD-V CPU isolation with PV drivers. Zero QEMU/device model in the path. Fastest boot (skips BIOS/UEFI entirely).
- **Tradeoff:** No PCI passthrough in PVH domUs (libxl limitation). Pi agent doesn't need passthrough, so this is fine.

### D2: initramfs-Only Rootfs (no persistent disk)
- **Why:** No disk = no filesystem = no journal = no persistent state to compromise. Boots entirely from memory. Kernel unpacks cpio.gz directly.
- **Tradeoff:** No persistence. Pi agent state (sessions, credentials) must be passed via environment variables or mounted read-only. This is acceptable for a stateless agent workload.

### D3: Alpine Kernel (linux-virt or custom minimal)
- **Why:** Alpine provides `linux-virt` kernel packages with Xen PV/PVH support out of the box (`CONFIG_XEN=y`, `CONFIG_XEN_PVHVM=y`, `CONFIG_XEN_PVH=y`, `CONFIG_XEN_BLKDEV_FRONTEND=y`, `CONFIG_XEN_NETDEV_FRONTEND=y`). Two options:
  - **Option A (practical):** Use Alpine's pre-built `linux-virt` kernel. Disable module loading at boot (`module.sig_enforce=1`) + seccomp blocking module syscalls.
  - **Option B (minimal):** Build custom kernel by applying a `minimalize-config.sh` (adapted from `../xen-vsock-kernel/scripts/minimalize-config.sh`) to Alpine's kernel config. Target CONFIG_MODULES=n for zero module attack surface.
- **Tradeoff:** Option A is faster to build, larger TCB. Option B is slower to build, smaller TCB. Start with Option A, move to Option B for production.

### D4: Alpine/musl Base (not Fedora)
- **Why:** User requirement — no Fedora as the basis for Pi. Alpine is the standard minimal Linux: smallest libc (musl), static binaries, mdev (not udev), busybox init. Proven in minimal Xen environments (see Qubes forum 13MB dom0 example).
- **Why not ostree/BlueBuild:** BlueBuild is designed for RPM-based distros (Fedora). ostree expects RPM packages + dracut + systemd. Alpine uses apk + musl + OpenRC + busybox. No official Alpine bootc image exists. Attempting Alpine+ostree is experimental and adds complexity without benefit for a stateless agent VM.
- **Tradeoff:** Different build process from `../os`. This is intentional — pi-agent VM is a different class of workload with different constraints (stateless, no GUI, agent-only).

### D5: Static Binaries (node, busybox, git, rg)
- **Why:** No shared library dependencies = no dlopen attack surface, no linker vulnerabilities. Single-file deployments.
- **Tradeoff:** Larger binaries than dynamic. Acceptable for a single VM.

### D6: BusyBox Init (no systemd, no ostree)
- **Why:** Minimal init script (sh) that mounts proc/sys/devtmpfs, configures network, and exec's the agent. No PID 1 complexity, no unit files, no socket activation.
- **Tradeoff:** No service management. Not needed for a single-process agent.

### D7: Integration with qlvm (not separate tool)
- **Why:** Reuse qlvm's libxl domain creation, OVN network isolation, lifecycle management (start/stop/kill/delete/list). Add a new template/image type rather than building a parallel system.
- **Tradeoff:** qlvm currently assumes bootc/ostree templates (raw disk images from bootc containers). Need to extend template model to support raw initramfs+kernel images (no disk, no btrfs reflink, no ostree root mount, no dracut initrd).

### D8: seccomp-BPF from init
- **Why:** Runtime syscall whitelist. Even if kernel has vulnerabilities, the agent process can only make whitelisted syscalls. Defense in depth.
- **Tradeoff:** Must whitelist exactly what node+pi need. Requires testing. Start permissive, tighten based on strace.

## Global Constraints

- **No containers:** No Docker, no podman, no containerd. The VM is the isolation boundary.
- **No QEMU:** PVH mode, no device model, no emulated hardware.
- **No persistent disk:** initramfs-only, stateless.
- **TDD:** Build tooling (Go) follows qlvm's TDD conventions. OS image builds are verified by boot tests.
- **Integration:** Works with `qlvm vm create/start/stop/kill/delete/list`. No separate CLI needed.
- **Security:** Every layer reduces attack surface. No "convenience" features that expand TCB.

## Review Focus

1. **Boot time:** Must achieve <10s from `qlvm vm start` to interactive pi prompt. Measure and iterate.
2. **Attack surface audit:** Kernel config must pass kconfig-hardened-check. No unnecessary subsystems compiled in.
3. **Network isolation:** VM must have only its subnet gateway reachable. No direct LAN access, no cross-VM L2 communication.
4. **Statelessness:** VM must be fully reproducible from build artifacts. No state persists between boots.
5. **Integration correctness:** qlvm lifecycle operations (start/stop/kill/delete) must work correctly with initramfs VMs (no ostree root to mount, no btrfs reflink).

---

## Phase 1: Build the Alpine Kernel

### Task 1: Alpine Kernel (linux-virt or custom minimal)

**Two options — start with Option A, move to Option B for production:**

**Option A: Alpine linux-virt kernel (practical, fast to build)**
- Use Alpine's pre-built `linux-virt` kernel package
- Already includes Xen PV/PVH support: `CONFIG_XEN=y`, `CONFIG_XEN_PVHVM=y`, `CONFIG_XEN_PVH=y`, `CONFIG_XEN_BLKDEV_FRONTEND=y`, `CONFIG_XEN_NETDEV_FRONTEND=y`
- Extract kernel image: `apk add linux-virt && cp /boot/vmlinuz-virt /out/vmlinuz`
- Disable module loading at boot: `module.sig_enforce=1` + seccomp blocking `init_module`/`finit_module`/`delete_module`
- Pros: No kernel build, uses tested Alpine kernel
- Cons: Larger TCB (modules available), not monolithic

**Option B: Custom minimal kernel (minimal TCB, slower to build)**
- Build Alpine kernel from source with minimal config
- Adapt `../xen-vsock-kernel/scripts/minimalize-config.sh` for Alpine's kernel config
- Target: CONFIG_MODULES=n, stripped subsystems (sound, USB, GPU, etc.)
- Build in Alpine container: `apk add build-base linux-source && make oldconfig && make -j$(nproc) bzImage`
- Pros: Smallest TCB, no modules, custom hardening
- Cons: Longer build time, must maintain kernel config

**Files:**
- Create: `build/kernel/Dockerfile` (Alpine-based kernel build container)
- Create: `build/kernel/minimalize-config.sh` (adapted from `../xen-vsock-kernel/` for Alpine)
- Create: `internal/kernel/kernel.go`, `internal/kernel/kernel_test.go`
- Create: `build/kernel/config-alpine` (base config for Option B)

**Interfaces:**
- Produces:
  - `func BuildKernelAlpine(srcDir string, configPath string, outputDir string) (string, error)` → returns path to vmlinuz (Option B)
  - `func ExtractKernelFromApk(apkDir string, outputDir string) (string, error)` → returns path to vmlinuz (Option A)
  - `func ValidateKernelConfig(config string) ([]string, error)` → returns list of missing/disabled required options
  - `func ExtractKernelModules(kernelDir string) []string` → for audit (should be empty for Option B)

**Kernel Config Requirements (minimal Xen PVH):**
```
CONFIG_XEN=y
CONFIG_XEN_PVHVM=y
CONFIG_X86_XENPV=y
CONFIG_X86_XEN_HVM=y
CONFIG_XEN_PVH=y
CONFIG_XEN_512GB=y
CONFIG_XEN_PV_SPINLOCK=y
CONFIG_XEN_PCI_STUB=y
CONFIG_XEN_PVFB=y
CONFIG_BLKDEV_XENBLK=y
CONFIG_NETDEVICES=y
CONFIG_XEN_NET_FRONTEND=y
CONFIG_XENFS=y
CONFIG_XEN_XENBUS_FRONTEND=y
CONFIG_XEN_GRANT_DEV_ALLOC=y
CONFIG_XEN_EVTCHN=y
CONFIG_XEN_GNTDEV=y

# HARDENING
CONFIG_MODULES=n              # CRITICAL: no module loading
CONFIG_STRICT_KERNEL_RWX=y
CONFIG_STRICT_MODULE_RWX=y
CONFIG_STACKPROTECTOR_STRONG=y
CONFIG_FORTIFY_SOURCE=y
CONFIG_SLAB_FREELIST_RANDOM=y
CONFIG_SLAB_FREELIST_HARDENED=y
CONFIG_RANDOMIZE_KSTACK_OFFSET=y
CONFIG_RANDOMIZE_BASE=y       # KASLR
CONFIG_BPF_SYSCALL=n          # No BPF in guest
CONFIG_KPROBES=n
CONFIG_KPROBE_EVENTS=n
CONFIG_DYNAMIC_FTRACE=n

# REMOVE ATTACK SURFACE
CONFIG_SOUND=n
CONFIG_USB=n
CONFIG_FIREWIRE=n
CONFIG_RDS=n
CONFIG_NFSD=n
CONFIG_SMB_FS=n
CONFIG_CIFS=n
CONFIG_NLS=n
CONFIG_PRINTK_NMI=n

# FAST BOOT
CONFIG_PRINTK=y
CONFIG_BLK_DEV_INITRD=y
CONFIG_BINFMT_ELF=y
CONFIG_BINFMT_SCRIPT=y
CONFIG_DEVTMPFS=y
CONFIG_PROC_FS=y
CONFIG_SYSFS=y
CONFIG_KERNEL_GZIP=y          # Faster decompress than XZ
CONFIG_SMP=y                  # Multi-core (can disable for single-core VM)
CONFIG_PREEMPT_VOLUNTARY=y

# CONSOLE
CONFIG_SERIAL_8250=y
CONFIG_SERIAL_8250_CONSOLE=y
CONFIG_VT=y
CONFIG_VT_CONSOLE=y
```

- [ ] **Step 1: Option A — Extract Alpine linux-virt kernel**

`build/kernel/Dockerfile` (Option A):
```dockerfile
FROM alpine:3.21
RUN apk add --no-cache linux-virt
COPY extract-kernel.sh /extract-kernel.sh
RUN /extract-kernel.sh
```

`extract-kernel.sh`:
```sh
#!/bin/sh
mkdir -p /out
cp /boot/vmlinuz-virt /out/vmlinuz
cp /boot/config-virt /out/.config
echo "Kernel version: $(uname -r)" > /out/version.txt
```

Build: `docker build -t alpine-kernel:a -f build/kernel/Dockerfile build/kernel/`
Extract: `docker cp $(docker create alpine-kernel:a):/out/. /tmp/kernel-a/`

- [ ] **Step 2: Option B — Build custom minimal Alpine kernel**

`build/kernel/Dockerfile` (Option B):
```dockerfile
FROM alpine:3.21
RUN apk add --no-cache build-base linux-source linux-headers
COPY minimalize-config.sh /minimalize-config.sh
COPY config-alpine /config-alpine
RUN set -eux \
 && cd /usr/src/linux \
 && cp /config-alpine .config \
 && bash /minimalize-config.sh .config .config.minimal \
 && mv .config.minimal .config \
 && make olddefconfig \
 && make -j$(nproc) bzImage \
 && mkdir -p /out \
 && cp arch/x86/boot/bzImage /out/vmlinuz \
 && cp .config /out/.config
```

`build/kernel/minimalize-config.sh`: Adapted from `../xen-vsock-kernel/scripts/minimalize-config.sh`. Same strategy: disable major subsystems with no dependencies (sound, GPU, USB, etc.), keep Xen PV/PVH support, keep module support (or set CONFIG_MODULES=n for monolithic).

- [ ] **Step 3: Write kernel config validation tests**

`internal/kernel/kernel_test.go`: `TestValidateKernelConfig` (subcases: valid minimal config passes; missing CONFIG_XEN_PVH fails; missing CONFIG_XEN_NET_FRONTEND fails; missing CONFIG_XEN_BLKDEV_FRONTEND fails; config with CONFIG_SOUND=y fails warning); `TestExtractKernelFromApk` (extract from linux-virt apk, assert vmlinuz exists and is >3MB); `TestBuildKernelSmoke` (Option B build, assert vmlinuz exists and is >3MB).

- [ ] **Step 4: Build and test both options**

Build Option A (fast) and Option B (slow). Test both boot in existing qlvm infrastructure with minimal initramfs. Compare boot time and TCB size.

---

## Phase 2: Build the Alpine Rootfs

### Task 2: Alpine Package Installation (apk-based)

**Approach:** Use Alpine's `apk` package manager to install packages into a rootfs directory, then pack as initramfs cpio.gz. This is simpler and more maintainable than collecting static binaries manually.

**Files:**
- Create: `build/rootfs/Dockerfile` (Alpine-based rootfs build)
- Create: `build/rootfs/apk-list.txt` (package list)
- Create: `build/rootfs/install.sh` (apk install script)
- Create: `internal/rootfs/rootfs.go`, `internal/rootfs/rootfs_test.go`

**Required Alpine Packages:**
```apk-list.txt
# Core
busybox            # sh, mount, ip, ifconfig, etc. (already in Alpine base)
openrc             # not needed — we use busybox init directly

# Node.js runtime
nodejs-lts         # Node.js 24.x (Alpine package, musl-linked)
npm                # for pi agent installation

# Pi agent dependencies
git                # version control
ripgrep            # file search (rg)
ca-certificates    # TLS for HTTPS

# Minimal system
mdev               # device manager (instead of udev)
linux-headers      # kernel headers (optional, for module building)
```

**Build Dockerfile:**
```dockerfile
FROM alpine:3.21

# Install packages
COPY apk-list.txt /apk-list.txt
COPY install.sh /install.sh
RUN /install.sh

# Package pi agent
WORKDIR /app
RUN npm install -g --ignore-scripts @earendil-works/pi-coding-agent

# Clean up (remove npm cache, apk cache)
RUN rm -rf /var/cache/apk /root/.npm /tmp/*
```

**install.sh:**
```sh
#!/bin/sh
set -eux
# Create rootfs structure
mkdir -p /rootfs/{bin,sbin,etc,proc,sys,dev,usr/bin,usr/sbin,var,workspace,app}

# Install packages into rootfs
apk add --root /rootfs --initdb --no-cache \
    busybox \
    nodejs-lts \
    npm \
    git \
    ripgrep \
    ca-certificates \
    mdev

# Set up busybox symlinks
/rootfs/bin/busybox --install -s /rootfs/bin
```

**Interfaces:**
- Produces:
  - `func BuildRootfs(apkList string, outputDir string) (string, error)` → returns path to initramfs.cpio.gz
  - `func VerifyRootfs(cpioPath string) error` → extracts and verifies structure

- [ ] **Step 1: Write rootfs build tests**

`internal/rootfs/rootfs_test.go`: `TestBuildRootfs` (build rootfs, extract, assert all required paths exist; init script is executable; node, git, rg present); `TestVerifyRootfs` (valid rootfs passes; missing init fails; missing node fails).

- [ ] **Step 2: Implement apk install**

`build/rootfs/Dockerfile` + `build/rootfs/install.sh`: Install Alpine packages into rootfs directory.

- [ ] **Step 3: Install pi agent**

`npm install -g @earendil-works/pi-coding-agent` inside the rootfs. This installs the pi binary + Node.js dependencies.

- [ ] **Step 4: Pack as initramfs**

`find /rootfs | cpio -H newc -o | gzip -9 > /out/initramfs.cpio.gz`

---

### Task 3: Rootfs Assembly (Alpine structure)

**Files:**
- Create: `build/rootfs/init` (init script)
- Create: `build/rootfs/etc/passwd`, `build/rootfs/etc/group`
- Create: `build/rootfs/Makefile` (rootfs assembly + pack)
- Create: `internal/rootfs/assembly.go`, `internal/rootfs/assembly_test.go`

**Rootfs Structure (Alpine-based):**
```
/
├── init                    # PID 1 script (busybox sh)
├── bin/
│   ├── busybox             # Alpine busybox (musl-linked)
│   ├── sh -> busybox
│   ├── mount -> busybox
│   ├── ip -> busybox
│   └── ... (busybox symlinks)
├── usr/
│   ├── bin/
│   │   ├── node            # Alpine nodejs-lts (musl-linked)
│   │   ├── git             # Alpine git
│   │   └── rg              # Alpine ripgrep
│   ├── lib/
│   │   └── node_modules/   # pi agent dependencies
│   └── local/bin/
│       └── pi              # pi agent binary
├── etc/
│   ├── passwd
│   ├── group
│   └── ssl/
│       └── certs/          # ca-certificates
├── proc/                   # mount point
├── sys/                    # mount point
├── dev/                    # mount point
└── workspace/              # mount point for host files (p9)
```

**Init Script (`/init`):**
```sh
#!/bin/busybox sh

# Mount pseudo-filesystems
mount -t proc none /proc
mount -t sysfs none /sys
mount -t devtmpfs none /dev

# Create console device (Xen PV: hvc0)
mknod /dev/hvc0 c 226 0 2>/dev/null || true

# Parse network from kernel cmdline
CMDLINE=$(cat /proc/cmdline)
IP=$(echo "$CMDLINE" | grep -o 'ip=[^ ]*' | cut -d= -f2)

# Network config (Xen PV: static, no DHCP)
ip link set lo up
ip addr add $IP dev eth0
ip link set eth0 up
ip route add default via ${IP%.*}.1

# Drop privileges to piagent user
exec setpriv --reuid=1000 --regid=1000 --clear-groups \
  /usr/local/bin/pi --workspace /workspace

# Fallback: interactive shell (should not happen)
exec /bin/busybox sh
```

**passwd:**
```
root:x:0:0:root:/root:/bin/sh
piagent:x:1000:1000:pi agent:/workspace:/bin/sh
```

**group:**
```
root:x:0:
piagent:x:1000:
```

# Fallback: interactive shell (should not happen)
exec /bin/busybox sh
```

**Interfaces:**
- Produces:
  - `func AssembleRootfs(binDir string, outputDir string) (string, error)` → returns path to initramfs.cpio.gz
  - `func VerifyRootfs(cpioPath string) error` → extracts and verifies structure

- [ ] **Step 1: Write rootfs assembly tests**

`internal/rootfs/assembly_test.go`: `TestAssembleRootfs` (build rootfs, extract, assert all required paths exist; init script is executable; binaries are present and static); `TestVerifyRootfs` (valid rootfs passes; missing init fails; missing node fails).

- [ ] **Step 2: Implement assembly**

`internal/rootfs/assembly.go`:
1. Create directory structure
2. Copy static binaries
3. Create busybox symlinks
4. Copy pi agent package
5. Write init script
6. Pack as `cpio -H newc -o | gzip -9`

- [ ] **Step 3: Build rootfs**

Run assembly, verify with `file initramfs.cpio.gz` (should be gzip compressed data), test extraction.

---

## Phase 3: Integrate with qlvm

### Task 4: Extend qlvm Template Model

**Current qlvm template model:**
- Template = raw disk image from bootc container (ostree root)
- VM = btrfs reflink (FICLONE) of template
- Boot: kernel + initrd (dracut) from template's ostree tree

**New template type:**
- Template = directory containing `vmlinuz` + `initramfs.cpio.gz` (no disk image)
- VM = direct reference to template (no reflink, no disk copy)
- Boot: kernel + initrd directly (PVH direct boot)

**Files:**
- Create: `internal/template/initramfs.go`, `internal/template/initramfs_test.go`
- Modify: `internal/template/template.go` (add template type field)
- Modify: `internal/cli/template.go` (add `qlvm template create-initramfs` command)

**New CLI commands:**
```
qlvm template create-initramfs <name> --kernel <path> --initramfs <path>
qlvm template list  # shows type: bootc or initramfs
```

**Interfaces:**
- Produces:
  - `type TemplateType string` // "bootc" or "initramfs"
  - `func CreateInitramfsTemplate(name string, kernelPath string, initramfsPath string, templateDir string) error`
  - `func (t *Template) Type() TemplateType`

**Template Directory Structure (initramfs type):**
```
/var/lib/qvm/templates/<name>/
├── meta.toml          # name, type=initramfs, kernel, initramfs paths
├── vmlinuz            # kernel image
└── initramfs.cpio.gz  # rootfs
```

**meta.toml format:**
```toml
name = "pi-agent"
type = "initramfs"
kernel = "vmlinuz"
initramfs = "initramfs.cpio.gz"
```

- [ ] **Step 1: Write template type tests**

`internal/template/initramfs_test.go`: `TestCreateInitramfsTemplate` (create template with kernel+initramfs, verify directory structure and meta.toml); `TestTemplateType` (initramfs template returns "initramfs", bootc template returns "bootc"); `TestInitramfsTemplateLoad` (load template from directory, verify fields).

- [ ] **Step 2: Extend template model**

Modify `internal/template/template.go`:
- Add `type TemplateType string` with constants `TemplateTypeBootc` and `TemplateTypeInitramfs`
- Add `Type() TemplateType` method to Template struct
- Handle both types in template loading

- [ ] **Step 3: Implement create-initramfs command**

`internal/cli/template.go`: Add `qlvm template create-initramfs` command that:
1. Validates kernel and initramfs files exist
2. Creates template directory
3. Copies kernel and initramfs
4. Writes meta.toml

- [ ] **Step 4: Update template list**

`internal/cli/template.go`: Add "type" column to `qlvm template list` output.

---

### Task 5: Extend qlvm VM Creation for Initramfs VMs

**Files:**
- Modify: `internal/cli/vm.go` (handle initramfs templates)
- Modify: `internal/domain/domain.go` (libxl config for initramfs VMs)
- Modify: `internal/domain/libxl.go` (domain creation path)

**Key Differences from bootc VMs:**
- No btrfs reflink (no disk image)
- No ostree root mount
- No per-VM networkd baking (network config is in init script)
- Kernel/initrd come from template directory directly
- No p9 mount by default (optional, passed via kernel cmdline or p9)

**libxl domain config for initramfs VM:**
```go
// Pseudocode — actual libxl bindings vary
domainConfig := libxl.DomainConfig{
    Name:       vmName,
    Type:       libxl.DOMAIN_TYPE_PVH,
    MemoryMB:   vm.MemoryMB,
    VCPUs:      vm.VCPUs,
    Kernel:     template.KernelPath,      // /var/lib/qvm/templates/<name>/vmlinuz
    Ramdisk:    template.InitramfsPath,    // /var/lib/qvm/templates/<name>/initramfs.cpio.gz
    Cmdline:    "root=/dev/ram0 ro console=hvc0 quiet tsc=reliable random.trust_cpu=on",
    // No disk devices
    // VIF via qlvm-vif hotplug (same as bootc VMs)
    OnCrash:    libxl.DOMAIN_DESTROY,
    OnReboot:   libxl.DOMAIN_DESTROY,
    OnShutdown: libxl.DOMAIN_DESTROY,
}
```

**Network:**
- Same OVN/OVS integration as bootc VMs
- `qlvm-vif` hotplug script programs OVS port
- IP address assigned via OVN (same as existing VMs)
- Init script must use the IP from OVN (passed via kernel cmdline or xenstore)

**IP Address Passing:**
Option A (kernel cmdline): Pass IP via `extra` in libxl config
```
Cmdline: "ip=10.100.0.2/24::10.100.0.1::eth0:off console=hvc0 ..."
```
Init script reads from `/proc/cmdline` and configures network accordingly.

Option B (xenstore): Read IP from xenstore in init script
```sh
ip=$(xenstore-read /local/domain/$DOMID/vif/0/ip)
```

**Recommendation:** Option A (kernel cmdline) — simpler, no xenstore dependency in init.

**Interfaces:**
- Produces:
  - `func CreateDomainConfig(vm *VM, template *Template) (libxl.DomainConfig, error)` → handles both template types
  - `func BuildInitramfsCmdline(vm *VM) string` → builds kernel cmdline with IP, console, boot params

- [ ] **Step 1: Write domain config tests**

`internal/domain/domain_test.go`: `TestCreateDomainConfigInitramfs` (initramfs template → PVH domain config with kernel+ramdisk, no disk); `TestCreateDomainConfigBootc` (bootc template → existing config, no regression); `TestBuildInitramfsCmdline` (cmdline includes ip, console, boot params).

- [ ] **Step 2: Extend domain config builder**

Modify `internal/domain/domain.go`:
- Detect template type
- For initramfs: build PVH config with kernel+ramdisk, no disk
- For bootc: existing behavior

- [ ] **Step 3: Handle VM creation flow**

Modify `internal/cli/vm.go`:
- `qlvm vm create` with `--template <initramfs-template>` skips reflink
- Stores VM metadata (template ref, domain config)
- No btrfs operations for initramfs VMs

- [ ] **Step 4: Test VM lifecycle**

Manual test:
```bash
qlvm template create-initramfs pi-agent --kernel build/kernel/bzImage --initramfs build/rootfs/initramfs.cpio.gz
qlvm vm create pi-test --template pi-agent --memory 1024 --vcpus 2
qlvm vm start pi-test
xl console pi-test  # should show pi prompt
qlvm vm stop pi-test
qlvm vm delete pi-test
```

---

### Task 6: Network Integration

**Files:**
- Modify: `internal/domain/libxl.go` (pass IP via cmdline)
- Modify: `build/rootfs/init` (read IP from cmdline)
- Modify: `internal/network/ovn.go` (no changes, reuse existing)

**IP Passing Implementation:**

1. **libxl side** (Go): When creating initramfs VM, build cmdline with IP:
```go
func BuildInitramfsCmdline(vm *VM) string {
    return fmt.Sprintf(
        "root=/dev/ram0 ro console=hvc0 quiet tsc=reliable random.trust_cpu=on "+
        "nosmp noapic no_timer_check mitigations=off module.sig_enforce=1 "+
        "ip=%s/24::%s::eth0:off",
        vm.IP.String(),
        vm.Gateway.String(),
    )
}
```

2. **Init script side** (sh): Parse IP from `/proc/cmdline`:
```sh
#!/bin/busybox sh

# Parse network from kernel cmdline
CMDLINE=$(cat /proc/cmdline)
IP=$(echo "$CMDLINE" | grep -o 'ip=[^ ]*' | cut -d= -f2)

# Mount pseudo-filesystems
mount -t proc none /proc
mount -t sysfs none /sys
mount -t devtmpfs none /dev

# Network config
ip link set lo up
ip addr add $IP dev eth0
ip link set eth0 up
ip route add default via ${IP%.*}.1  # gateway = last octet = 1

# Start agent
exec setpriv --reuid=1000 --regid=1000 --clear-groups \
  /usr/bin/node /usr/lib/pi/bin/pi --workspace /workspace
```

**Note:** This is simplified. Production init script should parse IP properly (handle CIDR, gateway, etc.).

- [ ] **Step 1: Write cmdline parsing tests**

`internal/domain/domain_test.go`: `TestBuildInitramfsCmdline` (subcases: IP 10.100.0.2 → cmdline contains "ip=10.100.0.2/24"; all boot params present).

- [ ] **Step 2: Implement cmdline builder**

Add `BuildInitramfsCmdline` to `internal/domain/domain.go`.

- [ ] **Step 3: Update init script**

Update `build/rootfs/init` to parse IP from `/proc/cmdline`.

- [ ] **Step 4: Integration test**

Create VM, verify it gets correct IP from OVN, verify network connectivity.

---

## Phase 4: Security Hardening

### Task 7: Kernel Hardening Verification

**Files:**
- Create: `internal/security/kconfig.go`, `internal/security/kconfig_test.go`
- Create: `build/security/kconfig-check.sh` (runs kconfig-hardened-check)

**Checks:**
1. `CONFIG_MODULES=n` (monolithic)
2. `CONFIG_STRICT_KERNEL_RWX=y`
3. `CONFIG_FORTIFY_SOURCE=y`
4. No unnecessary subsystems (SOUND, USB, FIREWIRE, etc.)
5. `CONFIG_BPF_SYSCALL=n`
6. `CONFIG_KPROBES=n`

**Tool:** [kconfig-hardened-check](https://github.com/jbruchon/kconfig-hardened-check) — audits kernel config for security issues.

**Interfaces:**
- Produces:
  - `func AuditKernelConfig(config string) (AuditReport, error)`
  - `type AuditReport struct { Pass bool; Warnings []string; Errors []string }`

- [ ] **Step 1: Write audit tests**

`internal/security/kconfig_test.go`: `TestAuditKernelConfig` (subcases: minimal config passes; config with modules fails; config with sound passes warnings).

- [ ] **Step 2: Implement audit**

`internal/security/kconfig.go`: Parse kernel config, check required/disabled options, generate report.

- [ ] **Step 3: Run kconfig-hardened-check**

`build/security/kconfig-check.sh`: Run external tool on final kernel config. Report results.

---

### Task 8: seccomp-BPF Policy

**Files:**
- Create: `build/rootfs/seccomp/profile.bpf` (compiled seccomp policy)
- Create: `build/rootfs/seccomp/policy.json` (human-readable policy)
- Create: `build/rootfs/seccomp/build.sh` (compile policy to BPF)
- Modify: `build/rootfs/init` (load seccomp before exec'ing agent)

**Policy Approach:**
1. **Start permissive:** strace pi agent to capture all syscalls used
2. **Build whitelist:** From strace output, create seccomp policy
3. **Compile:** Use seccomp-tools or libseccomp to compile to BPF
4. **Load in init:** Before exec'ing agent, load seccomp policy

**Expected syscalls (initial estimate):**
```
read, write, openat, close, fstat, stat, lstat,
mmap, munmap, mprotect, brk,
rt_sigaction, rt_sigprocmask, rt_sigreturn,
exit_group, exit, wait4, waitpid,
futex, epoll_create1, epoll_ctl, epoll_wait,
clock_gettime, getrandom, gettimeofday,
access, connect, sendto, recvfrom, sendmsg, recvmsg,
socket, bind, listen, accept, shutdown,
ioctl, fcntl, dup, dup2,
getpid, getppid, getuid, getgid,
uname, getcwd, chdir, mkdir, rmdir, unlink, rename,
```

**Implementation:**

`build/rootfs/seccomp/policy.json`:
```json
[
  { "action": "SCMP_ACT_ALLOW", "names": ["read", "write", "openat", ...] },
  { "action": "SCMP_ACT_KILL", "defaultAction": true }
]
```

`build/rootfs/init` (modified):
```sh
#!/bin/busybox sh

# ... (mounts, network) ...

# Load seccomp policy (if busybox has seccomp support)
# Alternative: use a small static seccomp loader binary
/usr/bin/seccomp-load /etc/seccomp/profile.bpf

# Start agent
exec setpriv --reuid=1000 --regid=1000 --clear-groups \
  /usr/bin/node /usr/lib/pi/bin/pi --workspace /workspace
```

**Note:** busybox may not have seccomp support. May need a small static seccomp loader (compile from libseccomp example).

- [ ] **Step 1: Capture syscalls**

strace pi agent running in existing environment. Record all syscalls.

- [ ] **Step 2: Build policy**

Create `policy.json` with captured syscalls. Add safety margin (include related syscalls).

- [ ] **Step 3: Compile policy**

`build/rootfs/seccomp/build.sh`: Compile policy.json to profile.bpf using seccomp-tools or libseccomp.

- [ ] **Step 4: Test policy**

Run pi agent with seccomp policy. Verify it works. Tighten policy based on errors.

- [ ] **Step 5: Integrate into init**

Update init script to load seccomp policy before exec'ing agent.

---

### Task 9: Xen Security Modules (XSM/FLASK) — Optional

**Files:**
- Create: `build/xen-flask/pi-agent.flask` (FLASK policy for pi-agent VM)
- Modify: `internal/domain/libxl.go` (add seclabel for initramfs VMs)

**Note:** This is optional and requires Xen compiled with XSM support. If current dom0 Xen doesn't have XSM, skip this task.

**FLASK Policy:**
- Restrict hypercalls available to pi-agent VM
- Prevent access to other domains' memory
- Restrict event channel operations

**Implementation:**
```ini
# In libxl domain config:
Seclabel: "flask:untrusted-pi-agent"
```

- [ ] **Step 1: Check XSM support**

Verify current Xen dom0 has XSM/FLASK compiled in. If not, mark task as skipped.

- [ ] **Step 2: Write FLASK policy**

Create policy file restricting pi-agent VM hypercalls.

- [ ] **Step 3: Apply to domain config**

Modify libxl domain creation to include seclabel.

---

## Phase 5: Boot Performance Optimization

### Task 10: Fast Boot Tuning

**Files:**
- Create: `build/bench/boot-time.sh` (measure boot time)
- Modify: `build/kernel/config` (fast boot options)
- Modify: `internal/domain/domain.go` (kernel cmdline tuning)

**Boot Time Targets:**
- Kernel decompress: <1s
- Init script: <0.5s
- Node.js start: <2s
- Pi agent ready: <5s
- Total: <10s

**Optimization Techniques:**

1. **Kernel compression:** GZIP (fastest decompress) vs XZ (smallest size). Choose GZIP.
2. **Kernel cmdline:**
   - `tsc=reliable` — skip TSC verification
   - `random.trust_cpu=on` — trust CPU RNG, no entropy wait
   - `nosmp` — single CPU (skip SMP init)
   - `noapic` — skip IO-APIC setup
   - `no_timer_check` — skip timer probe
   - `mitigations=off` — skip speculative execution mitigations (isolated VM)
   - `lpj=0` — skip delay loop calibration
3. **initramfs compression:** GZIP level 9 (good balance)
4. **Init script:** Minimal operations, no unnecessary mounts
5. **Node.js:** Pre-warm V8 (not applicable for first boot)

**Measurement:**
```bash
time qlvm vm start pi-test
xl console pi-test  # time to first pi prompt
```

- [ ] **Step 1: Write boot time measurement script**

`build/bench/boot-time.sh`: Measure time from `qlvm vm start` to interactive pi prompt. Run multiple times, report average.

- [ ] **Step 2: Baseline measurement**

Run initial build, measure boot time. Record baseline.

- [ ] **Step 3: Apply optimizations**

Iterate on kernel config and cmdline. Measure after each change.

- [ ] **Step 4: Final measurement**

Achieve <10s boot time. Document final configuration.

---

## Phase 6: Build Automation and Testing

### Task 11: Build Automation (GitHub Actions + container packaging)

**Files:**
- Create: `Makefile` (top-level build orchestration)
- Create: `build/kernel/Dockerfile.a` (Alpine linux-virt extraction)
- Create: `build/kernel/Dockerfile.b` (custom minimal kernel build)
- Create: `build/rootfs/Dockerfile` (Alpine rootfs build)
- Create: `build/container/Dockerfile` (container packaging)
- Create: `.github/workflows/build.yml` (GitHub Actions pipeline)

**Build Pipeline (GitHub Actions):**
```
push to main
  → build kernel (Option A or B)
  → build rootfs (apk install + pi agent + pack initramfs)
  → package into container image (kernel + initramfs embedded)
  → push to ghcr.io/jcpowermac/pi-in-xen:latest
  → upload artifacts (vmlinuz, initramfs.cpio.gz, .config)
```

**Container layout (similar to bootc):**
```
Container image: ghcr.io/jcpowermac/pi-in-xen:latest
├── /usr/lib/modules/<version>/vmlinuz      # kernel
├── /usr/lib/modules/<version>/initramfs.img # initramfs (full Alpine rootfs)
├── /etc/os-release                         # Alpine metadata
├── /etc/kernel-version                     # kernel version string
└── Labels:
    io.qlvm.type="pvh-initramfs"
    io.qlvm.kernel="/usr/lib/modules/<version>/vmlinuz"
    io.qlvm.initramfs="/usr/lib/modules/<version>/initramfs.img"
```

**qlvm integration:**
qlvm pulls the container image, extracts kernel + initramfs, creates PVH domain directly. No disk, no btrfs, no ostree. This is similar to how bootc works (container → ostree image), but simpler (container → kernel + initramfs).

**Local build (Makefile):**
```makefile
.PHONY: build kernel-a kernel-b rootfs container extract test clean

build: kernel-a rootfs container

# Option A: Alpine linux-virt kernel (fast)
kernel-a:
	docker build -t alpine-kernel:a -f build/kernel/Dockerfile.a build/kernel/
	docker cp $(docker create alpine-kernel:a):/out/. build/kernel/out/

# Option B: Custom minimal kernel (slow, smaller TCB)
kernel-b:
	docker build -t alpine-kernel:b -f build/kernel/Dockerfile.b build/kernel/
	docker cp $(docker create alpine-kernel:b):/out/. build/kernel/out/

rootfs: kernel-a
	docker build -t alpine-rootfs -f build/rootfs/Dockerfile build/rootfs/
	docker cp $(docker create alpine-rootfs):/out/initramfs.cpio.gz build/rootfs/out/

container: rootfs
	mkdir -p build/container/context
	cp build/kernel/out/vmlinuz build/container/context/
	cp build/rootfs/out/initramfs.cpio.gz build/container/context/initramfs.img
	cp build/container/os-release build/container/context/
	echo "local-build" > build/container/context/kernel-version
	docker build --build-arg KERNEL_VERSION=local-build \
		-t pi-in-xen:latest -f build/container/Dockerfile build/container/context/

extract: container
	CONTAINER=$(docker create pi-in-xen:latest)
	docker cp $$CONTAINER:/usr/lib/modules/local-build/vmlinuz build/kernel/out/
	docker cp $$CONTAINER:/usr/lib/modules/local-build/initramfs.img build/rootfs/out/initramfs.cpio.gz
	docker rm $$CONTAINER

test: extract
	qlvm vm create pi-test --template pi-agent --memory 1024 --vcpus 2
	qlvm vm start pi-test
	sleep 10
	qlvm vm stop pi-test
	qlvm vm delete pi-test
```

**Note on differences from `../os` build process:**
- `../os` uses BlueBuild (RPM/dnf/rpm-ostree modules) → bootc container → ostree image
- This project uses Docker + apk → initramfs cpio.gz → qlvm template
- Why different: Alpine cannot use BlueBuild (RPM-based tooling). ostree requires RPM + dracut + systemd. Alpine uses apk + musl + busybox.
- Both produce bootable VM images, just different build pipelines.

- [ ] **Step 1: Write Makefile**

Create top-level Makefile with build targets.

- [ ] **Step 2: Create build Dockerfiles**

`build/kernel/Dockerfile.a` (Option A: extract linux-virt), `build/kernel/Dockerfile.b` (Option B: custom minimal), `build/rootfs/Dockerfile` (apk install + pi agent).

- [ ] **Step 3: Full build test**

Run `make build`, verify all artifacts produced correctly. Test boot.

---

### Task 12: Documentation

**Files:**
- Create: `README.md` (project overview)
- Create: `docs/architecture.md` (detailed architecture)
- Create: `docs/security.md` (security analysis)
- Create: `docs/performance.md` (boot time analysis)
- Modify: `../qlvm/README.md` (add initramfs template type documentation)

**README.md content:**
- Overview: What this is, why it exists
- Requirements: Xen dom0, qlvm installed
- Build: `make build`
- Usage: `qlvm template create-initramfs`, `qlvm vm create/start/stop/kill/delete`
- Architecture: PVH direct boot, initramfs rootfs, monolithic kernel
- Security: Attack surface analysis, hardening measures
- Performance: Boot time targets and measurements

**Security.md content:**
- Threat model: What we're protecting against
- Defense layers: Xen hypervisor, monolithic kernel, initramfs, seccomp
- Attack surface: What's in the TCB, what's not
- Verification: How to verify security properties

**Performance.md content:**
- Boot time breakdown
- Optimization techniques used
- Benchmarks and measurements

- [ ] **Step 1: Write README.md**

Project overview, build instructions, usage.

- [ ] **Step 2: Write architecture.md**

Detailed design decisions, component diagrams.

- [ ] **Step 3: Write security.md**

Security analysis, threat model, hardening measures.

- [ ] **Step 4: Write performance.md**

Boot time analysis, benchmarks.

- [ ] **Step 5: Update qlvm README**

Document initramfs template type and usage.

---

## Acceptance Criteria

1. **Build:** `make build` produces kernel, rootfs, and qlvm template without errors.
2. **Boot:** `qlvm vm start` → interactive pi prompt in <10 seconds.
3. **Security:**
   - Kernel config passes kconfig-hardened-check with zero errors
   - `CONFIG_MODULES=n` verified
   - No persistent disk (initramfs-only)
   - seccomp policy loaded before agent start
4. **Integration:** All qlvm lifecycle commands work (create/start/stop/kill/delete/list)
5. **Network:** VM gets correct IP from OVN, can reach gateway, no direct LAN access
6. **Statelessness:** VM is fully reproducible from build artifacts
7. **No regressions:** Existing qlvm bootc VMs continue to work correctly

## Rollout Plan

1. **Phase 1-2:** Build kernel + rootfs, verify standalone (manual xl create test)
2. **Phase 3:** Integrate with qlvm, verify lifecycle operations
3. **Phase 4:** Security hardening (kernel audit, seccomp, optional FLASK)
4. **Phase 5:** Performance optimization, achieve <10s boot
5. **Phase 6:** Documentation, final testing, acceptance criteria verification

## Risks and Mitigations

| Risk | Mitigation |
|------|------------|
| Static Node.js not available for musl | Build from source with musl-gcc (Task 2) |
| seccomp policy too restrictive | Start permissive, capture syscalls with strace, tighten iteratively |
| Boot time >10s | Profile boot stages, apply optimizations (Task 10) |
| qlvm integration breaks bootc VMs | TDD: test bootc path doesn't regress (Task 5) |
| Kernel build fails | Use Alpine kernel package as base, apply custom config |
| Network IP passing fails | Test with multiple IP configurations, use kernel cmdline (Task 6) |
| XSM/FLASK not available | Mark as optional (Task 9), don't block rollout |

## References

- [Xen PVH direct boot ABI](https://xenbits.xen.org/docs/unstable/misc/pvh.html)
- [Xen Security Modules (XSM/FLASK)](http://xenbits.xen.org/docs/unstable/misc/xsm-flask.txt)
- [Securing Xen](https://wiki.xenproject.org/wiki/Securing_Xen)
- [Pi Agent containerization docs](https://pi.dev/docs/latest/containerization)
- [Build a Linux that boots in under a second](https://tempmv.cloud/guides/build-a-linux-that-boots-instantly)
- [MicroVM kernel hardening walkthrough](https://openclawsecurity.net/community/microvm-and-gvisor/walkthrough-hardening-the-guest-kernel-for-an-agent-microvm/)
- [Qubes minimal Xen setup (13MB dom0)](https://forum.qubes-os.org/t/running-a-minimal-xen-setup-without-qubes-lessons-learned-from-building-a-13mb-stateless-dom0/40607)
- [Alpine Linux Xen DomU guide](https://wiki.xenproject.org/wiki/Installing_Xen_on_Alpine_Linux)
- [kconfig-hardened-check](https://github.com/jbruchon/kconfig-hardened-check)
- [Unofficial Node.js musl builds](https://unofficial-builds.nodejs.org/)
- Existing: `../qlvm/README.md`, `../qlvm/AGENTS.md`, `../qlvm/docs/superpowers/specs/2026-09-26-qlvm-design.md`
- Existing: `../os/recipes/os-xenguest.yml`, `../os/recipes/os-bolt.yml`
