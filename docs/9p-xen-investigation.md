# 9p over Xen — investigation notebook (pi-in-xen)

Lab notes for getting 9p (xen-9pfsd) working between dom0 and a qlvm VM, so
pi VMs can share config/secrets/workspace with dom0. Updated 2026-11-17.
Everything here was verified live on the F45 dom0 + Fedora-44 guest.

> **STATUS: RESOLVED (2026-11-17, domid 20).** 9p over Xen now works
> end-to-end — mount, ls, read, and uid-1000 write all verified. See **§9** for
> the full root-cause list and the final wire-format fix. The "CURRENT BLOCKER"
> markers in §3/§4/§5 below are superseded by §9 (they describe the
> pre-fix protocol state).
>
> **Survives-what check (2026-11-17):** daemon fixes are committed in the
> `xen-421` repo (`tools/9pfsd/io.c`); the *deployed* daemon is a bind mount
> at `/usr/libexec/xen/bin/xen-9pfsd` which **does NOT survive a dom0 reboot**
> — redeploy per §10 (rebuild line + `mount --bind`) after any dom0 reboot,
> else the stock Xen 4.21.1 daemon (all bugs) is back. qlvm fixes committed in
> the `qlvm` repo (`internal/ostree/surgery.go` + tests, deployed to
> /usr/local/bin/qlvm). /tmp helper tools die on reboot (rebuild per §6).

## 1. Architecture (verified, not assumed)

- **Backend**: dom0 `xen-9pfsd` (spawned by libxl via `daemon-path=.../usr/libexec/xen/bin/xen-9pfsd`,
  no args; reads xenstore). Source: `xen/tools/9pfsd/` (4.21 tree at
  `/var/home/jcallen/Development/xen-421`; master at `/var/home/jcallen/Development/xen`).
- **Rings**: flex-ring layout. 2 rings (`num-rings=2`). Ring order 9 → 2 MiB
  data region (1 MiB guest→daemon "out", 1 MiB daemon→guest "in").
  - Per ring, frontend publishes `ring-ref<N>` (interface page grant) and the
    interface page holds `refs[8]` (data region grant; only `refs[0]` used).
  - Interface page layout (from `DEFINE_XEN_FLEX_RING_AND_INTF`,
    `xen/include/public/io/ring.h`): `{in_cons, in_prod}` @0, 56 pad,
    `{out_cons, out_prod}` @64, 56 pad, `ring_order` @128, `refs[8]` @132.
  - **Routing**: messages go to ring `tag % num_rings`. TVERSION uses
    `P9_NOTAG` (0xffff) → 0xffff % 2 = **ring 1**. Attach/walk/stat with
    tag 0 → **ring 0**. (This is why traffic appears split across rings.)
  - 9P header on the wire: **7 bytes** = `size(4 LE) + type(1) + tag(2 LE)`.
    Both sides LE (daemon `put_unaligned`, guest `cpu_to_le*`).
- **Guest frontend**: kernel `9pnet_xen` + v9fs, `mount -t 9p -o trans=xen <tag> <dir>`.
  No `/dev/9p` device (that's virtio-only). Transport negotiated via
  event channels (`event-channel-N`) + xenstore state machine
  (frontend `device/9pfs/0/state`, backend `backend/xen_9pfs/<domid>/0/state`;
  4 = Connected).
- **Daemon lifecycle**: libxl starts it once per device; on daemon exit it
  respawns **only if** the stale keys are gone:
  `xs_rm /local/domain/0/backend/xen_9pfs/<domid>/0/state` and
  `/local/domain/0/libxl/xen-9pfs/state` (+`pid`). libxl only respawns on
  VM shutdown/restart or daemon death *if it notices* — with stale
  `state=running` it does nothing.
- **Path**: daemon uses `path=` key from backend dir
  (`/local/domain/0/backend/xen_9pfs/<domid>/0/path`).

## 2. Environment facts (dom0 = F45 ostree, read-only /usr)

- **No dev packages, no network for podman**: build manually.
- **No C compiler by default** — `sudo dnf5 install gcc` once (or use the
  pi-in-xen container).
- **Public Xen headers cloned at `/tmp/9pfscfg`** (from
  `git://git xen.org` tag `xen-4.21.0` — the running Xen is 4.21.1).
  Build line that works:
  ```
  cd /var/home/jcallen/Development/xen-421/tools/9pfsd
  gcc -O2 -D__XEN_TOOLS__ -I/tmp/9pfscfg -I/tmp/9pfscfg/tools/include \
      -o xen-9pfsd-patched *.c /lib64/libxenstore.so.4 \
      /lib64/libxenevtchn.so.1 /lib64/libxengnttab.so.1
  ```
  (Link the versioned .so directly — no `libxenstore.so` symlink without the
  dev package. Output 129 KB unstripped, vs 14 KB system binary — fine.)
- **Deploy over read-only /usr**: `mount --bind <new> /usr/libexec/xen/bin/xen-9pfsd`
  (systemd-tmpfiles doesn't clobber bind mounts; original stays for rollback;
  `mountpoint -q /usr/libexec/xen/bin/xen-9pfsd` to check if bind is live).
- **SELinux**: daemon runs `unconfined_service_t` — not an SELinux issue.
- **`PrivateTmp=true`** on `qlvm-agent.service`: the daemon (agent's child)
  gets a private /var/tmp → share paths under /var/tmp are invisible. Use
  `/var/lib/qlvm/...` (same inode on host and in daemon — verified) or
  /tmp (private for everyone, consistent).
- **xenstore tools**: `/usr/bin/xenstore-ls` exists (use it). `xs` does NOT.
  `xsls` C tool is broken (xs_directory API mismatch) — don't rebuild it.
- **Guest**: `user@10.100.1.11` (domid changes on reboot — currently 20;
  Fedora 44, kernel 7.2.13-200.fc44, ssh with
  `-o BatchMode=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null`.
  No strace in guest. 9p dmesg is silent without debug module params.

## 3. Bugs found & fixed

1. **TVERSION mismatch** (root cause of first EREMOTEIO): daemon accepted
   only `"9P2000.u"` (io.c:735 `strcmp(version, P9_VERSION)`,
   `P9_VERSION "9P2000.u"`), replied `version="unknown"`; guest (defaults to
   9P2000.L, `fs/9p/vfs_super.c:336`) rejects "unknown"
   (`net/9p/client.c:819-832`).
   **Fix applied**: accept `"9P2000.L"` too. Verified: guest now gets
   `RVERSION "9P2000.L"`.
2. **p9_stat() segfault on root fid** (daemon died on TSTAT):
   `fill_p9_stat(..., strrchr(fidp->path, '/') + 1)` — root path is `"."`
   (from `relpath_from_path("/")`, io.c:194-195), no slash → NULL+1 →
   strlen(NULL). Coredump:
   `/var/lib/systemd/coredump/core.xen-9pfsd.0.62b2646a3a2e4a9eacd3bbcb388fc3ca.1179489.*.zst`.
   **Fix applied**: `slash ? slash + 1 : fidp->path`.
3. **qlvm surgery.go** (3 bugs, fixed + tests pass): mount unit name
   `-{index}` suffix; `trans=virtio` → `trans=xen`; `_netdev=true` in
   `[Unit]` → `[Mount]`. (qlvm at /var/home/jcallen/Development/qlvm,
   `sudo -n make container-build`, install /usr/local/bin/qlvm, restart
   qlvm-agent. Build tags: `exclude_graphdriver_btrfs exclude_graphdriver_zfs
   containers_image_openpgp libxl`.)
4. **Open — ENOTSUP on a 19-byte command after RATTACH** (see §5).

## 4. Protocol exchange (decoded from ring bytes)

Working exchange (per mount attempt):
```
ring1: TVERSION "9P2000.L" (tag 0xffff) → RVERSION "9P2000.L"   ✓ (after fix 1)
ring0: TATTACH uname="nobody" → RATTACH (valid qid)             ✓
ring0: ??? 19 bytes, type=0x18(24) → RERROR errno=23 "Operation
       not supported"                                            ✗  ← CURRENT BLOCKER
ring0: TCLUNK → RCLUNK                                           (guest gives up)
```
Daemon dispatch (io.c:1465-1507) handles ONLY: VERSION(100) ATTACH(104)
WALK(110) OPEN(112) CREATE(114) READ(116) WRITE(118) CLUNK(120) STAT(124).
**No FLUSH(108/109), no LOSTAT(126), no SYMLINK, no READDIR, no FSYNC,
no LOCK/GETATTR...** Everything else → `p9_error(ring, hdr.tag,
EOPNOTSUPP)` (that's the ENOTSUP). The "sent unhandled command %u" is
syslog LOG_DEBUG → **not captured by journalctl default (info)** — patch
level or `journalctl -p debug` to see it.

Raw bytes of the mystery 19-byte request (from OUT ring0 offset 29):
`13 00 00 00 18 00 00 | 00 00 00 00 ff 17 00 00 00 00 00 00`
= size 19, type **0x18 = 24**, tag 0, payload `00 00 00 00 ff 17 00 00 00 00 00 00`.
Legacy 9P numbering: 24 = **P9_TEXISTS**. Kernel 7.2 net/9p may use its own
enum values — `grep -rn "= 24\|P9_TEXISTS" net/9p fs/9p` in
`/var/home/jcallen/Development/linux` (local clone! don't re-fetch).
TATTACH payload decoded cleanly: afid=0xffffffff (P9_NOFID), uname "nobody",
aname "", with **2-byte string lengths** in this kernel's 9P2000 codec
(p9pdu codec: strings are `u16 len + chars`). The daemon's p9_readf
handled it fine (strings via "s" — check whether daemon uses 1-byte or 2-byte
lengths: `fill_buffer` "S" = 2-byte, "s" = 1-byte; guest sent 2-byte and it
parsed, so daemon's attach path must read 2-byte or len happened to align).

## 5. Current state (2026-11-17, domid 12)

- Patched daemon `xen-9pfsd-patched` bind-mounted at
  `/usr/libexec/xen/bin/xen-9pfsd`, pid ~1188476 (check `pidof xen-9pfsd`),
  `state=running`, backend `state=4` (Connected) — evtchn/io_thread healthy.
- Guest boots; `data.mount` (baked, Where=/data, trans=xen) **fails**
  (not hangs) — same root cause as manual mount:
  `mount -t 9p -o trans=xen 9ptest-0 /var/data` → `fsconfig() failed:
  Protocol error` (EPROTOTYPE from the RERROR ENOTSUP above).
- Share path: `/var/tmp/qlvm9p/data` (works, but PrivateTmp caveat — move to
  `/var/lib/qlvm/9p/<vm>/data` before real use).
- **Next**: identify the type-24 command (guest kernel source, local clone)
  → either teach daemon (likely TFLUSH/TEXISTS/LSTAT handler or map) or
  patch guest. Candidates to check first in daemon: add FLUSH(108→109) and
  STAT-variant handlers; they're trivial.

## 6. Helper tools (in /tmp; rebuild commands)

All link versioned .so directly. `gcc -o T T.c /lib64/libxengnttab.so.1`
(gnttab) or `/lib64/libxenstore.so.4` (xenstore; needs `-I/tmp` for
/tmp/xenstore.h — which also needs `-I/tmp/9pfscfg` for xen/io/xs_wire.h).

| tool | purpose |
|---|---|
| `xleaf` | print xenstore leaf values (positional paths) |
| `xsls` | **broken** (API mismatch) — use `xenstore-ls` |
| `xsc` | rm xenstore keys |
| `gmap` / `gi2` | map ring interface grants (gmap hardcoded dom11/old refs; **gi2 = dom12, refs 1151/1664**) |
| `gdata`/`gdata3`/`gdata4/5` | dump ring data pages (grant-based) |
| `ringread`/`ringscan`/`ringdump` | read daemon's mapped rings via /proc/PID/mem |
| `rdec` | decode one 9P message |
| `rhist` / `rhist2` / `rhist3` | decode full ring history (stale domids; superseded below) |
| `raw19` | dump raw bytes at fixed offsets (stale) |
| `deccmd2` | decode full ring with cmd names (current; sed domid+ring-ref0 in) |
| `hexoff` | hex dump of ring0 from the first RSTAT message (sed domid+ring-ref0 in) |
| `sd3` | field-by-field decode of one RSTAT payload (sed domid+ring-ref0 in) |

Pattern for a new VM reboot: get new `ring-ref0/1` from
`xenstore-ls /local/domain/<domid>/device/9pfs/0`, sed into the rhist*.c,
rebuild with `/lib64/libxengnttab.so.1`, run as root.

## 7. Key files

- Daemon: `/var/home/jcallen/Development/xen-421/tools/9pfsd/{io.c,xen-9pfsd.c,xen-9pfsd.h}`
  (io.c has both patches applied; P9_CMD_* at top; dispatch 1465; p9_stat ~1264;
  p9_version ~711-740)
- Ring header: `xen/include/public/io/ring.h` (flex ring macro ~line 479)
- qlvm: `internal/ostree/surgery.go` (baked mount units), `agentDomainConfig`
  (hardcodes `P9S: []DomainP9{}` — the ~5-line gap for agent VMs)
- Kernel (local clone!): `/var/home/jcallen/Development/linux-kern`
  (net/9p/trans_xen.c, net/9p/client.c, fs/9p/)
- Fetched kernel copies in /tmp (v7.2): client.c, trans_xen.c, p9proto.c/h
- Spec: `qlvm/docs/superpowers/specs/2026-10-13-qlvm-agent-vm-integration-design.md`
  (deferred 9p for agent VMs — this work reverses that)
- pi-in-xen plan: `docs/superpowers/plans/2026-10-09-pi-agent-xen-minimal-vm.md`
  (Option A kernel = Alpine linux-virt, **no CONFIG_9P_FS** — needs recheck;
  Option B `build/kernel/minimalize-config.sh:207-209` has `CONFIG_9P_FS=y`)

## 9. RESOLVED — 9p over Xen works end-to-end (2026-11-17, domid 20)

**Smoke test PASSED:** `mount -t 9p -o trans=xen 9ptest-0 /var/data` → MOUNT-OK;
`ls`, `cat`, and a uid-1000 guest write all work; guest writes appear on the
host owned by the share-root owner (`jcallen:jcallen`). Ring shows a clean
`TATTACH→TSTAT…→TWALK→TOPEN→TREAD×3` (the TREADs are `ls`) with no retry loop.

### Full root-cause list (all in `xen-421/tools/9pfsd/io.c`)
1. **TVERSION mismatch** — guest negotiates `9P2000.L`; daemon must accept it but
echo back `9P2000.u` to force the classic wire format (guest then avoids
TGETATTR/TREADDIR type-24 cmds).
2. **p9_stat() segfault** — `strrchr(path,'/')+1` on `"/"` → `NULL+1`. Guard the
root case.
3. **PrivateTmp** — share moved to `/var/lib/qlvm/9p/<vm>/data` (daemon runs in a
systemd unit whose /tmp is private).
4. **fill_p9_stat zeroed uid/gid** — everything looked root-owned. Use
`st->st_uid`/`st->st_gid`.
5. **No chown on create** — daemon is root; add `fchown(fd, rootst.st_uid,
rootst.st_gid)` after create so guest users can manage their files.
6. **Missing TFLUSH(108)→RFLUSH(109)** dispatch (added).
7. **Extra `tlen` in the SHARED stat serializer** — see #9; the `'s'` format used
to be `tlen + wstat`.
8. **Wrong stat size** — was `71+namelen`, correct is `61+namelen` (bytes after the
`size` field).
9. **THE final EFAULT: RSTAT vs RREAD stat prefix mismatch.**
   - The Linux client parses **RSTAT** (TSTAT reply) as `"wS"` = a leading u16
     (which it *ignores*) **plus** a full `p9_wstat` (`net/9p/client.c:
p9_client_stat`).
   - It parses each **RREAD** readdir record as a bare `p9_wstat` (`"S"`, via
     `p9stat_read`) — **no** leading prefix. (In `9P2000.u` the guest uses
     TREAD, not TREADDIR, for readdir — `fs/9p/vfs_dir.c:v9fs_dir_readdir`.)
   - The daemon used ONE `'s'` serializer for both, so it can't be right for
     both. The working domid-18 daemon wrote `tlen + wstat` (right for RSTAT, 2
     bytes too many per RREAD record → `ls` desynced). Removing tlen from `'s'`
     fixed RREAD but made RSTAT 2 bytes short → guest `"wS"` read overran →
     `mount(2)` returned **EFAULT**.
   - **Fix:** `'s'` = bare wstat (size=61+namelen). RREAD records use `'s'`
     directly (correct). The **RSTAT handler** (`p9_stat`) writes the extra
     prefix explicitly: `fill_buffer(ring,cmd+1,tag,"us",&prefix,&p9s)` where
     `prefix = 2 + p9s.size` (value ignored by guest). RSTAT payload is now
     2 + (63+namelen) bytes, exactly what `"wS"` consumes.

### Wire-format reference (9P2000.u, this daemon)
- wstat = `size(u16) type(u16) dev(u32) qid(13) mode(u32) atime(u32) mtime(u32)
  length(u64) name(s) uid(s) gid(s) muid(s) ext(s) n_uid(u32) n_gid(u32)
  n_muid(u32)`; with `size = 61 + namelen`.
- RSTAT payload = `u16 prefix` + wstat.   RREAD record = wstat (no prefix).
- p9_read (TREAD) dir branch accounts `p9s.size + 2` bytes per record.

### Baked `var-data.mount` still needs a boot dependency
The manual mount works; the systemd unit still races the 9p frontend at boot
(9pfs-0 not yet Connected). Needs `After=xen-9pfs-0.device`-style ordering or a
retry (WantedBy + `ConditionPathIsMountPoint`/`ExecCondition` loop) before it's
relied on for pi seed.

## 10. Commands (copy-paste)

```sh
# guest
ssh -o BatchMode=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null user@10.100.1.11 '<cmd>'

# daemon status
pidof xen-9pfsd; journalctl -u qlvm-agent --since '-10 min' | grep -i 9p
sudo xenstore-ls /local/domain/0/backend/xen_9pfs
sudo xenstore-ls /local/domain/<domid>/device/9pfs/0      # ring-refN, state

# stale daemon state (after segfault, before VM restart)
sudo /tmp/xsc /local/domain/0/backend/xen_9pfs/<domid>/0/state
sudo /tmp/xsc /local/domain/0/libxl/xen-9pfs/state /local/domain/0/libxl/xen-9pfs/pid

# mount test (in guest, as root)
sudo mount -t 9p -o trans=xen 9ptest-0 /var/data

# rebuild+deploy patched daemon
cd /var/home/jcallen/Development/xen-421/tools/9pfsd && gcc -O2 -D__XEN_TOOLS__ \
  -I/tmp/9pfscfg -I/tmp/9pfscfg/tools/include -o xen-9pfsd-patched *.c \
  /lib64/libxenstore.so.4 /lib64/libxenevtchn.so.1 /lib64/libxengnttab.so.1
sudo mountpoint -q /usr/libexec/xen/bin/xen-9pfsd || sudo mount --bind $PWD/xen-9pfsd-patched /usr/libexec/xen/bin/xen-9pfsd
# then: stop VM, clear stale state, start VM

# qlvm rebuild
cd /var/home/jcallen/Development/qlvm && sudo -n make container-build
sudo cp target/qlvm /usr/local/bin/qlvm && sudo systemctl restart qlvm-agent
```
