# Offline backup to an external USB HDD (pool `zusb`): plug the drive in and
# zroot/safe/{home,persist} are replicated to it automatically; when the
# desktop notification says so, the pool is exported and the disk powered off,
# so it can simply be unplugged. Covers the "both internal disks die" case in
# docs/DISK-LAYOUT.md. Pool creation: docs/INSTALL.md; restore: docs/RECOVERY.md.
#
# Deliberately NOT part of services.sanoid / services.syncoid: those run on
# 15-minute timers and would fail every tick while the drive is unplugged.
{ config, lib, pkgs, ... }:
let
  pool = "zusb";
  user = config.local.user;
  datasets = [ "home" "persist" ];

  # Retention on the USB copy. Keeping >= 1 of every type the source produces
  # guarantees the newest replicated snapshot survives pruning, which is the
  # incremental base for the next run (sanoid never prunes below the count).
  sanoidConf = pkgs.writeTextDir "sanoid.conf" (lib.concatMapStrings (d: ''
    [${pool}/backup/${d}]
      frequently = 1
      frequent_period = 15
      hourly = 1
      daily = 30
      monthly = 0
      autosnap = no
      autoprune = yes

  '') datasets);

  # Nag when the offline copy gets old. The age comes from the bookmarks that
  # `syncoid --create-bookmark` leaves on the *source* after every successful
  # USB run (named after, and dated like, the newest snapshot that reached the
  # drive), so it needs no state of its own and works without the drive.
  reminderDays = 14;
  zbackupUsbAge = pkgs.writeShellApplication {
    name = "zbackup-usb-age";
    runtimeInputs = [ config.boot.zfs.package pkgs.coreutils pkgs.libnotify ];
    text = ''
      now=$(date +%s)
      oldest=""
      for d in ${lib.concatStringsSep " " datasets}; do
        # -p: creation as epoch seconds. No bookmark = never backed up.
        if ! out=$(zfs list -H -p -t bookmark -o creation -s creation "zroot/safe/$d"); then
          echo "zbackup-usb-age: cannot list bookmarks of zroot/safe/$d" >&2
          exit 1
        fi
        last=$(printf '%s\n' "$out" | tail -n 1)
        if [ -z "$last" ]; then oldest=0; break; fi
        if [ -z "$oldest" ] || [ "$last" -lt "$oldest" ]; then oldest=$last; fi
      done

      if [ "$oldest" = 0 ]; then
        days=never
        msg="The USB backup drive has never been synced."
      else
        days=$(( (now - oldest) / 86400 ))
        msg="Last USB backup: $(date -d "@$oldest" '+%Y-%m-%d %H:%M') ($days days ago)."
      fi
      echo "$msg"

      if [ "''${1:-}" = "--notify" ] && { [ "$days" = never ] || [ "$days" -ge ${toString reminderDays} ]; }; then
        notify-send --app-name="USB backup" --icon=drive-harddisk \
          "Time for a USB backup" "$msg Plug in the backup drive; it syncs on its own."
      fi
    '';
  };

  zbackupUsb = pkgs.writeShellApplication {
    name = "zbackup-usb-run";
    runtimeInputs = [ config.boot.zfs.package pkgs.sanoid pkgs.udisks pkgs.util-linux pkgs.libnotify pkgs.coreutils pkgs.gawk pkgs.procps ];
    text = ''
      notify() {
        # Best effort: only works while the user has a graphical session.
        uid=$(id -u ${user})
        bus=/run/user/$uid/bus
        [ -S "$bus" ] || return 0
        runuser -u ${user} -- env DBUS_SESSION_BUS_ADDRESS="unix:path=$bus" \
          notify-send --app-name="USB backup" "$@" || true
      }
      # Success or failure, always leave the drive exported and powered off
      # so it can be unplugged; only the notification differs.
      vdev=""
      finish() {
        status=$?
        if zpool list ${pool} >/dev/null 2>&1; then
          zpool export ${pool} || status=1
        fi
        if [ -n "$vdev" ] && ! zpool list ${pool} >/dev/null 2>&1; then
          # Spin down and detach so the drive can be unplugged right away.
          udisksctl power-off -b "$vdev" || true
        fi
        if [ "$status" -eq 0 ]; then
          notify "USB backup done" "Safe to unplug the drive."
        else
          notify --urgency=critical "USB backup FAILED" "See: journalctl -u zbackup-usb"
        fi
        exit "$status"
      }
      trap finish EXIT

      if ! zpool list ${pool} >/dev/null 2>&1; then
        # -N: never mount anything; the received datasets are encrypted anyway.
        zpool import -d /dev/disk/by-id -N ${pool}
      fi
      # Remember the disk before exporting so it can be powered off afterwards.
      vdev=$(zpool list -vHP ${pool} | awk '$1 ~ /^\/dev\// { print $1; exit }')

      # Parent of the received datasets; absent on a freshly created pool.
      zfs list ${pool}/backup >/dev/null 2>&1 || zfs create -o canmount=off ${pool}/backup

      notify "USB backup started" "Do not unplug the drive."

      ${lib.concatMapStrings (d: ''
        # Raw send (w): the copy stays encrypted with zroot's key, never loaded
        # here. --create-bookmark leaves a bookmark on the source so the next
        # run stays incremental even after sanoid has pruned the snapshot.
        syncoid --no-sync-snap --create-bookmark \
          --sendoptions=w --recvoptions=u \
          zroot/safe/${d} ${pool}/backup/${d}
      '') datasets}

      # Own config, cache and lock dirs so this never collides with the
      # system sanoid timer.
      sanoid --configdir=${sanoidConf} \
        --cache-dir="$RUNTIME_DIRECTORY" --run-dir="$RUNTIME_DIRECTORY" \
        --force-update --prune-snapshots --verbose
    '';
  };
in
{
  systemd.services.zbackup-usb = {
    description = "Replicate zroot/safe/* to the USB backup pool ${pool}";
    after = [ "zfs-import.target" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = lib.getExe zbackupUsb;
      RuntimeDirectory = "zbackup-usb";
      # The first full send is ~190 GB over USB 2.5" HDD (1-2 hours).
      TimeoutStartSec = "infinity";
      Nice = 10;
      IOSchedulingClass = "idle";
    };
  };

  environment.systemPackages = [ zbackupUsbAge ];

  # Daily check (and once shortly after login): notify if the USB copy is
  # older than reminderDays (above). `zbackup-usb-age` prints the age by hand.
  systemd.user.services.zbackup-usb-reminder = {
    description = "Remind to plug in the USB backup drive";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${lib.getExe zbackupUsbAge} --notify";
    };
  };
  systemd.user.timers.zbackup-usb-reminder = {
    description = "Daily USB backup age check";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnStartupSec = "15min";
      OnCalendar = "daily";
      Persistent = true;
    };
  };

  # Start the backup when a disk carrying the pool is plugged in. Matching on
  # the pool label (not the drive serial) means a replacement drive only needs
  # `zpool create zusb ...` again.
  services.udev.extraRules = ''
    ACTION=="add", SUBSYSTEM=="block", ENV{ID_FS_TYPE}=="zfs_member", ENV{ID_FS_LABEL}=="${pool}", TAG+="systemd", ENV{SYSTEMD_WANTS}+="zbackup-usb.service"
  '';
}
