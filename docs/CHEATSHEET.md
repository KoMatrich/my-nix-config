# Cheatsheet

Daily commands for this setup. Aliases are defined in `system/shell.nix`;
run `cheat` in a terminal for a quick summary of them.

The default shell is zsh with oh-my-zsh (plugins: `git`, `sudo`,
`extract`) plus autosuggestions, syntax highlighting and zoxide (`z`, `zi`).

## System management

| Alias | Runs | What it does |
|---|---|---|
| `rebuild` | `nh os switch` | Apply config changes from `/etc/nixos` |
| `update` | `nh os switch --update` | Update flake inputs + rebuild |
| `gc` | `nh clean all ...` | Delete old generations (keeps 7 days / last 5; dev shells expire separately, see below) |
| `docker-clean` | `docker system prune -a` | Remove unused Docker images, stopped containers, networks and build cache (keeps volumes; asks first) |

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
| `zbackup-usb` | Run the USB HDD backup now and follow its log (normally starts on plug-in) |
| `zbackup-usb-status` | Result and log of the last USB HDD backup |
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

**USB HDD (offline copy):** just plug the drive in. The backup starts by
itself; wait for the "USB backup done — safe to unplug" notification (the
pool is exported and the disk powered off by then). `zbackup-usb-status`
shows the last result. Setup and restore: [RECOVERY.md](RECOVERY.md).

## Scrub (data integrity check)

Runs monthly on both pools automatically.

```sh
zpool status              # shows last scrub result / progress
sudo zpool scrub zroot    # start one manually
```

## iPhone

USB access and backups via libimobiledevice (`apps/iphone.nix`). Backups go
to `~/Backups/iPhone`, so they're replicated with the rest of `/home`.

| Command | What it does |
|---|---|
| `iphone-backup` | Back up over USB if plugged in, else over Wi-Fi (incremental; `iphone-backup --full` forces a full one) |
| `iphone-wifi-sync on\|off\|status` | Allow/deny Wi-Fi connections — needs the phone on USB |
| `ifuse ~/iPhone` / `fusermount -u ~/iPhone` | Mount / unmount the phone's media (photos etc.) |

**One-time setup** (after `rebuild`):

1. Plug the phone in via USB, unlock it, tap **Trust**, then `idevicepair pair`.
   Pairing is persisted (`/var/lib/lockdown`), so this survives reboots.
2. Optional but recommended: `idevicebackup2 -i encryption on` (asks for a
   password). Only encrypted backups include saved passwords, Wi-Fi and
   Health data. **Lose the password and the backup is useless.**
3. `iphone-backup` — the first run is a full backup and takes a while.
4. For Wi-Fi: `iphone-wifi-sync on`, unplug, then `idevice_id -n` should list
   the phone (same network, phone unlocked/awake). After that `iphone-backup`
   works wirelessly.

**Restore:** `idevicebackup2 -i restore --system --settings ~/Backups/iPhone`
(phone on USB; *Find My* must be off on the phone; `-i` prompts for the
backup password if encrypted). Onto a new/replacement phone, add
`-s <old-UDID>` — backups are stored per UDID (the folder name in
`~/Backups/iPhone`).

**Wi-Fi not showing up?** Wi-Fi uses `usbmuxd2` instead of stock usbmuxd and
depends on the iOS version, so it's best-effort; USB always works. Check
`journalctl -u usbmuxd`, that `avahi-browse -rt _apple-mobdev2._tcp` sees the
phone, and that `sudo grep WiFiMACAddress /var/lib/lockdown/*.plist` finds
the pairing's Wi-Fi MAC (if not, re-run `idevicepair pair` over USB). If the
phone is visible to avahi but not to `idevice_id -n`, uncomment the
`--allow-heartless-wifi` override in `apps/iphone.nix` and `rebuild`. If
usbmuxd2 itself misbehaves, set `wifi = false` in `apps/iphone.nix` to go
back to USB-only stock usbmuxd.

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
