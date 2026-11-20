# Handoff: 9p Mounting & Data Location (pi agent VM)

**Date:** 2026-11-18
**Author:** pi session (9p workspace integration)
**Target:** Next session / anyone picking up the 9p workspace + mount-path work

## TL;DR

- The pi agent VM's `$HOME` is **`/var/data`** in the guest — a 9p share
  (9P2000.u, `trans=xen`) backed by a real directory on **dom0** at
  **`/var/lib/qlvm/9p/<name>/data`**.
- The data physically lives on **dom0**, not in the VM and not in the ramdisk.
  The VM's `/var/data` is only the 9p mount point; the real files are the dom0
  dir. Every write the pi agent makes in its home lands in
  `/var/lib/qlvm/9p/<name>/data` on dom0 (inspectable from dom0).
- Each agent VM gets its **own** isolated host dir (keyed by VM name), so
  multiple pi VMs run side by side without sharing state.
- **Presenting data to the VM** (docs, git repos) already works today via
  `qlvm vm create --mount host:guest` (repeatable) — see §6.1. This is now
  documented in both READMEs (2026-11-18 follow-up).
- The **pi home** mount path is a **hardcoded constant** in both repos — it is
  *not* a user-configurable parameter. Making it configurable is the remaining
  open item (see §6.2).

## 1. Where the data actually lives

| View | Path | What it is |
|------|------|------------|
| **dom0 (host)** | `/var/lib/qlvm/9p/<name>/data` | The real files. Root of the 9p share. Inspectable from dom0. |
| **guest** | `/var/data` | The 9p mount point. This is the pi agent's `$HOME`. |
| **VM ramdisk** | `/var/data` | Just an empty mount-point dir in RAM; the real data is the 9p share. |

The pi's config, secrets, and session logs live here (e.g.
`/var/lib/qlvm/9p/<name>/data/.pi/agent/{auth.json,settings.json,sessions/}`).

- Inspect from dom0: `ls -laR /var/lib/qlvm/9p/<name>/data`
- Inspect from guest (console): `ls -laR /var/data`
- Live dirs today: `9ptest`, `pi9p`, `pi9p-test` (one per agent VM).

## 2. The two mount mechanisms

There are **two** code paths that bring a 9p share up in a guest, selected by
VM type. Both use `trans=xen` and both use a **retry loop** (the dom0
`xen-9pfsd` backend and the guest 9p frontend are not ready immediately after
boot, so a single mount attempt races and fails).

### 2a. Agent VMs (the pi agent — busybox init, no systemd)

dom0 side (qlvm), at `vm create`:
1. **Create + chown the share dir** — `provisionAgentHomeHost`
   (`qlvm/internal/vm/create.go`): `mkdir -p /var/lib/qlvm/9p/<name>/data`
   and `chown 1000:1000` (the pi agent uid). Rolled back if meta-save fails.
2. **Add the 9p share** to the libxl domain config
   (`qlvm/internal/vm/domcfg.go`, `agentDomainConfig`):
   tag `<name>-0`, guest `/var/data`, path `/var/lib/qlvm/9p/<name>/data`,
   `security_model=none`, type `xen9pfsd`.
3. **Add the kernel cmdline** `qlvm.mount=<name>-0=/var/data`.

guest side (`pi-in-xen/build/rootfs/init`):
1. Read `/proc/cmdline`; for each `qlvm.mount=<tag>=<path>`:
2. Mount with a retry loop (up to 60 s):
   `mount -t 9p -o trans=xen,cache=none <tag> <path>`.
3. `chown -R piagent:piagent <path>`.

The init is **path-generic** (it mounts at whatever `<path>` the cmdline
carries), but the pi `$HOME` is separately fixed at `/var/data` in the rootfs
(see §6 — that's why changing the guest path touches both repos).

### 2b. Ostree VMs (systemd)

qlvm bakes one **oneshot `.service`** per share into the deployment `/etc`
overlay (`qlvm/internal/ostree/surgery.go`, `SharedMountService`). A plain
`Type=9p` `.mount` unit races at boot (the writable `/var` overlay may not be
up yet, so the mountpoint can't be created on the still-ro composefs root, and
the 9p device unit stays `inactive (dead)`), so the service runs a retry loop:
`mkdir -p <where> && mount -t 9p -o trans=xen <tag> <where>` up to 60×.
No kernel-cmdline mechanism is involved for ostree VMs.

## 3. Why `trans=xen` (not `trans=virtio`)

The dom0 backend is Xen's `xen-9pfsd`, which speaks **Xen's 9pfs protocol**
(evtchn + grant-table rings, `xen/interface/io/9pfs.h`), not the virtio-9p
protocol. The guest's `9pnet_xen` frontend resolves the share by the **9p tag**
in `What`. `trans=virtio` would look for a `/dev/9p` node that `xen9pfsd` never
creates. (The qlvm README previously said `trans=virtio` — that was corrected
2026-11-18.)

## 4. The dom0 backend: `xen-9pfsd` (patched)

Xen's stock `xen-9pfsd` only handled a small 9P2000.L command set, so a modern
Linux guest (6.12 / 7.3.5, 9P2000.u) hit `EOPNOTSUPP` / `EINVAL` / `EBADF`. It
is **patched** in the xen-421 fork:

- **Repo/branch:** `github.com/jcpowermac/xen`, branch `stable-4.21`
  (fork of `xen-project/xen`).
- **What:** added 9P2000.u/.L handlers (`TCREATE`/`TREMOVE`/`TWSTAT`/
  `TRENAME`/`TFSYNC`/…), accepted `P9_OAPPEND` in TOPEN, raised
  `MAX_OPEN_FILES` 5→256, reclaimed stale fids (guest drops a fid on a walk
  error without clunking), fixed a `scan_backend` NULL deref.
- **Deploy:** built to `xen-421/tools/9pfsd/xen-9pfsd-patched` and
  **bind-mounted** over `/usr/libexec/xen/bin/xen-9pfsd` on dom0 (the dom0
  `/usr` is a read-only overlay, so bind-mount is how the patched binary is
  used). One daemon per active agent VM.
- **Ownership:** the daemon runs as **root**; with `security_model=none` it
  attributes guest writes to the **share root's owner** — hence the
  `chown 1000:1000` (the guest `piagent` is uid 1000, so its files are
  writable by it).

## 5. Tag numbering

- **Agent VM:** the pi home is always **`<name>-0`** (index 0). Any `--mount`
  shares continue at `<name>-1`, `<name>-2`, …
- **Ostree VM:** `--mount` shares are 0-based (`<name>-0`, `<name>-1`, …).

## 6. Mount paths: what is, and isn't, configurable

### 6.1 Presenting data to the VM — already works (`--mount`)

`--mount host:guest` (repeatable, honored at `vm create` for both ostree and
agent VMs) exports *any* existing dom0 directory into the guest at *any*
guest path: `--mount /srv/docs:/var/data/docs`,
`--mount /srv/repos/proj:/var/data/repos/proj`. No copy, read-write, host
path stays visible on dom0. On agent VMs these shares take tags
`<name>-1`… and are passed to the guest as extra `qlvm.mount=` cmdline
entries; the init's retry loop mounts them the same as the pi home. Limitation:
mounts are fixed at create time (recorded in `meta.yaml`); changing the set
means recreating the VM. (Documented in the qlvm README "Shared mounts (9p)"
→ "Presenting data to a VM" and the pi-in-xen README "Persistent workspace".)

### 6.2 The pi home path: a constant, not a parameter

Neither side of the *pi home* path is user-configurable today.

- **Guest path:** `const agentHomeGuest = "/var/data"` —
  `qlvm/internal/vm/domcfg.go:67`.
- **Host path:** `agentHomeHost(name) = filepath.Join("/var/lib/qlvm/9p",
  name, "data")` — `domcfg.go:73-75`. (Per-VM by `<name>`; the base
  `/var/lib/qlvm/9p` and the `data` subdir are fixed.)
- **The only arbitrary-path mechanism** is `--mount host:guest`, which adds
  *extra* shares; it does **not** change the pi home.

The guest path `/var/data` is baked into **both** repos:
- qlvm: `agentHomeGuest` + the `qlvm.mount=` cmdline.
- pi-in-xen: `init` does `cd /var/data`; `etc/passwd` sets the piagent home to
  `/var/data`; the rootfs `Dockerfile` `chown`s `/var/data`.

**Open decision — make it configurable. Options:**
- `qlvm vm create --pi-home-guest <path>` (per-VM flag);
- a `/etc/qlvm/qlvm.yaml` config key (global default);
- a pi-in-xen kernel-cmdline override (guest-side).
Whichever is chosen, if the *guest* path moves you must update both repos
(§6 bullet above). If only the *host* base dir should move, it's qlvm-only.

## 7. Multiple VMs

- Each agent VM mounts its **own** `/var/lib/qlvm/9p/<name>/data` (per-name),
  so there is no sharing or conflict between pi VMs.
- The guest path `/var/data` is the same string in every VM, but each maps to a
  different host dir.
- To *explicitly* share one host dir between two VMs, point both at it via
  `--mount /same/host/dir:/shared`. That is a real shared 9p mount with
  `security_model=none` and **no cross-VM locking** — concurrent writes to the
  same files can conflict.

## 8. Key code locations

| What | Where |
|------|-------|
| Guest 9p mount retry loop | `pi-in-xen/build/rootfs/init` (the `qlvm.mount=` handling) |
| pi `$HOME` guest const + host path | `qlvm/internal/vm/domcfg.go` (`agentHomeGuest`, `agentHomeHost`, `agentDomainConfig`) |
| dom0 share dir create + chown | `qlvm/internal/vm/create.go` (`provisionAgentHomeHost`) |
| ostree 9p `.service` | `qlvm/internal/ostree/surgery.go` (`SharedMountService`) |
| 9pfsd backend patch | `xen-421/tools/9pfsd/` (`io.c`, `xen-9pfsd.c`, `xen-9pfsd.h`) |
| pi home fixed in rootfs | `pi-in-xen/build/rootfs/etc/passwd` (piagent home `/var/data`) + `init` `cd /var/data` |

## 9. State: done / pending

**Done**
- ✅ pi home 9p works end-to-end — the pi agent runs with its workspace on
  `/var/data` (backed by the per-VM dom0 dir).
- ✅ `xen-9pfsd` patched; a clean build shows **0 EINVAL / EBADF /
  EOPNOTSUPP** across ~12k ops (mkdir, deep mkdir, write, rename, fsync all
  work).
- ✅ `fd` + `ripgrep` baked into the rootfs (verified in-guest: `fd 10.2.0`,
  `ripgrep 14.1.1`).
- ✅ READMEs corrected (pi-in-xen + qlvm) — pushed.
- ✅ Commits pushed: `jcpowermac/pi-in-xen`, `jcpowermac/qlvm`,
  `jcpowermac/xen` (stable-4.21 fork).

**Pending / open**
- ❌ **Make the pi home mount path a variable/parameter** (the main open item
  — see §6.2; needs a design decision: flag vs config key vs cmdline). Note
  the resolved host path should be persisted in `Meta` at create time so a
  later config change doesn't silently repoint existing VMs' shares; the
  start path (`xenctl` → `DomainConfig(vmDir, m, tpl)`) has no access to the
  config, only `Meta`. Presenting *other* data is already covered by
  `--mount` (§6.1).
- ❌ `Makefile` `test: template` references a `template` target that doesn't
  exist (minor; `make test` currently no-ops/fails on that dep).
- ❌ `xen-9pfsd` patch doesn't yet handle `TGETATTR`(24)/`TSETATTR`(26) —
  only matters if a guest negotiates 9P2000.L feature extensions (current
  guests use 9P2000.u).
- ❌ `pi9p-test`'s running `initramfs` was **swapped in-place** for testing
  (not via the template); recreating that VM from the template needs the
  freshly-built `alpine-rootfs` image (which is current: has fd+rg+clean init).
- ❌ pi agent needs `/login` (provider config) to have models — unrelated to
  mounting, but the agent shows "No models available" until then.

## 10. How to verify

- **dom0 (real data):** `ls -laR /var/lib/qlvm/9p/<name>/data`
- **guest (the mount):** console → `ls -laR /var/data`
- **daemon up:** `pgrep -x xen-9pfsd` (one per active agent VM); the patched
  binary is `/usr/libexec/xen/bin/xen-9pfsd` (bind-mounted from
  `xen-421/tools/9pfsd/xen-9pfsd-patched`).
- **9p is clean:** the daemon's stderr log shows 0 `errno=22` (EINVAL) /
  `errno=9` (EBADF) / `errno=95` (EOPNOTSUPP).
