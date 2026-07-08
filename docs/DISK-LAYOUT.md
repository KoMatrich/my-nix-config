# Disk layout

Two disks, two ZFS pools, "erase your darlings" style
([grahamc's blog post](https://grahamc.com/blog/erase-your-darlings/)):
the root filesystem is rolled back to an empty snapshot on **every boot**.
Only explicitly persisted state survives.

## Physical layout

| Device | Size | Speed | Contents |
|---|---|---|---|
| `/dev/nvme0n1` | 256 GB | fast | 1 GB ESP (`/boot`) + pool **`zroot`** |
| `/dev/sda` | 512 GB | slow (SATA) | pool **`zstorage`** |

## Pool `zroot` (NVMe — the system runs from here)

| Dataset | Mounted at | Fate |
|---|---|---|
| `zroot/local/root` | `/` | **Erased on every boot** (rollback to `@blank` in initrd) |
| `zroot/local/nix` | `/nix` | Persistent; not backed up (rebuildable from this flake) |
| `zroot/safe/home` | `/home` | Persistent; snapshotted every 15 min; replicated to SSD |
| `zroot/safe/persist` | `/persist` | Persistent; snapshotted every 15 min; replicated to SSD |
| `zroot/reserved` | — | 10 GB emergency reservation (see below) |

## Pool `zstorage` (SATA SSD — games + backups)

| Dataset | Mounted at | Fate |
|---|---|---|
| `zstorage/games` | `/games` | Steam library; **not** replicated (games are re-downloadable) |
| `zstorage/comfyui-models` | `/var/lib/comfyui/models` | ComfyUI model checkpoints; **not** replicated (re-downloadable) |
| `zstorage/backup/home` | never mounted | Encrypted replica of `zroot/safe/home` |
| `zstorage/backup/persist` | never mounted | Encrypted replica of `zroot/safe/persist` |
| `zstorage/reserved` | — | 20 GB emergency reservation |

`/games` and `/var/lib/comfyui/models` are mounted `nofail`: if the SSD dies,
the system still boots (the comfyui service then refuses to start instead of
re-downloading models onto the NVMe).

## What survives what

| Event | Result |
|---|---|
| Reboot | Everything on `/` outside persisted paths is gone (that's the point). `/home`, `/persist`, `/nix`, `/games` untouched. |
| Accidental `rm` in /home | Restore from 15-min snapshots (see RECOVERY.md), up to 14 days back. |
| NVMe dies | Reinstall on new disk; `/home` + `/persist` restored from `zstorage/backup/*` — at most ~15 min of work lost. Games re-download. |
| SATA SSD dies | Nothing important lost. System runs fine; replication timers fail loudly until the disk is replaced. Games and ComfyUI models re-download. |
| Both die at once | Data gone. Keep occasional external backups for the truly irreplaceable. |

## Redundancy model

- **sanoid** snapshots `zroot/safe/{home,persist}` every 15 minutes.
  Retention on the source: 16 × 15 min, 48 hourly, 14 daily.
- **syncoid** replicates those snapshots to `zstorage/backup/*` every
  15 minutes (offset by 5 min). Retention on the backup: 72 hourly,
  30 daily, 3 monthly.
- Replication uses **raw sends**: the copies on the SSD stay encrypted and
  the backup pool never has keys loaded.
- Config: `system/replication.nix`. Status: `zbackup-status` alias.

## Encryption / key model

Both pools use ZFS native encryption (aes-256-gcm) with the **same passphrase**:

```
boot ──> type passphrase once ──> unlocks zroot (keylocation=prompt)
                                        │
                                        └─> /persist mounts ──> zstorage key
                                            read from /persist/zfs/zstorage.key
                                            (file content = the passphrase)
```

Because the keyfile's content *is* the passphrase, `zstorage` remains
recoverable with `zfs load-key -L prompt zstorage` even if the NVMe (and
thus the keyfile) is destroyed.

## Persisted state

- `/persist` bind-mount list: `apps/impermanence.nix` (system state like
  logs, NetworkManager connections, the flake itself at `/etc/nixos`).
- User password hashes: `/persist/passwords/{root,komatrich}` (not in git).
- zstorage keyfile: `/persist/zfs/zstorage.key` (not in git).
- Run `fsdiff` to list everything on `/` that would be erased by a reboot —
  if something in the output matters, add it to `apps/impermanence.nix`.

## Emergency: pool full

ZFS degrades badly at ~100% full. Both pools carry an unmountable `reserved`
dataset you can shrink to instantly free space:

```sh
sudo zfs set refreservation=none zroot/reserved   # frees 10 GB
```

Then clean up (old snapshots, `gc` alias) and restore the reservation.
