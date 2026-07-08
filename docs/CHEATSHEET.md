# Cheatsheet

Daily commands for this setup. Aliases are defined in `system/shell.nix`.

## System management

| Alias | Runs | What it does |
|---|---|---|
| `rebuild` | `nh os switch` | Apply config changes from `/etc/nixos` |
| `update` | `nh os switch --update` | Update flake inputs + rebuild |
| `gc` | `nh clean all ...` | Delete old generations (keeps 7 days / last 5) |

`nh` also shows a package diff on every rebuild. Old generations are cleaned
automatically on a schedule too (`programs.nh.clean`).

Editing the config: it lives in `/etc/nixos` (persisted, it's this git repo).
Commit and push your changes — the repo is the backup of the config. It is
user-owned so no sudo is needed to edit; if editing prompts for permissions,
run the one-time `chown` from the end of [INSTALL.md](INSTALL.md).

Trying a package without a rebuild (no sudo needed):

```sh
nix shell nixpkgs#htop            # temporary, gone when the shell exits
nix run nixpkgs#cowsay -- moo     # run once without installing
nix profile install nixpkgs#htop  # per-user, survives reboots (~/.nix-profile is on /home)
```

Once a package earns its keep, move it into the config
(`environment.systemPackages` or `home.packages`) and `rebuild`, and remove
the ad-hoc install with `nix profile remove`.

## Passwords

`users.mutableUsers = false` — **`passwd` changes are silently reverted** on
the next boot/rebuild. The only source of truth is the hash files on the
persisted dataset:

- `/persist/passwords/komatrich` — user login **and sudo** (sudo asks for the
  user's password)
- `/persist/passwords/root` — root / `su`

To change a password (as root — use `su` if sudo is broken):

```sh
mkpasswd -m sha-512 > /persist/passwords/komatrich   # type the new password
chmod 400 /persist/passwords/komatrich
nixos-rebuild switch --flake /etc/nixos#default      # or just reboot
```

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

## Steam / games

Library lives at `/games` (512 GB SSD). Add it once via
Steam → Settings → Storage → Add Drive. Games are not backed up on purpose.

## GPU

- Default boot: NVIDIA PRIME offload (battery friendly).
  Run a game on the dGPU: `nvidia-offload %command%` in Steam launch options.
- Docked boot entry (`docked` specialisation in the boot menu): PRIME sync,
  dGPU always on.
