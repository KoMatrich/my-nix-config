# CPU power profiles.
#
# power-profiles-daemon exposes performance/balanced/power-saver on D-Bus, and
# GNOME already renders it as the "Power Mode" row in Quick Settings (click the
# battery icon). But PPD's intel_pstate driver only moves
# energy_performance_preference - it never touches the frequency ceiling or the
# turbo bit, which is what the old sudo-based `mute`/`unmute` aliases did.
#
# The service below closes that gap: it follows PPD's ActiveProfile and applies
# the clamps itself. Because it runs as root, nothing needs sudo and no sysfs
# permissions are loosened - switching profiles goes through PPD's polkit
# action, which already allows any active local session without a password.
# See system/shell.nix for the `mute`/`unmute`/`cpu-mode` aliases that drive it
# from the terminal.
{ config, lib, pkgs, ... }:
let
  pstate = "/sys/devices/system/cpu/intel_pstate";

  # PPD 0.30 serves both org.freedesktop.UPower.PowerProfiles and the legacy
  # net.hadess.PowerProfiles alias; use the current name.
  dest = "org.freedesktop.UPower.PowerProfiles";
  objectPath = "/org/freedesktop/UPower/PowerProfiles";
in
{
  # On by default, but stated explicitly: both the clamp service below and the
  # shell aliases in system/shell.nix depend on it being present.
  services.power-profiles-daemon.enable = true;

  systemd.services.cpu-profile-clamp = {
    description = "Clamp intel_pstate to match the active power profile";
    wantedBy = [ "multi-user.target" ];
    after = [ "power-profiles-daemon.service" ];
    # BindsTo rather than Requires: if PPD goes away there is nothing to
    # follow, and Restart=always brings us back once it returns.
    bindsTo = [ "power-profiles-daemon.service" ];
    path = [ pkgs.glib pkgs.coreutils pkgs.gnused ];

    serviceConfig = {
      Type = "simple";
      # PPD restarting must not leave the clamps stuck at eco.
      Restart = "always";
      RestartSec = 5;
    };

    script = ''
      set -u

      apply() {
        case "$1" in
          power-saver)
            # The old `mute`: 60% frequency ceiling, turbo off.
            echo 60  > ${pstate}/max_perf_pct
            echo 1   > ${pstate}/no_turbo
            ;;
          balanced|performance)
            # The old `unmute`. balanced is deliberately identical to
            # performance so the two-state mute/unmute semantics are preserved;
            # make balanced a genuine middle (no_turbo=1, ceiling 100) here if
            # that turns out to be wanted.
            echo 100 > ${pstate}/max_perf_pct
            echo 0   > ${pstate}/no_turbo
            ;;
          *)
            echo "cpu-profile-clamp: unknown profile '$1', leaving clamps alone" >&2
            return 0
            ;;
        esac
        echo "cpu-profile-clamp: applied '$1' (max_perf_pct=$(cat ${pstate}/max_perf_pct) no_turbo=$(cat ${pstate}/no_turbo))"
      }

      current() {
        # gdbus prints the property as: (<'performance'>,)
        gdbus call --system --dest ${dest} --object-path ${objectPath} \
          --method org.freedesktop.DBus.Properties.Get \
          ${dest} ActiveProfile \
          | sed -n "s/.*<'\(.*\)'>.*/\1/p"
      }

      # Sync once before watching, otherwise a restart of this unit leaves the
      # clamps out of step with the profile GNOME is displaying.
      apply "$(current)"

      # PropertiesChanged fires on every profile switch, including PPD's own
      # automatic drop to power-saver on low battery (BatteryAware=true).
      # Re-read the property rather than parsing it out of the signal body.
      gdbus monitor --system --dest ${dest} --object-path ${objectPath} \
        | while read -r line; do
            case "$line" in
              *ActiveProfile*) apply "$(current)" ;;
            esac
          done
    '';
  };
}
