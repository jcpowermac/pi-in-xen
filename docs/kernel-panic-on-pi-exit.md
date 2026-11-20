# Kernel Panic: "Attempted to kill init!" When the Pi Agent VM Ends

The recurring symptom is the same; it has had **three root causes** as
`build/rootfs/init` evolved. All share the kernel invariant: **if PID 1 (your init)
exits via `exit_group()`, the kernel panics with "Attempted to kill init!"** — there is
no kernel option to disable it. So every shutdown path must either power the VM off
*before* PID 1 exits, or keep PID 1 alive.

```
Kernel panic - not syncing: Attempted to kill init! exitcode=0x00000000
CPU: 1 UID: 0 PID: 1 Comm: init Not tainted 7.3.5 #1 PREEMPT(lazy)
  <TASK>
  do_exit.cold / do_group_exit / __x64_sys_exit_group   <- PID 1 called exit_group(0)
```

`exitcode=0x0` is the tell that PID 1 exited **cleanly** (reached EOF) rather than
crashing with a non-zero code.

## Stage 1 — pi exec'd as init (fixed 2026-10-12)

`init` ended with `exec su - piagent -c /usr/local/bin/pi`. The `exec` replaced PID 1
with the pi agent; when pi exited 0, PID 1 died → panic. **Fix:** run pi as a *child*
of init so init stays PID 1 and can shut down on pi's exit.

## Stage 2 — the debug shell exec'd as init (fixed 2026-10-12, commit 328af11)

Dropping to a shell with `exec su - piagent -c sh` made the *shell* PID 1, so Ctrl+D
(the normal way to leave the shell) exited PID 1 → panic. **Fix:** run the shell through
`conmux` **without** `exec`, so it is a child and Ctrl+D just returns control to init.

## Stage 3 — the final `poweroff` is a no-op (fixed 2026-11-20)

Current `init` runs pi under tmux, bridges the console through `conmux`, and on exit
drops to a non-`exec` `conmux su - piagent -c sh`. Its last line was:

```sh
poweroff
```

That was the bug. busybox's `poweroff` applet (`init/halt.c`) **without `-f` does not
call `reboot(2)`** — it runs `kill(1, SIGUSR2)` and returns 0, expecting a real busybox
**init** to catch SIGUSR2 and power off. But PID 1 here is a bare `busybox sh` script
with no SIGUSR2 handler. So:

- the `poweroff` child (running as root) sends `kill(1, SIGUSR2)`, succeeds, returns 0;
- `poweroff` is the *last* line, so the `sh` immediately hits EOF and calls `exit(0)`
  before the pending SIGUSR2 is ever dispatched;
- PID 1 exits 0 → **panic**.

The same flaw explains the interactive case. In the dropped-to shell you are
**`piagent` (uid 1000)**, not root, and `poweroff` (no `-f`) runs `kill(1, SIGUSR2)` —
but piagent cannot signal root's PID 1 → `EPERM` → the exact
`poweroff: : Operation not permitted` (busybox `bb_perror_nomsg_and_die`).

### Fix

```sh
exec poweroff -f
```

`-f` forces the direct `reboot(RB_POWER_OFF)` syscall as root (`CAP_SYS_BOOT`). On Xen
PVH that is the in-hypervisor `HYPERVISOR_reboot` poweroff — it does **not** depend on a
dom0 libxl event handler (unlike the `RB_AUTOBOOT` reboot-zombie, see
`qlvm/docs/pitfalls/in-guest-reboot-zombie.md`). `exec` replaces PID 1 with the poweroff
process, so there is no shell left that can fall off EOF.

## Why It Matters

- **Unclean shutdown**: the panic skips fsync / graceful teardown. Tolerable for an
  initramfs VM (no persistent disk), but in-memory state (workspace, agent session) is
  lost abruptly.
- **Xen domain state**: after the panic the domain may sit in an inconsistent state in
  Xen, requiring `xl destroy` / `qlvm vm stop`.
- **UX**: the normal "leave the session" path kills the VM with a panic instead of a
  clean poweroff.

## Verification

Rebuild + re-bake, then:

1. `qlvm vm start <vm>` (or create a new one from the re-baked template)
2. `qlvm vm console <vm>`
3. Quit pi → expect "pi agent exited (rc=0), dropping to shell", no kernel panic
4. Leave the shell with **Ctrl+D**. (As `piagent`, a bare `poweroff` fails with
   `Operation not permitted` — no `CAP_SYS_BOOT`. `sudo poweroff -f` also works.)
5. Expected: the domain disappears from `xl list` cleanly — no "Attempted to kill init".

## Related

- `qlvm/docs/pitfalls/in-guest-reboot-zombie.md` — Xen PVH in-guest **reboot**
  (`RB_AUTOBOOT`) zombing because dom0 has no libxl event handler. A *different* path
  from the poweroff no-op fixed here.
- qlvm `vm console` terminal-size sync + Ctrl+] escape
  (`internal/xenctl/xenctl_libxl.go`).
- `on_reboot=` / `on_crash=` libxl options are **irrelevant** here — there is no
  persistent dom0 event loop; the fix must be in-guest (init script).
