# When the machine is allowed to suspend.
#
# Two separate mechanisms decide that, and both had to be addressed:
#
#   1. logind's lid switch. Already set to "ignore" - but that only stops the
#      lid *event* from triggering a suspend.
#   2. GNOME's idle timer (org.gnome.settings-daemon.plugins.power,
#      sleep-inactive-*-type = suspend after 15 min). GNOME derives "idle"
#      from input activity via mutter, so it happily suspends a machine that
#      is 100% busy compiling, and it suspends a lid-closed machine 15 minutes
#      after the lid went down. This is what actually interrupts long jobs.
#
# Rather than turning GNOME's idle suspend off wholesale (we still want an
# untouched, idle laptop to suspend), the stay-awake service below holds a
# logind *block* inhibitor for exactly as long as there is a reason to stay
# up. GNOME's idle path calls logind Suspend(), which a block inhibitor
# refuses, so the suspend simply does not happen.
#
# Caveat: while the inhibitor is held, "Suspend" from GNOME's Quick Settings
# is also refused (that is the price of a block inhibitor - a delay inhibitor
# would only postpone the suspend by a few seconds, not prevent it).
# `systemd-inhibit --list` shows whether it is currently held, and
# `journalctl -u stay-awake` shows why it was taken and released.
{ config, lib, pkgs, ... }:
let
  # Average CPU utilisation across all cores, in percent, at or above which
  # suspend is blocked. Averaged over `interval`, idle+iowait counted as idle.
  # 25% is roughly two of eight cores pinned.
  #
  # Measured on this machine: an *actively used* desktop (VS Code + Discord +
  # GNOME + an agent running shell commands) sits at 18-27%, i.e. right on
  # this threshold. That is fine - while you are actually at the keyboard
  # GNOME's idle timer never fires anyway, so the inhibitor being held is
  # harmless. It only matters once you walk away, and an unattended VS Code /
  # Discord idle down well below this.
  #
  # If the machine turns out never to suspend on its own, this is the one
  # number to raise (40 only blocks suspend for genuinely heavy work);
  # `journalctl -u stay-awake` shows the percentages it actually saw.
  cpuThreshold = 25;

  # Seconds between samples. Also the averaging window for the CPU figure.
  interval = 20;

  # Consecutive below-threshold samples required before the inhibitor is
  # dropped again. A build dipping under the threshold between compile units
  # must not hand GNOME a window to suspend in, so releasing is deliberately
  # lazier than taking: 3 * 20s = a minute of genuine quiet.
  releaseAfter = 3;
in
{
  # Lid events themselves: never suspend, in any of the three cases systemd
  # distinguishes. HandleLidSwitchExternalPower and HandleLidSwitchDocked
  # inherit HandleLidSwitch when unset, but stating them makes it explicit
  # that docking or unplugging does not quietly change the answer.
  # (These moved from the old services.logind.lidSwitch aliases, which 26.05
  # still accepts but renames onto settings.Login.)
  services.logind.settings.Login = {
    HandleLidSwitch = "ignore";
    HandleLidSwitchExternalPower = "ignore";
    HandleLidSwitchDocked = "ignore";
  };

  systemd.services.stay-awake = {
    description = "Block suspend while the CPU is busy or the lid is closed on AC";
    wantedBy = [ "multi-user.target" ];
    after = [ "systemd-logind.service" ];
    path = [ pkgs.systemd pkgs.coreutils ];

    serviceConfig = {
      Type = "simple";
      Restart = "always";
      RestartSec = 5;
      # The inhibitor is held open by a child process; it dies with the unit,
      # so a stop or restart can never leave a stale block inhibitor behind.
      KillMode = "control-group";
    };

    script = ''
      set -u

      inhibit_pid=""

      lid_closed() {
        local state
        for f in /proc/acpi/button/lid/*/state; do
          if [ -r "$f" ]; then
            # "state:      open" / "state:      closed"
            read -r _ state < "$f" || continue
            if [ "$state" = "closed" ]; then return 0; fi
          fi
        done
        return 1
      }

      on_ac() {
        local type online
        for d in /sys/class/power_supply/*/; do
          if [ -r "$d/type" ] && [ -r "$d/online" ]; then
            read -r type < "$d/type" || continue
            read -r online < "$d/online" || continue
            if [ "$type" = "Mains" ] && [ "$online" = "1" ]; then return 0; fi
          fi
        done
        return 1
      }

      hold() {
        if [ -z "$inhibit_pid" ] || ! kill -0 "$inhibit_pid" 2>/dev/null; then
          systemd-inhibit \
            --what=idle:sleep --mode=block \
            --who="stay-awake" --why="CPU busy or lid closed on AC" \
            sleep infinity &
          inhibit_pid=$!
          echo "stay-awake: blocking suspend ($1)"
        fi
      }

      release() {
        if [ -n "$inhibit_pid" ] && kill -0 "$inhibit_pid" 2>/dev/null; then
          kill "$inhibit_pid" 2>/dev/null || true
          wait "$inhibit_pid" 2>/dev/null || true
          echo "stay-awake: suspend allowed again"
        fi
        inhibit_pid=""
      }

      # Cumulative jiffies from /proc/stat's aggregate "cpu" line. Deltas
      # between two samples give utilisation over the window; iowait counts as
      # idle, so a sleeping machine waiting on ZFS does not pin itself awake.
      sample() {
        local user nice system idle iowait irq softirq steal rest
        read -r _ user nice system idle iowait irq softirq steal rest < /proc/stat
        total=$((user + nice + system + idle + iowait + irq + softirq + steal))
        idle_total=$((idle + iowait))
      }

      # Prime the counters, otherwise the first comparison is against boot.
      sample
      prev_total=$total
      prev_idle=$idle_total
      idle_streak=0

      while true; do
        sleep ${toString interval}

        sample
        d_total=$((total - prev_total))
        d_idle=$((idle_total - prev_idle))
        prev_total=$total
        prev_idle=$idle_total

        busy=0
        if [ "$d_total" -gt 0 ]; then
          busy=$(( (100 * (d_total - d_idle)) / d_total ))
        fi

        reason=""
        if [ "$busy" -ge ${toString cpuThreshold} ]; then
          reason="CPU at ''${busy}%"
        elif lid_closed && on_ac; then
          # On battery a closed lid is left to GNOME's normal idle suspend, so
          # a laptop shut into a bag does not run itself flat.
          reason="lid closed on AC"
        fi

        if [ -n "$reason" ]; then
          idle_streak=0
          hold "$reason"
        else
          idle_streak=$((idle_streak + 1))
          if [ "$idle_streak" -ge ${toString releaseAfter} ]; then
            release
          fi
        fi
      done
    '';
  };
}
