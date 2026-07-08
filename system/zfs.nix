# ZFS core: boot-time root rollback ("erase your darlings"), pool imports,
# encryption unlock, scrub/trim maintenance, ARC sizing.
# See docs/DISK-LAYOUT.md for what is wiped vs persisted.
{ config, lib, pkgs, ... }:
{
  boot.supportedFilesystems = [ "zfs" ];

  # hostId is required by ZFS and baked into the pools; do not change it
  # after install or the pools will refuse to import without -f.
  # (Set in configuration.nix: networking.hostId)

  # zroot prompts for its passphrase in initrd. zstorage is listed too so the
  # stage-2 import service loads its key from the keyfile on /persist
  # (keylocation=file:///persist/zfs/zstorage.key, set in INSTALL.md step 6);
  # only the exact names listed here get load-key, so the raw-received
  # zstorage/backup/* datasets stay locked as intended.
  boot.zfs.requestEncryptionCredentials = [ "zroot" "zstorage" ];
  boot.zfs.forceImportRoot = false;

  # zstorage is imported in stage 2. Its key lives on /persist (neededForBoot,
  # so already mounted), meaning one passphrase at boot unlocks everything.
  boot.zfs.extraPools = [ "zstorage" ];

  # Modern systemd-based initrd. The rollback service resets / to the blank
  # snapshot on every boot, after the pool is imported and unlocked but before
  # the root filesystem is mounted.
  boot.initrd.systemd.enable = true;
  boot.initrd.systemd.services.rollback = {
    description = "Rollback root filesystem to blank snapshot";
    wantedBy = [ "initrd.target" ];
    after = [ "zfs-import-zroot.service" ];
    before = [ "sysroot.mount" ];
    unitConfig.DefaultDependencies = "no";
    serviceConfig.Type = "oneshot";
    script = ''
      ${config.boot.zfs.package}/sbin/zfs rollback -r zroot/local/root@blank
    '';
  };

  # A dead/absent SSD must not block boot; only /games and backups live there.
  fileSystems."/games".options = [ "nofail" ];

  # Monthly integrity check of all data on both pools.
  services.zfs.autoScrub = {
    enable = true;
    interval = "monthly";
  };
  services.zfs.trim.enable = true;

  # Cap the ZFS ARC at 8 GiB so games and dev tools keep most of the 32 GiB.
  # ARC shrinks under memory pressure, but slowly - a hard cap behaves better
  # on a desktop. Tune here if needed.
  boot.kernelParams = [ "zfs.zfs_arc_max=8589934592" ];
}
