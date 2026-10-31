# iPhone support: USB access (Files/ifuse/libimobiledevice) and full device
# backups with `iphone-backup`, over USB or - once enabled - over Wi-Fi.
# One-time setup and restore: docs/CHEATSHEET.md, "iPhone".
#
# Backups land in ~/Backups/iPhone, i.e. on /home, so the sanoid/syncoid
# replication and the USB HDD backup cover them like any other home data.
{ config, lib, pkgs, ... }:
let
  # usbmuxd2 is a drop-in usbmuxd that also discovers paired iPhones on the
  # LAN via avahi (`_apple-mobdev2._tcp`), which is what makes Wi-Fi backups
  # possible; stock usbmuxd is USB-only. Its nixpkgs snapshot is from 2023,
  # so if it ever misbehaves set this to false - USB keeps working.
  wifi = true;

  wifiSync = pkgs.runCommandCC "iphone-wifi-sync" {
    nativeBuildInputs = [ pkgs.pkg-config ];
    buildInputs = [ pkgs.libimobiledevice pkgs.libplist ];
  } ''
    mkdir -p $out/bin
    $CC -O2 -Wall -Werror ${./iphone-wifi-sync.c} -o $out/bin/iphone-wifi-sync \
      $(pkg-config --cflags --libs libimobiledevice-1.0 libplist-2.0)
  '';

  backup = pkgs.writeShellApplication {
    name = "iphone-backup";
    runtimeInputs = [ pkgs.libimobiledevice pkgs.coreutils ];
    text = ''
      dest="''${IPHONE_BACKUP_DIR:-$HOME/Backups/iPhone}"
      mkdir -p "$dest"

      # Prefer USB (faster, always works); fall back to a Wi-Fi device.
      if udid=$(idevice_id -l 2>/dev/null | head -n 1) && [ -n "$udid" ]; then
        sel=(-u "$udid"); via="USB"
      elif udid=$(idevice_id -n 2>/dev/null | head -n 1) && [ -n "$udid" ]; then
        sel=(-n -u "$udid"); via="Wi-Fi"
      else
        echo "No iPhone found. Plug it in (and tap Trust), or for Wi-Fi: same" >&2
        echo "network, phone unlocked, and 'iphone-wifi-sync on' done once over USB." >&2
        exit 1
      fi

      echo "Backing up $(idevicename "''${sel[@]}" 2>/dev/null || echo "$udid") over $via to $dest"
      # Extra args (e.g. --full) go to `idevicebackup2 backup`; incremental by default.
      idevicebackup2 "''${sel[@]}" backup "$@" "$dest"
    '';
  };

  # Unattended run (also callable by hand): copy new photos/videos from the
  # phone into ~/Pictures/<phone name>/ and, at most once a day, take a full
  # device backup. Silent no-op when the phone isn't reachable.
  sync = pkgs.writeShellApplication {
    name = "iphone-sync";
    runtimeInputs = [ pkgs.libimobiledevice pkgs.ifuse pkgs.coreutils pkgs.findutils pkgs.systemd backup ];
    text = ''
      state="''${XDG_STATE_HOME:-$HOME/.local/state}/iphone-sync"
      stamp="$state/last-backup"
      mkdir -p "$state"

      if udid=$(idevice_id -l 2>/dev/null | head -n 1) && [ -n "$udid" ]; then
        sel=(-u "$udid")
      elif udid=$(idevice_id -n 2>/dev/null | head -n 1) && [ -n "$udid" ]; then
        sel=(-n -u "$udid")
      else
        echo "iPhone not reachable - nothing to do."
        exit 0
      fi

      name=$(idevicename "''${sel[@]}" 2>/dev/null | head -n 1 | tr -c 'A-Za-z0-9._\n-' '_' || true)
      [ -n "$name" ] || name="iPhone-$udid"
      photos="''${IPHONE_PHOTOS_DIR:-$HOME/Pictures}/$name"
      mnt="''${XDG_RUNTIME_DIR:-/tmp}/iphone-sync-mnt"

      # Stop the laptop from suspending mid-transfer.
      if [ -z "''${IPHONE_SYNC_INHIBITED:-}" ]; then
        IPHONE_SYNC_INHIBITED=1 exec systemd-inhibit --what=sleep:idle --why="iPhone sync" "$0" "$@"
      fi

      # ---- photos -------------------------------------------------------
      mkdir -p "$photos" "$mnt"
      if ! ifuse "$mnt" "''${sel[@]}"; then
        echo "Could not mount the phone (locked? not trusted?). Unlock it and retry." >&2
        exit 1
      fi
      unmount() { fusermount -u "$mnt" 2>/dev/null || fusermount3 -u "$mnt" 2>/dev/null || true; }
      trap unmount EXIT

      copied=0
      while IFS= read -r -d "" f; do
        b=$(basename "$f")
        d="$photos/$b"
        # Same name, different size = a different file (counter wrapped): prefix its folder.
        if [ -e "$d" ] && [ "$(stat -c %s "$d")" != "$(stat -c %s "$f")" ]; then
          d="$photos/$(basename "$(dirname "$f")")_$b"
        fi
        [ -e "$d" ] && continue
        cp -p "$f" "$d.part" && mv "$d.part" "$d"
        copied=$((copied + 1))
      done < <(find "$mnt/DCIM" -type f -print0 2>/dev/null)
      echo "Photos: $copied new file(s) copied to $photos"
      unmount
      trap - EXIT

      # ---- full device backup, at most once per 24h ---------------------
      if [ -z "''${IPHONE_SYNC_FORCE_BACKUP:-}" ] && [ -e "$stamp" ] && [ -z "$(find "$stamp" -mmin +1440)" ]; then
        echo "Backup: done within the last 24h, skipping."
      else
        iphone-backup
        touch "$stamp"
      fi
    '';
  };
in
{
  services.usbmuxd = {
    enable = true;
    package = if wifi then pkgs.usbmuxd2 else pkgs.usbmuxd;
  };

  # Start only once the persisted /var/lib/lockdown is bind-mounted - else on
  # the first switch usbmuxd may write its SystemConfiguration.plist (host ID)
  # to the ephemeral root, and pairings made then break after a reboot.
  systemd.services.usbmuxd.unitConfig.RequiresMountsFor = [ "/var/lib/lockdown" ];

  # Fallback if a paired phone never shows up in `idevice_id -n` (newer iOS
  # may not send the heartbeat usbmuxd2 waits for):
  # systemd.services.usbmuxd.serviceConfig.ExecStart = lib.mkForce
  #   "${config.services.usbmuxd.package}/bin/usbmuxd -U ${config.services.usbmuxd.user} -v --allow-heartless-wifi";

  environment.systemPackages = [
    pkgs.libimobiledevice # idevicepair, idevicebackup2, ideviceinfo, ...
    pkgs.ifuse            # mount the phone's media/app files: `ifuse ~/iPhone`
    backup
    sync
  ] ++ lib.optional wifi wifiSync;

  # Every 30 min: if the phone is reachable (USB or Wi-Fi) pull new photos and,
  # once a day, back it up. User-level so files land owned by komatrich.
  systemd.user.services.iphone-sync = {
    description = "Copy iPhone photos and back up the device";
    path = [ "/run/wrappers/bin" ]; # setuid fusermount for ifuse
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${sync}/bin/iphone-sync";
      Nice = 10;
    };
  };
  systemd.user.timers.iphone-sync = {
    description = "Periodic iPhone photo copy + backup";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnStartupSec = "5min";
      OnUnitInactiveSec = "30min";
    };
  };

  # Pair records (the "Trust this computer" result, incl. the phone's Wi-Fi
  # MAC that Wi-Fi discovery matches on). Lost on every boot otherwise.
  environment.persistence."/persist".directories = [
    { directory = "/var/lib/lockdown"; user = config.services.usbmuxd.user; group = config.services.usbmuxd.group; mode = "0750"; }
  ];
}
