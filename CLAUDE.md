# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

NixOS system flake for host `BLACK-BOX` (single-user desktop/workstation, i5-9300H + NVIDIA PRIME). `networking.hostName` and the flake output name must both stay `BLACK-BOX` — `nh`/`nixos-rebuild` resolve the config by that name.

## Commands

| Command | What it does |
|---|---|
| `rebuild` | `nh os switch` — apply config changes live. Wraps the switch so a silent no-op (e.g. a shadowed `sudo env`, see Gotchas) is reported instead of exiting 0 — trust this wrapper's output over a bare exit code. |
| `nh os build` | Build the closure without switching — use this to check a change compiles before `rebuild`. |
| `update` | `nh os switch --update` — bump flake inputs, then rebuild. |
| `nix flake check` | Validate the flake (evaluates the `nixosConfigurations.BLACK-BOX` output). |
| `gc` | `nh clean all --keep-since 7d --keep 5 --no-direnv` — prune old generations. Dev-shell GC roots are excluded and expire on their own 30-day timer (`apps/devshells.nix`). |
| `cheat` | In-terminal listing of every alias below, generated from the same source as `docs/CHEATSHEET.md` — the two cannot drift apart. |

There is no test suite or linter configured for this repo; correctness is "does it evaluate and does `nh os build` succeed."

Aliases (`rebuild`, `update`, `gc`, `zhealth`, `zsnaps`, `zbackup-status`, `devshell-clean`, etc.) are all defined in one place, `system/shell.nix`, as a single `aliasGroups` list that generates both the real zsh aliases and the `cheat`/`docs/CHEATSHEET.md` text — add a new alias there, not directly in `.zshrc` or only in the docs.

## Architecture

**Module graph**: `flake.nix` defines one `nixosConfigurations.BLACK-BOX` output built from `configuration.nix`, which imports every other module by path, grouped by directory:
- `apps/*.nix` — optional software/features (steam, virtualization, llm, devshells, tailscale, ...)
- `desktop/*.nix` — desktop environment; **exactly one** of `gnome.nix` / `hyprland.nix` is imported at a time in `configuration.nix`, the other is commented out
- `system/*.nix` — core OS behavior (zfs, firewall, power, sleep, shell, replication, zerotier)
- `home.nix` — home-manager config for user `komatrich`, imported via `home-manager.users.komatrich` in `configuration.nix` (it has no flake inputs in scope itself; `voice2text`/`local-ci` are threaded in via `home-manager.extraSpecialArgs` in `flake.nix`)

**Disk/impermanence model** ("erase your darlings" — full detail in `docs/DISK-LAYOUT.md`): root (`/`) is ZFS-rolled-back to an empty snapshot on every boot; only `/home`, `/persist`, `/nix` and `/games` survive. If a change needs a path outside `/home` to persist across reboots, add it to `apps/impermanence.nix` — find what needs persisting with the `fsdiff` alias. `/etc/nixos` itself lives on `/persist` (bind-mounted), which is why the git repo survives a reboot.

**Two ZFS pools**: `zroot` (NVMe, the live system + `/home`/`/persist`) and `zstorage` (SATA SSD, Steam library + encrypted raw-send replica of `zroot/safe/{home,persist}` via sanoid/syncoid every 15 min, config in `system/replication.nix`). See `docs/DISK-LAYOUT.md` for the full redundancy/encryption model, `docs/RECOVERY.md` for disk-failure procedures, `docs/INSTALL.md` for a from-scratch reinstall.

**Flake inputs with non-obvious pinning** (see comments in `flake.nix` for the why on each):
- `comfyui-nix` and `nixpkgs-llama` deliberately do **not** follow the main `nixpkgs` — they need newer CUDA-adjacent packages than `nixos-26.05` ships.
- `voice2text` and `local-ci` are `git+file:///home/...` inputs pointing at sibling repos under `~/Tools/`. Changes there need to be **committed** in that repo, then picked up here with `nix flake update voice2text` / `nix flake update local-ci` — editing those repos' working tree alone does nothing for this flake.
- `claude-code-nix` supplies an overlay (tracks upstream Claude Code releases faster than nixpkgs) applied in the `outputs` block of `flake.nix`.

**Dev shells for other projects** (not this repo): `apps/devshells.nix` implements persistent nix-direnv dev shells with two independent cleanup timers (30-day shell expiry, 60-day `node_modules` expiry) that exist specifically because `nh clean`'s normal 7-day window would otherwise kill dev shells too aggressively. Onboarding a project is `mkflake` (new) or `mkenvrc` (existing `flake.nix`), not manual `.envrc` editing.

## Known gotchas

- **`sudo env ...` can silently no-op.** `environment.localBinInPath = true` puts `~/.local/bin` ahead of system bins; if `~/.local/bin/env` exists (e.g. uv's PATH-setup snippet, not coreutils `env`) and has any executable bit, `sudo` resolves to it instead — it sets a var and exits 0 without running the real command. This is exactly why `rebuild`/`update` are wrapper scripts that verify the generation actually changed, rather than trusting the exit code. If a switch "succeeds" but nothing changed, check `ls -l ~/.local/bin/env` and verify with `readlink -f /run/current-system`.
- **A project's own dev shell can shadow system-managed tools.** If a system tool (e.g. `claude`) looks stale right after a successful rebuild, run `command -v <tool>` — a `/nix/store/...` path not reached via `/etc/profiles/per-user/<user>/bin` means an active `nix develop`/direnv shell in some other project owns it, not `/etc/nixos`. Don't put system-wide tools in a project's own `devShells.default`.
- **Verify NixOS option/package names with the `nix` MCP tool** (mcp-nixos, configured globally in `~/.claude.json`) before writing them into `.nix` files — don't guess option paths.

## Commit style

Commits in this repo use a terse `FEAT: <short description>` subject line (no body, no conventional-commits scopes) — match this style rather than introducing a different convention.
