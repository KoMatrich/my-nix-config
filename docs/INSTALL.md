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

> **⚠️ `mkpasswd` prompts only ONCE, with no confirmation** — a typo here
> means being locked out of the user account (and sudo) after first boot.
> Verify each hash by re-typing the password with the same salt and
> comparing the output to the stored file (they must match exactly):
>
> ```sh
> mkpasswd -m sha-512 -S "$(sudo cut -d'$' -f3 /mnt/persist/passwords/komatrich)"
> sudo cat /mnt/persist/passwords/komatrich
> ```
>
> If you get locked out anyway, it's fixable post-install with the root
> password via `su` (see "Passwords" in CHEATSHEET.md). Note that
> `users.mutableUsers = false` means `passwd` changes never persist — these
> files are the only source of truth.

> The hash that used to be committed in this repo's git history is burned —
> pick **new** passwords, don't reuse the old one.

## 8. Generate hardware config and install

```sh
sudo nixos-generate-config --no-filesystems --root /mnt
# Compare/replace hardware-configuration.nix in the repo if the generated
# one differs (new kernel modules etc.):
sudo cp /mnt/etc/nixos/hardware-configuration.nix /tmp/nixos/hardware-configuration.nix
sudo rm -rf /mnt/etc/nixos
sudo cp -r /tmp/nixos /mnt/etc/nixos
sudo nixos-install --flake /mnt/etc/nixos#default --no-root-passwd
reboot
```

At boot you'll be prompted once for the ZFS passphrase.

## 9. Post-install checks

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

Make the config editable without sudo (rebuilding still needs root; the
ownership lives on the persist dataset so this survives reboots):

```sh
sudo chown -R komatrich:users /persist/etc/nixos
```

Then:

1. Run `fsdiff` — anything listed will be erased on reboot; persist what
   matters via `apps/impermanence.nix`.
2. Reboot once more and verify the system comes up clean and `/` was reset.
3. Steam → Settings → Storage → Add Drive → `/games`, and set it as default.

Daily usage from here: see [CHEATSHEET.md](CHEATSHEET.md).
