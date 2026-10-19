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
  ] ++ lib.optional wifi wifiSync;

  # Pair records (the "Trust this computer" result, incl. the phone's Wi-Fi
  # MAC that Wi-Fi discovery matches on). Lost on every boot otherwise.
  environment.persistence."/persist".directories = [
    { directory = "/var/lib/lockdown"; user = config.services.usbmuxd.user; group = config.services.usbmuxd.group; mode = "0750"; }
  ];
}
