# Install runbook

> **⚠️ THIS WIPES BOTH DISKS COMPLETELY.**
> Everything on the NVMe and the SATA SSD is destroyed in step 4.
> Do not start until the backup in step 0 is verified readable.

Migrating from the old BTRFS layout (or installing on fresh disks) to the
ZFS layout described in [DISK-LAYOUT.md](DISK-LAYOUT.md).

## 0. Back up (on the currently running system)

```sh
# External drive mounted at /mnt/backup (adjust):
rsync -aHAX --info=progress2 /home/    /mnt/backup/home/
rsync -aHAX --info=progress2 /persist/ /mnt/backup/persist/
```

Verify the backup is actually readable (spot-check a few files, check sizes
with `du -sh`). Games don't need backing up — Steam re-downloads them.

## 1. Boot the NixOS live ISO and get the config

Boot a NixOS 25.05 (or newer) live USB, connect to the network, then:

```sh
git clone https://github.com/KoMatrich/my-nix-config /tmp/nixos
cd /tmp/nixos
```

## 2. Stage the zstorage keyfile

Both pools use the **same passphrase**. Pick a strong one; you will type it
at every boot. disko needs it in a file to create the second pool
non-interactively:

```sh
echo -n 'YOUR-PASSPHRASE' > /tmp/zstorage.key
chmod 400 /tmp/zstorage.key
```

(`-n` matters — a trailing newline would become part of the key.)

## 3. Check disk device names

Confirm the devices match `disko-config.nix` (`/dev/nvme0n1` and `/dev/sda`):

```sh
lsblk -o NAME,SIZE,MODEL
```

If the SATA disk shows up under another name, edit `disko-config.nix` first.

## 4. Partition, format, mount (DESTRUCTIVE)

```sh
sudo nix --experimental-features "nix-command flakes" \
  run github:nix-community/disko/latest -- \
  --mode destroy,format,mount /tmp/nixos/disko-config.nix
```

You will be prompted for the `zroot` passphrase — use the **same** one as in
step 2.

## 5. Verify the blank snapshot exists

This is what gets rolled back to on every boot. **Do not skip this check:**

```sh
zfs list -t snapshot
# must contain: zroot/local/root@blank
```

If it's missing, create it now, while root is still empty:

```sh
sudo zfs snapshot zroot/local/root@blank
```

## 6. Move the zstorage keyfile into place

```sh
sudo mkdir -p /mnt/persist/zfs
sudo install -m 400 /tmp/zstorage.key /mnt/persist/zfs/zstorage.key
sudo zfs set keylocation=file:///persist/zfs/zstorage.key zstorage
```

## 7. Create password hash files

Password hashes live on `/persist`, not in git:

```sh
sudo mkdir -p /mnt/persist/passwords
mkpasswd -m sha-512 | sudo tee /mnt/persist/passwords/komatrich > /dev/null
mkpasswd -m sha-512 | sudo tee /mnt/persist/passwords/root > /dev/null
sudo chmod 400 /mnt/persist/passwords/*
```

> The hash that used to be committed in this repo's git history is burned —
> pick **new** passwords, don't reuse the old one.

## 8. Generate hardware config and install

The repo must live on the **persisted** dataset: `/persist/etc/nixos`. The
running system sees it at `/etc/nixos` via the impermanence bind mount. Do
NOT copy it to `/mnt/etc/nixos` — that path is on the root dataset, which the
blank-snapshot rollback erases on first boot, leaving `/etc/nixos` empty.

```sh
sudo nixos-generate-config --no-filesystems --root /mnt
# Compare/replace hardware-configuration.nix in the repo if the generated
# one differs (new kernel modules etc.):
sudo cp /mnt/etc/nixos/hardware-configuration.nix /tmp/nixos/hardware-configuration.nix
sudo rm -rf /mnt/etc/nixos
sudo mkdir -p /mnt/persist/etc
sudo cp -r /tmp/nixos /mnt/persist/etc/nixos
sudo nixos-install --flake /mnt/persist/etc/nixos#default --no-root-passwd
```

## 9. Export the pools, then reboot

The pools are currently imported by the **live ISO's random hostid**, not the
installed system's (`networking.hostId = "deadbeef"`). Without a clean export,
the first boot refuses to import `zroot` ("pool was previously in use from
another system" — `forceImportRoot` is off) and drops into a locked emergency
console. **Do not skip this:**

```sh
sudo umount -R /mnt
sudo zpool export -a
reboot
```

At boot you'll be prompted once for the ZFS passphrase. If boot fails anyway,
see ["First boot fails" in RECOVERY.md](RECOVERY.md#first-boot-fails--drops-to-emergency-mode).

## 10. Post-install checks

```sh
zpool status -x                       # "all pools are healthy"
mount | grep -E 'zroot|zstorage'      # /, /nix, /home, /persist, /games
swapon --show                         # zram0
zfs get keylocation zstorage          # file:///persist/zfs/zstorage.key
```

Restore your data:

```sh
rsync -aHAX --info=progress2 /mnt/backup/home/ /home/
```

After ~20 minutes, confirm replication is flowing:

```sh
zbackup-status
# zstorage/backup/home and zstorage/backup/persist should list fresh snapshots
```

Then:

1. Run `fsdiff` — anything listed will be erased on reboot; persist what
   matters via `apps/impermanence.nix`.
2. Reboot once more and verify the system comes up clean and `/` was reset.
3. Steam → Settings → Storage → Add Drive → `/games`, and set it as default.

Daily usage from here: see [CHEATSHEET.md](CHEATSHEET.md).
