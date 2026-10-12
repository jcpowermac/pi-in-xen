# Kernel Panic When Pi Agent Exits

## Problem

When the pi agent exits inside the agent VM, the kernel panics:

```
Kernel panic - not syncing: Attempted to kill init! exitcode=0x00000000
CPU: 1 UID: 1000 PID: 1 Comm: pi Not tainted 6.12.112-0-virt #1-Alpine
Call Trace:
 <TASK>
 dump_stack_lvl+0x5d/0x90
 panic+0x113/0x2d6
 do_exit.cold+0x15/0x15
 do_group_exit+0x2b/0x80
 __x64_sys_exit_group+0x13/0x20
 ...
```

Observed live 2026-10-12: user quit the pi agent session, kernel panicked ~immediately after.

## Root Cause

`build/rootfs/init` ends with:

```sh
exec su - piagent -c "/usr/local/bin/pi"
```

The `exec` replaces the init process (PID 1) with the pi agent. When pi exits normally (exit code 0), PID 1 dies. The Linux kernel treats exit of PID 1 as fatal — there is no init to reap children or manage the system — so it panics with "Attempted to kill init!".

This is by design in the kernel: `do_exit()` checks if the exiting task is PID 1 and calls `panic()` unconditionally. There is no kernel config to disable this.

## Why It Matters

- **Data loss risk**: The panic is unclean — no fsync, no graceful shutdown. For an initramfs VM (no persistent disk) this is less critical, but any in-memory state (workspace, agent session) is lost abruptly.
- **Xen domain state**: After the panic, the domain may sit in an inconsistent state in Xen, requiring `xl destroy` to clean up.
- **User experience**: Quitting the pi agent (the normal way to end a session) kills the VM with a panic instead of shutting it down cleanly.

## Fix

Run pi as a **child** of init, not as init itself. When pi exits, init performs a clean shutdown.

### Fixed `build/rootfs/init`

```sh
#!/bin/busybox sh
# Alpine initramfs init script for pi agent Xen PVH VM
# PID 1: mount pseudo-fs, configure network, run pi agent, drop to shell on exit

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
if [ -n "$IP" ]; then
    ip link set lo up
    ip addr add "$IP" dev eth0
    ip link set eth0 up
    # Gateway = last octet replaced with 1
    GATEWAY=$(echo "$IP" | awk -F'[./]' '{print $1"."$2"."$3".1"}')
    ip route add default via "$GATEWAY"
fi

# Run pi agent as a child (NOT exec — init must stay PID 1).
# When pi exits (quit, crash, Ctrl+] escape), drop to shell for debugging.
cd /workspace
su - piagent -c "/usr/local/bin/pi"
rc=$?

echo "pi agent exited (rc=$rc), dropping to shell"
echo "Inspect as needed, then run: poweroff"
exec su - piagent -c "/bin/busybox sh"
```

### Key Changes

1. **Removed `exec`** from `su - piagent -c "/usr/local/bin/pi"` — pi runs as a child, init stays PID 1.
2. **Drop to shell on exit** — any exit (quit, crash, Ctrl+] escape) drops to an interactive shell as piagent for debugging.
3. **Manual shutdown** — user types `poweroff` when done. No auto-shutdown, no lost debugging opportunity.
4. **Init reaps pi** — as PID 1, init automatically reaps the child process, so no zombie.

## Verification

After rebuilding the rootfs and template:

1. `qlvm vm create pi-agent --template <new-template>`
2. `qlvm vm start pi-agent`
3. `qlvm vm console pi-agent`
4. Quit the pi agent (e.g., type `exit` or use the agent's quit command)
5. Expected: console shows "pi agent exited (rc=0), dropping to shell" followed by a shell prompt — no kernel panic
6. Type a command to verify the shell works (e.g., `ls /workspace`)
7. Type `poweroff` to shut down; verify domain disappears from `xl list` cleanly
8. Also test: let pi crash or Ctrl+] escape — should also drop to shell, not panic

## Related

- qlvm `vm console` terminal size sync and Ctrl+] escape fix (qlvm repo, `internal/xenctl/xenctl_libxl.go`)
- The `on_reboot=` / `on_crash=` libxl domain config options are **not relevant** here — they require a dom0 event handler to act on domain state changes, and qlvm has no persistent libxl event loop. The fix must be in-guest (init script).
