# Weekly unattended system update. Each run:
#
#   1. skips (and alerts) if /etc/nixos has uncommitted changes: the build
#      would otherwise silently include half-done work;
#   2. `nix flake update`; stops quietly if no input moved;
#   3. builds the new system and makes it the default boot entry
#      (switch-to-configuration *boot*: nothing changes under a running
#      desktop, the update applies on the next reboot);
#   4. commits flake.lock as "FEAT: auto flake update", so every automatic
#      update is one revertable commit.
#
# Any failure after step 2 restores flake.lock, so a failed build cannot leave
# the tree dirty (which would make every later run skip). Failures pop up via
# notify-failure@ (system/notify.nix); a successful update pops up a "reboot to
# apply" notification. Roll back by picking an older generation in the boot
# menu, or `git revert` the commit and `rebuild`.
#
# git and nix run as the repo's owner (config.local.user): root operating on a
# user-owned repo trips git's ownership checks, and the commit should carry the
# user's identity. Only the profile switch runs as root.
#
#   autoupdate-now / autoupdate-status   (aliases in system/shell.nix)
{ config, lib, pkgs, ... }:
let
  user = config.local.user;
  repo = config.programs.nh.flake;
  host = config.networking.hostName;
  notify = lib.getExe config.local.notifyDesktop;

  autoupdate = pkgs.writeShellApplication {
    name = "nixos-autoupdate";
    runtimeInputs = [ config.nix.package pkgs.git pkgs.util-linux pkgs.coreutils ];
    text = ''
      # runuser sets HOME/USER for the target user (git finds their identity);
      # PATH is passed explicitly so it is this script's pinned tools.
      as_user() { runuser -u ${user} -- ${pkgs.coreutils}/bin/env PATH="$PATH" "$@"; }

      cd ${repo}

      if ! dirty=$(as_user git status --porcelain --untracked-files=no); then
        echo "git status failed in ${repo}; not updating" >&2
        exit 1
      fi
      if [ -n "$dirty" ]; then
        echo "uncommitted changes in ${repo}; commit or stash them, then run autoupdate-now:" >&2
        echo "$dirty" >&2
        exit 1
      fi

      restore_lock() { as_user git checkout -- flake.lock || true; }
      trap restore_lock EXIT

      as_user nix flake update --flake ${repo}

      if as_user git diff --quiet -- flake.lock; then
        echo "all flake inputs already up to date"
        exit 0
      fi
      as_user git --no-pager diff --stat -- flake.lock

      out=$(as_user nix build --no-link --print-out-paths \
        "${repo}#nixosConfigurations.${host}.config.system.build.toplevel")
      echo "built $out"

      nix-env -p /nix/var/nix/profiles/system --set "$out"
      "$out/bin/switch-to-configuration" boot

      as_user git commit --quiet -m "FEAT: auto flake update" -- flake.lock
      trap - EXIT
      echo "committed $(as_user git rev-parse --short HEAD); applies on next boot"

      ${notify} --app-name=nixos-autoupdate --icon=system-software-update \
        "System updated" "New generation is the default boot entry; reboot to apply."
    '';
  };
in
{
  systemd.services.nixos-autoupdate = {
    description = "Weekly flake update + build (applies on next boot)";
    wants = [ "network-online.target" ];
    after = [ "network-online.target" ];
    onFailure = [ "notify-failure@%n.service" ];
    # Never (re)start as a side effect of a rebuild, only from the timer.
    restartIfChanged = false;
    serviceConfig = {
      Type = "oneshot";
      ExecStart = lib.getExe autoupdate;
      Nice = 19;
      IOSchedulingClass = "idle";
    };
  };

  systemd.timers.nixos-autoupdate = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "weekly";
      # Catch up at the next boot if the machine was off at the scheduled
      # time (/var/lib/systemd/timers is persisted, apps/impermanence.nix).
      Persistent = true;
      RandomizedDelaySec = "1h";
    };
  };
}
