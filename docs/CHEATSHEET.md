# Cheatsheet

Daily commands for this setup. Aliases are defined in `system/shell.nix`;
run `cheat` in a terminal for a quick summary of them.

The default shell is zsh with oh-my-zsh (plugins: `git`, `sudo`, `z`,
`extract`) plus autosuggestions and syntax highlighting.

## System management

| Alias | Runs | What it does |
|---|---|---|
| `rebuild` | `nh os switch` | Apply config changes from `/etc/nixos` |
| `update` | `nh os switch --update` | Update flake inputs + rebuild |
| `gc` | `nh clean all ...` | Delete old generations (keeps 7 days / last 5; dev shells expire separately, see below) |

`nh` also shows a package diff on every rebuild. Old generations are cleaned
automatically on a schedule too (`programs.nh.clean`).

Editing the config: it lives in `/etc/nixos` (persisted, it's this git repo).
Commit and push your changes — the repo is the backup of the config.

## Dev shells (direnv)

Dev shells are cached and GC-rooted per project via nix-direnv, so they
survive reboots and `gc` and keep working offline. A shell only expires
after **30 days without use** (every `cd` into the project resets the
clock); `node_modules` of npm projects untouched for **60 days** are also
auto-deleted (both run as weekly user timers, see `apps/devshells.nix`).

| Command | What it does |
|---|---|
| `mkflake` | Guided wizard: scaffold `flake.nix` (pick language + packages) + `.envrc` for a new project |
| `mkenvrc` | Add `.envrc` to an existing project that already has a `flake.nix` / `shell.nix` + `direnv allow` |
| `devshells` | List cached dev shells with last-used age and closure size |
| `devshell-clean` | Run the 30d/60d cleanup now and show what was deleted |

**Starting from scratch?** Run `mkflake` — it creates both `flake.nix` and `.envrc` in one go.
**Already have a `flake.nix`?** Run `mkenvrc` to just add `.envrc` + `direnv allow`.

Note: only direnv-entered shells are protected — a plain `nix develop` in a
project without `.envrc` still creates no GC root.

## ZFS health & snapshots

| Alias | What it shows |
|---|---|
| `zhealth` | Pool health (silent = all good) |
| `zsnaps` | All snapshots, oldest first |
| `zbackup-status` | Replication timers + latest backup snapshots on the SSD |
| `fsdiff` | Every file on `/` that will be **erased on next reboot** |

## Impermanence workflow

Root (`/`) resets to empty on every boot. When an app misbehaves after
reboots (lost settings, re-asks for setup), it's storing state outside
`/home` — find it and persist it:

1. `fsdiff` → look for its paths (e.g. `/var/lib/someservice`)
2. Add the path to `directories` (or `files`) in `apps/impermanence.nix`
3. `rebuild`

## Manual snapshot / restore

```sh
sudo zfs snapshot zroot/safe/home@before-big-experiment   # named snapshot
ls /home/.zfs/snapshot/                                   # browse snapshots
cp -a /home/.zfs/snapshot/<snap>/komatrich/file ~/        # restore one file
sudo zfs rollback zroot/safe/home@<snap>                  # full rollback (destroys newer data!)
sudo zfs destroy zroot/safe/home@before-big-experiment    # drop a snapshot
```

More restore scenarios (disk death etc.): [RECOVERY.md](RECOVERY.md)

## Replication (redundancy to the 2nd disk)

Runs automatically every 15 min. Manual operations:

```sh
zbackup-status                                        # is it flowing?
sudo systemctl start syncoid-zroot-safe-home.service  # force a sync now
sudo systemctl start syncoid-zroot-safe-persist.service
journalctl -u syncoid-zroot-safe-home -e              # debug a failed sync
```

## Scrub (data integrity check)

Runs monthly on both pools automatically.

```sh
zpool status              # shows last scrub result / progress
sudo zpool scrub zroot    # start one manually
```

## Hyprland keys

Defined in `desktop/hyprland.nix`. `Super` = Windows key.

| Keys | Action |
|---|---|
| `Super+Return` | Terminal (kitty) |
| `Super+D` | App launcher (wofi) |
| `Super+V` | Clipboard history |
| `Super+Q` | Close window |
| `Super+F` | Fullscreen |
| `Super+Shift+Space` | Toggle floating |
| `Super+1..9` | Switch workspace (`+Shift` = move window there) |
| `Super+arrows` | Move focus (`+Shift` = move window, `+Ctrl` = resize) |
| `Super+mouse drag` | Move window (right button = resize) |
| `Print` | Screenshot region → clipboard (`Shift+Print` = full screen → ~/Pictures) |
| `Super+L` | Lock screen |
| `Super+M` | Exit Hyprland session |

## Steam / games

Library lives at `/games` (512 GB SSD). Add it once via
Steam → Settings → Storage → Add Drive. Games are not backed up on purpose.

## GPU

- Default boot: NVIDIA PRIME offload (battery friendly).
  Run a game on the dGPU: `nvidia-offload %command%` in Steam launch options.
- Docked boot entry (`docked` specialisation in the boot menu): PRIME sync,
  dGPU always on.
