# pi-in-xen 9p Seed & Workspace Design

**Date:** 2026-11-17
**Topic:** How pi VMs get config, auth, extensions, and git-repo access from dom0 over 9p
**Status:** Design settled; 9p transport verified end-to-end (see
`../9p-xen-investigation.md` §9 for the wire-format root causes)

## Intent

Give every pi VM a small, well-defined way to pull its configuration from
dom0 without baking mutable state into the VM image. The image stays
clean and deterministic (kernel, rootfs, pi binary, extensions); everything
that changes per-host or per-VM (config, secrets, repos, session history)
lives on dom0 and reaches the VM over 9p.

The 9p transport itself is now proven: `mount -t 9p -o trans=xen <tag>
<mountpoint>` works on a Fedora-44 guest against dom0's patched `xen-9pfsd`
— mount, `ls`, read, and a uid-1000 write all verified, with guest writes
landing on the host owned by the share-root owner.

## The four things a pi VM needs

| Thing | Nature | Where it lives | How it reaches the VM |
|---|---|---|---|
| **Pi config** (`pi.json`, `AGENTS.md`, keymaps) | mutable, per-host | dom0 seed dir | 9p, **read-only** seed share |
| **Auth / secrets** (`auth.json`, provider keys) | mutable, sensitive | dom0 seed dir | 9p, **read-only** seed share |
| **Extensions** | code, version-pinned | **baked into the image** | none (in initramfs) |
| **Git repos / workspace** | mutable, per-VM, large | dom0 per-VM dir | 9p, **read-write** workspace share |

Rationale for the split:
- **Extensions are code** → they should be version-pinned and identical
  across VMs, so they go in the image (rebuild to change), not in a live
  mount. Mounting code from dom0 would make every extension edit
  instantly (and silently) affect all running VMs.
- **Config/secrets are data** → they change without a rebuild, and the user
  wants to edit them on dom0. A read-only 9p seed share is editable on the
  host with no VM restart of the image.
- **Git/workspace is data** → per-VM, read-write, potentially large; a
  per-VM rw 9p share on dom0 keeps it persistent and host-inspectable.
  (Fallback for the "clone from network" case: OVN networking already works,
  so `git clone` over the VM's NIC is the alternative when a repo isn't
  pre-placed on dom0.)

## Shares

Each VM gets **two** 9p shares (qlvm `--mount`, in this order — the index is
the 9p tag suffix):

```
<vm>-0  dom0 seed       /var/lib/qlvm/9p/<vm>/seed        (guest: read-only)
<vm>-1  dom0 workspace  /var/lib/qlvm/9p/<vm>/workspace    (guest: read-write)
```

- **Tag** = `P9Tag(vmName, i)` = `<vmname>-<i>` (qlvm `internal/vm/domcfg.go`).
  The guest resolves the tag via the xen 9pfs frontend (`/sys/bus/xen/
  devices/9pfs-<i>`), not a device node.
- **`security_model=none`** — no uid mapping; dom0 uid == guest uid. The dom0
  user (uid 1000, `jcallen`) is the same numeric uid as the guest's `piagent`
  (uid 1000), so ownership "just works".
- **Share root path is `/var/lib/qlvm/9p/`** (not `/var/tmp`) — the daemon
  runs under a systemd unit with `PrivateTmp`, so a share under `/tmp` is a
  different directory to the daemon than to the mount (see investigation §9).
- **Ownership:** the daemon runs as root; on `TCREATE` it `fchown`s the new
  file to the share-root's owner (`xen-9pfsd` fix), so guest `piagent` (uid
  1000) can rewrite files it "owns". Pre-place the seed dir owned by the dom0
  user; the workspace dir likewise.
- **Mount point must be on a writable guest fs.** For ostree VMs the root is
  composefs (read-only) — mount under `/var/...` (the rw `/var` partition),
  e.g. `/var/data`, not `/data`. For the pi agent VM (initramfs root, busybox
  init) the mount point is a plain initramfs dir (see below).

## Wire protocol (the part that took 9 root causes)

Negotiated version is **9P2000.u** (the daemon accepts 9P2000/.L but always
echoes `9P2000.u`), so the guest uses the classic command set — no TGETATTR/
TLOPEN/TREADDIR. Transport is `trans=xen` (grant-table flex-rings), **not**
`trans=virtio`. The daemon must emit:

- **RSTAT** (TSTAT reply) = `u16 prefix` + full `p9_wstat` (the Linux client
  parses it as `"wS"` and ignores the prefix).
- **RREAD** readdir records = bare `p9_wstat` (the client's `p9stat_read`
  parses `"S"`, no prefix). In 9P2000.u the guest reads directories with
  **TREAD**, not TREADDIR.
- `p9_wstat.size = 61 + strlen(name)` (bytes after the size field).

Full field-by-field reference and the RSTAT/RREAD asymmetry: investigation
§9. If the daemon is replaced or upgraded, these must hold or `mount(2)`
returns EFAULT / `ls` desyncs.

## Two guest surfaces (do not conflate)

pi-in-xen is an **agent VM** (PVH, kernel + initramfs root, busybox init, no
systemd). But the same 9p seed/workspace mechanism must also work for
**ostree VMs** (systemd, composefs root), which is how the `9ptest` smoke
VM was built. The mount + seed logic therefore has two implementations that
share the dom0-side contract:

### A. Agent VM (pi-in-xen `init`)

The busybox `init` (PID 1) does the mount and seed, because there is no
systemd. Sequence (after existing proc/sys/dev + network setup):

1. Read the 9p tags from the kernel cmdline — qlvm passes them as
   `qlvm.9p=<seed-tag>:<ws-tag>` (or per-mount `qlvm.mount=<tag>=<path>`);
   see "qlvm changes" below. Fallback: if absent, scan
   `/sys/bus/xen/devices/9pfs-*` and use the tags found.
2. **Mount the workspace** (`<ws-tag>`) at `/workspace` — the pi agent's
   `$HOME`. `/workspace` is a plain initramfs dir (writable), so this needs
   no partition. Mount with `trans=xen`. **Retry loop** (up to ~30s, 250ms
   backoff) until the frontend `state == Connected` — this is the agent-VM
   form of the boot race; init is the natural place to absorb it because it
   runs before anything else and can block.
3. **Mount the seed** (`<seed-tag>`) at a tmpfs/ramfs path (e.g. `/seed`)
   with `trans=xen,ro`. Read-only so the VM can't clobber dom0's config.
4. **Seed the pi home:** copy the seed into `/workspace/.pi`
   (`/workspace` is now the rw workspace share). Only seed files that are
   absent locally, or always overwrite — decision: **always overwrite
   config/secrets from the seed** (dom0 is the source of truth; the VM is
   disposable), but **preserve** `/workspace` subdirs the agent creates
   (`.pi/sessions`, repo checkouts) so a remount/restart doesn't lose work.
   Concretely: `cp -an` (no-clobber) the seed's `.pi` into `/workspace`,
   then force-overwrite the specific mutable files (`pi.json`, `auth.json`)
   from the seed. (Refine the exact file list during implementation.)
5. `chown -R piagent:piagent /workspace/.pi` (the 9p share root is uid 1000
   = piagent, so this is a no-op in the common case but keeps it correct if
   the seed was pre-placed by a different dom0 uid).
6. `cd /workspace` and start pi under tmux (existing behavior).

Because init mounts the workspace *before* starting pi, pi always sees a
populated, host-backed `$HOME`. No in-pi setup step is needed.

### B. Ostree VM (systemd `.service` retry loop, qlvm `surgery.go`) — RESOLVED

qlvm bakes one **`.service`** (retry loop) per `--mount` (implemented in qlvm
`57ee934`; see `SharedMountService`/`BakeMounts`). Unit contract:

```
[Unit]
Description=qlvm 9p share <where> (tag <tag>)
After=local-fs.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/bin/sh -c 'n=0; while [ "$n" -lt 60 ]; do if mkdir -p <where> \
  2>/dev/null && mount -t 9p -o trans=xen <tag> <where> 2>/dev/null; then \
  exit 0; fi; n=$((n+1)); sleep 1; done; echo "...did not come up" >&2; exit 1'

[Install]
WantedBy=multi-user.target
```

- `trans=xen` (not virtio) in the `mount` command.
- `Where` must be on the rw `/var` partition (root is composefs ro); the loop
  retries `mkdir -p` until `/var` is writable.
- No longer a path-unit, so the old "unit name must equal the escaped Where"
  constraint is gone (the path-derived name is kept only for readability).

## Boot mount race

**Symptom:** the manual `mount -t 9p -o trans=xen <tag> <mp>` always works,
but the systemd `.mount` unit at boot fails (or the agent init's first mount
attempt fails) because the xen 9pfs frontend is not yet `Connected` when the
mount is first attempted.

**Observed on the live guest (9ptest, domid 20):** `/sys/bus/xen/
devices/9pfs-0` is present with `state=Connected` and driver `9pfs`, and a
`xen-9pfs-0.device` unit exists — but it reports **`inactive (dead)`** even
while the device is Connected. So `After=xen-9pfs-0.device` alone is not
proven sufficient (an `After=` on a dead device unit is a no-op for
ordering, and `Requires=` would pull in a unit that may never activate).

**Fix — RESOLVED (qlvm `57ee934`):** the live journal showed the `.mount`
failed for a reason *besides* the 9p frontend: **`/var` was not yet writable.**
`/var/data`'s parent `/var` is a separate generated mount (`/dev/xvda4` xfs)
that is down when the `.mount` fires, so `mkdir /var/data` fails on the still-ro
composefs root (`Read-only file system` / `mount point does not exist`). Option 2
above (the `.service` retry loop) was implemented: it retries `mkdir -p` +
`mount`, absorbing *both* the `/var`-not-ready and the 9p-frontend-not-ready
races. `After=local-fs.target` (the dead `xen-9pfs-0.device` is not used for
ordering). Verified: VM boots to `multi-user.target` with `/var/data` mounted
`9p (rw,trans=xen,9p2000.u)` and a guest uid-1000 write landing on the host
share owned by the share root's owner.

The **agent-VM** path (A) sidesteps this entirely: init runs a retry loop
before starting pi, so the race is absorbed by construction.

**Verification required:** reboot an ostree VM with the baked unit and confirm
the mount is up at `multi-user.target` without a manual intervention; reboot
an agent VM and confirm pi starts with a populated `/workspace/.pi`.

## qlvm changes

1. **Lift `p9s` construction into a helper** shared by both domain-config
   paths. Today `DomainConfig` (ostree) builds `p9s` from `m.Mounts` inline;
   `agentDomainConfig` hardcodes `P9S: []DomainP9{}`. Extract
   `func p9sFor(vmName string, mounts []Mount) []DomainP9` and call it from
   both, so an agent VM passed `--mount host:guest` gets real shares.
2. **Pass the tags to the agent guest.** The agent init (A) needs to know the
   9p tags. Add them to the agent kernel cmdline in `agentDomainConfig`:
   `qlvm.9p=<seed-tag>:<ws-tag>` (derived from `P9Tag(m.Name, i)`), so the
   busybox init can mount them without scanning sysfs. (Ostree VMs don't need
   this — the baked `.mount` unit carries `What=<tag>`.)
3. **`SharedMount` ro flag:** the seed share is read-only in the guest. Add an
   optional `RO bool` to `Mount`/`SharedMount` (or derive: index 0 = seed =
   ro) so the `.mount`/init emits `ro` for the seed. Keep it explicit rather
   than implicit-by-index if it costs little.

## pi-in-xen `init` changes

Add the mount + seed phase (surface A, steps 1–6 above) between network setup
and `cd /workspace` / `tmux`. Keep it in busybox `sh` (no new binaries). The
retry loop must be bounded so a missing share doesn't hang boot forever
(fall through to starting pi with a RAM `/workspace` and log a warning).

## Image / build changes (pi-in-xen)

- **Extensions stay baked.** No change to how extensions ship (in the
  initramfs). The seed share carries *config*, not extension code.
- **Seed layout on dom0** (pre-placed by the user or a setup helper):
  ```
  /var/lib/qlvm/9p/<vm>/seed/.pi/pi.json
  /var/lib/qlvm/9p/<vm>/seed/.pi/auth.json
  /var/lib/qlvm/9p/<vm>/seed/.pi/AGENTS.md        (optional)
  /var/lib/qlvm/9p/<vm>/workspace/                 (per-VM, rw, may be empty)
  ```
  Owned by the dom0 user (uid 1000) so guest `piagent` matches.

## Non-goals

- Per-VM config variation that requires a different *image* (still a rebuild).
- A daemon-side uid mapping (`security_model=mapped`); we stay on `none`.
- Live sync of dom0→guest after boot (seed is a boot-time copy; edit on dom0
  + VM restart to pick up, for v1).
- Network `git clone` as the primary repo path (it's the fallback, not the
  default).

## Open items (resolve during implementation)

1. Exact seed-file list to force-overwrite vs. no-clobber (step A.4).
2. Which boot-race fix (service-retry vs. condition) actually holds on a
   clean reboot — verify on the live guest, pick the one that works.
3. `qlvm.9p=` cmdline format (combined `seed:ws` vs. repeated
   `qlvm.mount=tag=path`) — pick one, keep it parseable by busybox `sh`.
4. Whether the seed share is truly `ro` in-guest or just "don't write" by
   convention (ro mount is safer; confirm the daemon tolerates `ro`).

## References

- `../9p-xen-investigation.md` — full root-cause list, wire format, tools
- `qlvm/internal/vm/domcfg.go` — `DomainConfig`, `agentDomainConfig`, `P9Tag`
- `qlvm/internal/ostree/surgery.go` — `SharedMount`, `SharedMountUnit`,
  `BakeMounts`, `MountUnitName`
- `pi-in-xen/build/rootfs/init` — the agent PID-1 script to extend
