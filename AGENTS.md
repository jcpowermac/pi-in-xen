# pi-in-xen

Pi agent VM for a Xen dom0. Architecture, build, and manual usage are in
`README.md`. This file is the **operational map** — what you must know to work the
build, CI, template bake, and the `agent` launcher without rediscovering it.

## End-to-end flow (dom0)

```
git push origin main
  → GH Actions (.github/workflows/build.yml) builds kernel + rootfs + container
  → publishes ghcr.io/jcpowermac/pi-in-xen:latest
sudo make template     # bakes /var/lib/qlvm/templates/jcpowermac-pi-in-xen-sha256:<digest>/
agent                  # one-shot: create + inject config + start + attach an agent VM
```

CI is the canonical build. `make template` bakes from the **ghcr.io** image, not a
local registry — no `localhost:5000` registry is assumed. `TEMPLATE_REF` (Makefile,
line ~70) overrides the source if you ever need to.

## Build (local)

- `make build` = `kernel-b rootfs container` (the default target).
- **Option B is the source-of-truth kernel** (`kernel-b`): minimized linux-7.3.5
  Xen PVH, 9p `trans=xen` built-in, `CONFIG_MODULES=n`. Option A (`kernel-a`,
  linux-virt, 9p as a module) is kept only for fast pre-built boots — the 7.3
  kernel has fixes the older linux-virt lacks. CI defaults to B.
- `make container` builds the qlvm agent-VM template image locally (a manual
  alternative to CI).

## Running the agent VM

- **`agent`** (`/usr/local/bin/agent`) is the one-shot launcher: create + inject
  config + start + attach, auto-named `agent-N`. It is `qlvm/cmd/agent` (built in
  the qlvm `.worktrees/agent-binary` worktree). `-m host[:guest]` adds a 9p share.
- `agent` reads its defaults **from `/etc/qlvm/qlvm.yaml`** (the `agent:` block:
  `template`, `memory_mb`, `vcpus`) **fresh on every invocation** (client-side, so
  no daemon restart after a config edit). To point `agent` at a new baked template,
  edit `agent.template` in that file (root-owned — back it up first). The old value
  kept a stale `pi-in-xen-sha256:<digest>` that still had the bare-`poweroff` bug.
- Manual alternative: `qlvm vm create <name> --template jcpowermac-pi-in-xen
  --type agent --memory 2048 --vcpus 2`, then `qlvm vm start` /
  `sudo qlvm vm console <name>` / `qlvm vm stop|delete`.

## Gotchas

- **Templates are root-owned** — `/var/lib/qlvm/templates` is `root:root`. So
  `qlvm template create`, and the Makefile `template`/`test` targets, must run with
  `sudo` (the Makefile does not add it): `sudo make template`.
- **`--template` resolves by exact dir name or unique prefix** of the TEMPLATE
  column. Each CI push mints a new digest → a new `jcpowermac-pi-in-xen-sha256:<digest>`
  dir, so a bare `jcpowermac-pi-in-xen` prefix becomes ambiguous once a second bake
  exists. Use the full name, or prune old templates.
- **aports HTTP 418 (Option B kernel build)** — `gitlab.alpinelinux.org` rate-limits
  shared CI runner IPs (even a single raw-file `wget`). The aports `virt.x86_64.config`
  base is now **vendored** at `build/kernel/virt.x86_64.config` (the Dockerfile COPYs
  it instead of cloning). Re-copy it only if you intentionally track a newer aports
  config.
- **Shutdown must be `exec poweroff -f`** — bare `poweroff` no-ops (PID 1 is a bare
  `busybox sh`, not busybox init). See `docs/kernel-panic-on-pi-exit.md`.

## Docs

- `README.md` — architecture, build, manual usage, 9p workspace, project structure.
- `docs/kernel-panic-on-pi-exit.md` — the `poweroff -f` fix (3-stage root cause).
- `docs/handoff-qlvm-integration.md`, `docs/handoff-9p-mounting-data.md`,
  `docs/9p-xen-investigation.md` — 9p workspace + qlvm integration history.
