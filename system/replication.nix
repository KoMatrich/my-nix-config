# Redundancy: sanoid snapshots zroot/safe/* every 15 minutes, syncoid
# replicates them to the second disk (zstorage/backup/*) shortly after.
# If the NVMe dies, at most ~15 minutes of work is lost.
# Games (/games) and /nix are intentionally NOT replicated - re-downloadable
# and rebuildable respectively. See docs/RECOVERY.md for restore procedures.
{ config, lib, pkgs, ... }:
{
  services.sanoid = {
    enable = true;
    # Default sanoid cadence is hourly; run every 15 min for the frequent snaps.
    interval = "*:0/15";
    templates = {
      # Source datasets on the fast NVMe pool.
      source = {
        frequently = 16;      # 16 x 15min = 4 hours of fine-grained history
        frequent_period = 15;
        hourly = 48;
        daily = 14;
        monthly = 0;
        autosnap = true;
        autoprune = true;
      };
      # Replicated copies on the SSD: no snapshots taken here (they arrive via
      # syncoid), only pruning, with longer retention.
      backup = {
        frequently = 0;
        hourly = 72;
        daily = 30;
        monthly = 3;
        autosnap = false;
        autoprune = true;
      };
    };
    datasets = {
      "zroot/safe/home".useTemplate = [ "source" ];
      "zroot/safe/persist".useTemplate = [ "source" ];
      # These datasets are created by syncoid's first run; sanoid logs a
      # harmless warning until then.
      "zstorage/backup/home".useTemplate = [ "backup" ];
      "zstorage/backup/persist".useTemplate = [ "backup" ];
    };
  };

  services.syncoid = {
    enable = true;
    # Offset 5 min after each sanoid tick so fresh snapshots get replicated.
    interval = "*:5/15";
    # Replicate only sanoid's snapshots instead of creating extra sync snaps.
    commonArgs = [ "--no-sync-snap" ];
    commands = {
      "zroot/safe/home" = {
        target = "zstorage/backup/home";
        sendOptions = "w"; # raw send: backups stay encrypted, keys never loaded
        recvOptions = "u"; # never mount received datasets
      };
      "zroot/safe/persist" = {
        target = "zstorage/backup/persist";
        sendOptions = "w";
        recvOptions = "u";
      };
    };
    # The module runs syncoid as an unprivileged user with delegated ZFS
    # permissions. If raw receives ever fail with a permission error, the
    # simple fallback is:
    #   services.syncoid.user = "root";
  };
}
