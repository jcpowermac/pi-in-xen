# Handoff: Extend qlvm for pi-in-xen Container Templates

**Date:** 2026-10-12
**Author:** Previous session (pi agent in Xen PVH VM project)
**Target:** New pi agent to extend qlvm (`../qlvm`) for container-based kernel+initramfs VMs

## Context

The `pi-in-xen` project (`/var/home/jcallen/Development/pi-in-xen`) builds a minimal Xen PVH VM that runs the pi agent (`pi.dev`) in ~1.0s boot time. The VM is distributed as a container image (`ghcr.io/jcpowermac/pi-in-xen:latest`) with the kernel and initramfs embedded.

**Current state (2026-10-12):**
- ✅ Container image builds successfully on GitHub Actions (run 38292782472)
- ✅ Kernel + initramfs boot correctly on Xen PVH (tested with `xl create`)
- ✅ Pi agent TUI displays in ~1.0s
- ✅ All initramfs bugs fixed (nested dirs, busybox symlinks, /usr/bin/env, permissions)
- ❌ qlvm cannot yet create VMs from this container (only supports ostree/bootc raw disk images)

**Verified boot sequence (from console log):**
```
[0.000s] Linux version 6.12.112-0-virt
[0.135s] Booting kernel on Xen PVH
[0.198s] Unpacking initramfs...
[0.931s] Freeing initrd memory: 61920K
[0.942s] Run /init as init process
[~1.0s] Pi v1.1.0 TUI displayed
```

**Goal:** Extend qlvm to support a new template type (`pvh-initramfs`) that extracts kernel + initramfs from a container image and boots them directly (no disk, no ostree, no systemd).

## Repositories

| Repo | Path | Purpose |
|------|------|---------|
| pi-in-xen | `/var/home/jcallen/Development/pi-in-xen` | Builds the pi agent VM container |
| qlvm | `/var/home/jcallen/Development/qlvm` | Go Xen VM manager (target of this work) |
| os | `/var/home/jcallen/Development/os` | BlueBuild Fedora image recipes (reference) |
| xen-vsock-kernel | `/var/home/jcallen/Development/xen-vsock-kernel` | Minimal Fedora Xen kernel (reference) |

## Container Image Layout

The pi-in-xen container image (`ghcr.io/jcpowermac/pi-in-xen:latest`) has this layout:

```
/usr/lib/modules/<version>/vmlinuz      # Kernel (Alpine linux-virt 6.12.x)
/usr/lib/modules/<version>/initramfs.img # Initramfs (cpio.gz, ~61MB)
/etc/os-release                         # Alpine 3.21
/etc/kernel-version                     # Version string (e.g. "6.12.112-0-virt")
```

Container labels:
```
io.qlvm.type="pvh-initramfs"
io.qlvm.kernel="/usr/lib/modules/<version>/vmlinuz"
io.qlvm.initramfs="/usr/lib/modules/<version>/initramfs.img"
```

## Current qlvm Architecture

### Template System (`internal/template/template.go`)

Current flow: `pull container → run osbuild image-builder → adopt raw disk → bake ostree → save META`

Key types:
```go
type Template struct {
    Dir        string `yaml:"dir"`
    Image      string `yaml:"image"`
    Digest     string `yaml:"digest"`
    KernelVer  string `yaml:"kernel_ver"`
    RootDev    string `yaml:"root_dev"`      // e.g. "/dev/xvda"
    RootFlags  string `yaml:"root_flags"`    // e.g. "subvol=root"
    OstreePath string `yaml:"ostree_path"`   // e.g. "/ostree/deploy/..."
}
```

The template dir contains:
- `template.raw` - the raw disk image (ostree-based)
- `vmlinuz` - kernel
- `initramfs` - initramfs
- `META` - YAML metadata

### VM Creation (`internal/vm/domcfg.go`)

Current `DomainConfig()` produces:
```go
&DomainSpec{
    Type:        "PVH",
    Name:        m.Name,
    UUID:        m.UUID,
    Kernel:      filepath.Join(vmDir, "vmlinuz"),
    Ramdisk:     filepath.Join(vmDir, "initramfs"),
    Extra:       []string{"root=" + tpl.RootDev, "subvol=root", "ostree=...", "systemd.default-target=multi-user.target", "console=hvc0"},
    MaxVcpus:    m.VCPUs,
    TargetMemkb: m.MemoryMB * 1024,
    Disks:       []DomainDisk{{PdevPath: filepath.Join(vmDir, "disk.img"), Vdev: "xvda", Format: "raw", Readwrite: 1}},
    Nics:        []DomainNic{{Mac: m.MAC, Script: "vif-ovn", Nictype: "vif"}},
    P9S:         p9s,
}
```

### Kernel Management (`internal/vm/kernel.go`)

`EnsureKernel()` seeds `vmlinuz` + `initramfs` from template dir to VM dir.

## Work Required

### Task 1: Add template type detection

In `internal/template/template.go`:

1. After pulling the container, inspect its labels (`io.qlvm.type`)
2. If `io.qlvm.type == "pvh-initramfs"`, use a new extraction path instead of osbuild
3. Add a `Type` field to the `Template` struct: `Type string `yaml:"type"`` (values: `"ostree"` or `"pvh-initramfs"`)

### Task 2: Implement container extraction for pvh-initramfs

New function in `internal/template/` (e.g., `extract.go`):

```go
func ExtractPvhInitramfs(ctx context.Context, p Podman, dir, ref string) (*Template, error) {
    // 1. Create a container from the image (read-only)
    // 2. Extract /usr/lib/modules/<version>/vmlinuz to dir/vmlinuz
    // 3. Extract /usr/lib/modules/<version>/initramfs.img to dir/initramfs
    // 4. Extract /etc/kernel-version to dir/kernel-version
    // 5. Return Template{Type: "pvh-initramfs", KernelVer: ..., Dir: dir, ...}
}
```

Use podman bindings (`pkg/bindings`) to:
- `containers.Create()` with the image
- `containers.CopyFilesFromContainer()` to extract files
- `containers.Remove()` to clean up

Alternatively, use `podman run --rm <image> cat /path/to/file > local/file` via the podman exec API.

**Note:** The container may use `latest` tag - resolve to digest for cache key.

### Task 3: Modify Ensure() to handle both template types

In `internal/template/template.go`, modify `Ensure()`:

```go
func Ensure(ctx context.Context, p Podman, o EnsureOpts) (*Template, error) {
    digest, err := p.Pull(ctx, o.Ref)
    // ...
    dir := DirFor(o.Root, slugFromRef(o.Ref), digest)
    if t, err := LoadMeta(dir); err == nil && t.Digest == digest {
        return t, nil
    }
    
    // Check container type from labels
    ctype, err := InspectContainerType(ctx, p, o.Ref)
    if err != nil {
        return nil, err
    }
    
    if ctype == "pvh-initramfs" {
        // New path: extract kernel + initramfs
        t, err := ExtractPvhInitramfs(ctx, p, dir, o.Ref)
        if err != nil {
            return nil, err
        }
        t.Digest = digest
        t.Image = o.Ref
        return t.SaveMeta(dir), nil
    }
    
    // Existing path: osbuild image-builder
    // ...
}
```

Add `InspectContainerType()` to read the `io.qlvm.type` label via `images.Inspect()`.

### Task 4: Modify DomainConfig for pvh-initramfs VMs

In `internal/vm/domcfg.go`, modify `DomainConfig()`:

```go
func DomainConfig(vmDir string, m *Meta, tpl *template.Template) *DomainSpec {
    var extra []string
    var disks []DomainDisk
    
    if tpl.Type == "pvh-initramfs" {
        // No disk, no ostree, no systemd
        extra = []string{"console=hvc0", "init=/init"}
        disks = nil // No disk
    } else {
        // Existing ostree path
        extra = []string{"root=" + tpl.RootDev, ...}
        disks = []DomainDisk{{...}}
    }
    
    return &DomainSpec{
        Type:        "PVH",
        Name:        m.Name,
        UUID:        m.UUID,
        Kernel:      filepath.Join(vmDir, "vmlinuz"),
        Ramdisk:     filepath.Join(vmDir, "initramfs"),
        Extra:       extra,
        MaxVcpus:    m.VCPUs,
        TargetMemkb: m.MemoryMB * 1024,
        Disks:       disks,
        Nics:        []DomainNic{{Mac: m.MAC, Script: "vif-ovn", Nictype: "vif"}},
        P9S:         p9s, // May be empty for initramfs VMs
    }
}
```

### Task 5: Handle network configuration

For pvh-initramfs VMs, network is configured via kernel cmdline (`ip=` parameter).

In `DomainConfig()`, if the VM has a network config, add:
```go
extra = append(extra, "ip="+ipConfig)
```

Where `ipConfig` format is: `ip=<ip>::<gw>:<netmask>:<hostname>:<dev>:none`

The init script (`/init` in the initramfs) parses this from `/proc/cmdline` and configures the interface.

### Task 6: Update CLI commands

In `internal/cli/template.go`:
- `template list` should show the template type (ostree vs pvh-initramfs)
- `template create` should work for both types

In `internal/cli/create.go`:
- `vm create` should accept pvh-initramfs templates
- May need a `--no-disk` flag or auto-detect from template type

### Task 7: Update META format

Add fields to `Template` struct:
```go
type Template struct {
    Type       string `yaml:"type"`        // "ostree" or "pvh-initramfs"
    Dir        string `yaml:"dir"`
    Image      string `yaml:"image"`
    Digest     string `yaml:"digest"`
    KernelVer  string `yaml:"kernel_ver"`
    RootDev    string `yaml:"root_dev"`    // Empty for pvh-initramfs
    RootFlags  string `yaml:"root_flags"`  // Empty for pvh-initramfs
    OstreePath string `yaml:"ostree_path"` // Empty for pvh-initramfs
}
```

Backward compatibility: existing META files without `type` field should default to `"ostree"`.

## Testing

### Local testing without qlvm changes

Test the VM directly with xl (already working):
```bash
xl create pi-test.cfg
xl console pi-test
```

Test config (`pi-test.cfg`):
```
name = "pi-test"
type = "pvh"
memory = 1024
vcpus = 2
kernel = "/var/home/jcallen/Development/pi-in-xen/artifacts/pi-agent-xen-pvh/kernel/out/vmlinuz"
ramdisk = "/var/home/jcallen/Development/pi-in-xen/artifacts/pi-agent-xen-pvh/rootfs/out/initramfs.cpio.gz"
extra = "console=hvc0 init=/init"
```

### After qlvm changes

1. `qlvm template create ghcr.io/jcpowermac/pi-in-xen:latest`
2. Verify template dir contains `vmlinuz`, `initramfs`, `META` (with `type: pvh-initramfs`)
3. `qlvm create pi-agent-test ghcr.io/jcpowermac/pi-in-xen:latest --memory 1024 --vcpus 2`
4. Verify VM starts with no disk, kernel boots, pi agent TUI appears
5. `qlvm destroy pi-agent-test`

## Key Files to Modify

| File | Changes |
|------|---------|
| `internal/template/template.go` | Add `Type` field, modify `Ensure()`, add type detection |
| `internal/template/extract.go` (new) | Container file extraction for pvh-initramfs |
| `internal/vm/domcfg.go` | Handle pvh-initramfs in `DomainConfig()` |
| `internal/cli/template.go` | Show template type in list output |
| `internal/cli/create.go` | Handle pvh-initramfs VM creation |

## Constraints (from qlvm AGENTS.md)

- **No shelling out** to CLIs (use podman bindings, xenlight, etc.)
- **Xen version skew**: builder headers ≤ dom0 runtime (Xen 4.21.2)
- **Clean repo**: no vendor names, no real IPs
- **Tests**: all changes need tests (Go test files)

## References

- pi-in-xen plan: `docs/superpowers/plans/2026-10-09-pi-agent-xen-minimal-vm.md`
- qlvm design: `docs/superpowers/specs/2026-09-26-qlvm-design.md`
- qlvm AGENTS.md: `AGENTS.md` (read fully before making changes)
- Container build: `build/container/Dockerfile` (pi-in-xen repo)
- Init script: `build/rootfs/init` (pi-in-xen repo)
- Working xl config: `pi-test.cfg` (pi-in-xen repo)

## Bugs Fixed in This Session (for reference)

These bugs were in the pi-in-xen Dockerfile and init script, now fixed and pushed:

1. `cp -a /lib /rootfs/lib` created nested `/rootfs/lib/lib/` → use `cp -a /lib/. /rootfs/lib/`
2. `busybox --install -s /rootfs/bin` created symlinks to `/rootfs/bin/busybox` → use `chroot`
3. Missing `/usr/bin/env` → add symlink
4. `--workspace` not a valid pi option → use `cd /workspace`
5. `/workspace` owned by root → `chown -R 1000:1000 /rootfs/workspace /rootfs/var`
6. `chroot /rootfs /bin/busybox` failed (no musl libs yet) → copy `/lib` before busybox install

Boot time: ~1.0s from power-on to pi agent TUI.

**Known pi agent behavior:**
- Session directory is `/workspace/.pi/agent/sessions/<name>` where `<name>` is derived from the working directory
- `fd` (ripgrep alternative) download fails without network (non-fatal warning)
- No models available without API key (use `/login` in pi TUI to configure)
