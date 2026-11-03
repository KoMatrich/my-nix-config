# Desktop notifications for things that would otherwise fail silently.
#
# Root services cannot reach the user's notification daemon directly, so
# `notify-desktop` hops onto komatrich's session bus (best effort: nothing is
# shown, and the call still succeeds, while nobody is logged in).
#
#   - notify-failure@<unit>.service: hang it off any unit with
#       systemd.services.<name>.onFailure = [ "notify-failure@%n.service" ];
#     and a failure of that unit pops up a critical notification.
#   - ZED (ZFS event daemon): pool faults, device errors, failed scrubs.
#   - smartd: SMART health of the NVMe and the SATA SSD.
#
# Test the whole path with:
#   sudo systemctl start notify-failure@test.service
{ config, lib, pkgs, ... }:
let
  user = config.local.user;

  notifyDesktop = pkgs.writeShellApplication {
    name = "notify-desktop";
    runtimeInputs = [ pkgs.libnotify pkgs.util-linux pkgs.coreutils ];
    text = ''
      uid=$(id -u ${user})
      bus=/run/user/$uid/bus
      if [ ! -S "$bus" ]; then
        echo "notify-desktop: ${user} has no session bus, not shown: $*" >&2
        exit 0
      fi
      runuser -u ${user} -- env DBUS_SESSION_BUS_ADDRESS="unix:path=$bus" \
        notify-send "$@" || true
    '';
  };

  # ZED calls ZED_EMAIL_PROG with ZED_EMAIL_OPTS (subject below) and the event
  # body on stdin; turn that into a notification instead of a mail.
  zedNotify = pkgs.writeShellScript "zed-notify" ''
    subject=''${1:-ZFS event}
    body=$(${pkgs.coreutils}/bin/head -c 1500)
    ${lib.getExe notifyDesktop} --urgency=critical --app-name=ZFS \
      --icon=drive-harddisk "$subject" "$body"
  '';
in
{
  options.local.notifyDesktop = lib.mkOption {
    type = lib.types.package;
    readOnly = true;
    internal = true;
    description = "Script that shows a desktop notification from a root service.";
  };

  config = {
    local.notifyDesktop = notifyDesktop;
    environment.systemPackages = [ notifyDesktop ];

    systemd.services."notify-failure@" = {
      description = "Desktop notification: %i failed";
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${lib.getExe notifyDesktop} --urgency=critical --app-name=systemd --icon=dialog-error \"%i failed\" \"See: journalctl -u %i\"";
      };
    };

    services.zfs.zed = {
      enableMail = false;
      settings = {
        # zed_notify() only takes the email path when an address is set; the
        # address itself is never used, ZED_EMAIL_OPTS does not pass it on.
        ZED_EMAIL_ADDR = [ "root" ];
        ZED_EMAIL_PROG = "${zedNotify}";
        ZED_EMAIL_OPTS = "'@SUBJECT@'";
        # Also report finished scrubs/resilvers, so the monthly scrub visibly
        # happened (one notification a month).
        ZED_NOTIFY_VERBOSE = true;
        ZED_NOTIFY_INTERVAL_SECS = 3600;
      };
    };

    # SMART monitoring of every disk smartd finds. systembus-notify forwards
    # its warnings to the desktop (the module enables the user-side daemon).
    # x11 notifications are xmessage-based and do not work under Wayland.
    services.smartd = {
      enable = true;
      notifications = {
        systembus-notify.enable = true;
        wall.enable = true;
        x11.enable = false;
      };
    };
  };
}
