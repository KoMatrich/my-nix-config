# Recovery procedures

What to do when things break, from least to most severe.
Layout reference: [DISK-LAYOUT.md](DISK-LAYOUT.md).

## Restore a deleted/overwritten file

Snapshots of `/home` and `/persist` are taken every 15 minutes.
Every snapshot is browsable as a plain read-only directory:

```sh
ls /home/.zfs/snapshot/                          # list snapshots by name
ls /home/.zfs/snapshot/autosnap_2026-07-02_14:15:00_frequently/komatrich/
cp -a /home/.zfs/snapshot/<snap>/komatrich/lost-file ~/lost-file
```

(The `.zfs` directory is hidden — it won't show in `ls /home`, but you can
`cd` into it.)

To roll a whole dataset back (destroys everything newer than the snapshot!):

```sh
zfs list -t snapshot zroot/safe/home
sudo zfs rollback zroot/safe/home@<snapshot>
```

## "I lost files on / after a reboot"

Working as designed — `/` is erased every boot. Recreate the files and, if
they should survive, add their path to `apps/impermanence.nix` and rebuild.
Use `fsdiff` before rebooting to catch this in advance.

## SATA SSD (`zstorage`) died

Nothing important is lost. The system boots without it (`/games` is `nofail`);
sanoid/syncoid units will log failures until fixed.

1. Replace the disk.
2. Recreate the pool and datasets manually (disko full-runs would wipe the
   NVMe too — do **not** re-run disko in destroy mode):

   ```sh
   # adjust device name if needed
   sudo zpool create -o ashift=12 -o autotrim=on \
     -O compression=zstd -O atime=off -O xattr=sa -O acltype=posixacl \
     -O dnodesize=auto -O normalization=formD -O mountpoint=none -O canmount=off \
     -O encryption=aes-256-gcm -O keyformat=passphrase \
     -O keylocation=file:///persist/zfs/zstorage.key \
     zstorage /dev/sda1   # create a single GPT partition first (e.g. with parted)
   sudo zfs create -o mountpoint=legacy -o recordsize=1M zstorage/games
   sudo zfs create -o canmount=off zstorage/backup
   sudo zfs create -o canmount=off -o refreservation=20G zstorage/reserved
   ```

3. `sudo nixos-rebuild switch` (remounts `/games`), re-add the Steam library.
4. Replication resumes on the next syncoid timer tick and re-seeds
   `zstorage/backup/*` from scratch. Verify with `zbackup-status`.

## NVMe (`zroot`) died — restore from the SSD replica

Your `/home` and `/persist` are safe on `zstorage/backup/*`, at most ~15
minutes stale. The ESP (`/boot`) also lived on the NVMe, but it's fully
reproducible.

1. Replace the NVMe, boot the NixOS live ISO.
2. Follow [INSTALL.md](INSTALL.md) steps 1–5, **but**: disko in
   `destroy,format,mount` mode would also wipe `zstorage` (where your backups
   are!). Instead, temporarily delete the `disk.data` and `zpool.zstorage`
   sections from your local copy of `disko-config.nix` before running disko,
   so only the NVMe is touched. Use the **same passphrase as before** so the
   raw backup streams remain loadable.
3. Import the backup pool and unlock it by prompt (the keyfile died with the
   old NVMe; the passphrase is the key):

   ```sh
   sudo zpool import zstorage
   sudo zfs load-key -L prompt zstorage
   ```

4. Restore the data as raw streams back into the new pool:

   ```sh
   LATEST_HOME=$(zfs list -t snapshot -o name -s creation zstorage/backup/home | tail -1)
   LATEST_PERSIST=$(zfs list -t snapshot -o name -s creation zstorage/backup/persist | tail -1)
   sudo zfs send -w "$LATEST_HOME"    | sudo zfs recv -F zroot/safe/home
   sudo zfs send -w "$LATEST_PERSIST" | sudo zfs recv -F zroot/safe/persist
   # The received datasets carry the old encryption root; unlock and adopt them:
   sudo zfs load-key -L prompt zroot/safe/home
   sudo zfs load-key -L prompt zroot/safe/persist
   sudo zfs change-key -i zroot/safe/home
   sudo zfs change-key -i zroot/safe/persist
   sudo zfs set mountpoint=legacy zroot/safe/home zroot/safe/persist
   ```

5. Continue INSTALL.md from step 6 (keyfile, passwords already restored
   inside /persist — check `/mnt/persist/passwords/` after mounting, then
   steps 8–9).

## Both disks died

The replicas were on the same machine as the originals — that's what the
external backup from INSTALL.md step 0 (or your own off-machine backups) is
for. Consider periodic `syncoid` runs to an external USB disk for the
irreplaceable stuff.

## Pool won't import after a hostId change

`networking.hostId` is baked into the pools. If it ever changes, import once
with force from a live system: `zpool import -f zroot`. Don't change it.

## Pool is 100% full and everything is failing

```sh
sudo zfs set refreservation=none zroot/reserved    # instantly frees 10 GB
gc                                                 # clean old generations
zsnaps                                             # find fat snapshots to destroy
sudo zfs set refreservation=10G zroot/reserved     # restore the safety net
```
