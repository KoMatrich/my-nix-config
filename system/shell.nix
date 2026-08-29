# Day-to-day tooling: zsh (+ oh-my-zsh), nh (nix helper) and shell aliases
# for the common operations. Run `cheat` for a quick in-terminal reference;
# the full command reference lives in docs/CHEATSHEET.md.
{ config, lib, pkgs, ... }:
let
  # Shared by the `gc` alias and the automatic clean timer so they can't
  # drift. --no-direnv: dev shell gcroots are managed by the 30-day timer
  # in apps/devshells.nix, not by nh's 7-day window.
  gcArgs = "--keep-since 7d --keep 5 --no-direnv";

  # Single source of truth: the shell aliases and the `cheat` help text are
  # both generated from this list, so the help cannot drift out of sync.
  aliasGroups = [
    {
      title = "System management";
      aliases = [
        # verify = true installs these as wrapper scripts (mkVerified below)
        # instead of plain aliases, so a switch that silently fails to land is
        # reported instead of exiting 0.
        { name = "rebuild"; cmd = "nice -n 19 nh os switch"; desc = "Apply config changes from /etc/nixos"; verify = true; }
        { name = "update"; cmd = "nice -n 19 nh os switch --update"; desc = "Update flake inputs + rebuild"; verify = true; }
        { name = "gc"; cmd = "nice -n 19 nh clean all ${gcArgs}"; desc = "Delete old generations (keeps 7 days / last 5; dev shells expire separately after 30 days)"; }
        { name = "mute"; cmd="sudo sh -c \"echo 60 > /sys/devices/system/cpu/intel_pstate/max_perf_pct; echo 1 > /sys/devices/system/cpu/intel_pstate/no_turbo\""; desc="Lower cpu freq"; }
        { name = "unmute"; cmd="sudo sh -c \"echo 100 > /sys/devices/system/cpu/intel_pstate/max_perf_pct; echo 0 > /sys/devices/system/cpu/intel_pstate/no_turbo\""; desc="Normal cpu freq"; }
      ];
    }
    {
      title = "Dev shells (direnv)";
      aliases = [
        { name = "devshell-clean"; cmd = "systemctl --user start devshell-cleanup.service node-modules-cleanup.service && journalctl --user -u devshell-cleanup -u node-modules-cleanup --since -10min --no-pager"; desc = "Run the 30d shell / 60d node_modules cleanup now and show what was deleted"; }
      ];
    }
    {
      title = "ZFS health & snapshots";
      aliases = [
        { name = "zhealth"; cmd = "zpool status -x"; desc = "Pool health (silent = all good)"; }
        { name = "zsnaps"; cmd = "zfs list -t snapshot -o name,used,creation -s creation"; desc = "All snapshots, oldest first"; }
        { name = "zbackup-status"; cmd = "systemctl list-timers sanoid.timer 'syncoid-*' --all && zfs list -r -t snapshot -o name,creation zstorage/backup | tail -n 6"; desc = "Replication timers + latest backup snapshots on the SSD"; }
      ];
    }
  ];

  # Standalone scripts installed below; listed in `cheat` only.
  extraCommands = [
    { name = "fsdiff"; desc = "Every file on / that will be ERASED on next reboot"; }
    { name = "devshells"; desc = "List cached dev shells with last-used age and closure size"; }
    { name = "mkenvrc"; desc = "Create .envrc in the current project + direnv allow (makes its dev shell persistent)"; }
    { name = "mkflake"; desc = "Guided wizard: scaffold flake.nix (pick language + packages) + .envrc for a new project"; }
    { name = "cheat"; desc = "This help"; }
  ];

  allAliases = lib.concatMap (g: g.aliases) aliasGroups;
  isVerified = a: a.verify or false;

  # A `nh os switch` that exits 0 is not proof that anything happened: on
  # 2026-08-06 a shadowed `sudo env` let nh report success three times without
  # ever creating a generation. So after running the command, compare what the
  # flake evaluates to against what is actually running. This holds whether or
  # not the rebuild changed anything, unlike a before/after comparison — a
  # no-op switch legitimately leaves /run/current-system untouched.
  #
  # nix/nh are pinned to the system closure: running this from inside a
  # `nix develop` shell must not pick up that shell's toolchain.
  mkVerified = a: pkgs.writeShellScriptBin a.name ''
    PATH=${lib.makeBinPath [ config.programs.nh.package config.nix.package pkgs.coreutils ]}:$PATH

    ${a.cmd} "$@"
    status=$?

    want=$(nix eval --raw '${config.programs.nh.flake}#nixosConfigurations.${config.networking.hostName}.config.system.build.toplevel' 2>/dev/null)
    have=$(readlink -f /run/current-system)

    if [ -z "$want" ]; then
      printf '\n\033[1;33m! %s: could not verify — flake evaluation failed\033[0m\n' '${a.name}' >&2
      exit "$status"
    fi

    if [ "$want" != "$have" ]; then
      printf '\n\033[1;31m✗ %s did not land: /run/current-system does not match the config\033[0m\n' '${a.name}' >&2
      printf '    want: %s\n    have: %s\n' "$want" "$have" >&2
      printf '  If the command above looked successful, suspect a shadowed binary:\n' >&2
      printf '    ls -l ~/.local/bin/env && journalctl -t sudo --since -10min\n' >&2
      exit 1
    fi

    printf '\n\033[1;32m✓ %s landed: %s\033[0m\n' '${a.name}' "$have"
    exit "$status"
  '';

  pad = s: s + lib.strings.replicate (lib.max 1 (16 - lib.stringLength s)) " ";

  helpText = "Shell helpers from /etc/nixos/system/shell.nix (full docs: docs/CHEATSHEET.md)\n"
    + lib.concatMapStrings
      (g: "\n${g.title}\n" + lib.concatMapStrings
        (a: "  ${pad a.name}${a.desc}\n  ${pad ""}$ ${a.cmd}\n")
        g.aliases)
      aliasGroups
    + "\nCommands\n"
    + lib.concatMapStrings (c: "  ${pad c.name}${c.desc}\n") extraCommands;
in
{
  # nh = modern wrapper around nixos-rebuild / nix-collect-garbage with
  # diffs between generations and nicer output. clean.enable replaces the
  # old nix.gc setup (do not enable both).
  programs.nh = {
    enable = true;
    flake = "/etc/nixos";
    clean = {
      enable = true;
      extraArgs = gcArgs;
    };
  };

  # zsh as the login shell for all users (root included), with oh-my-zsh on
  # top. environment.shellAliases below flows into zsh automatically.
  programs.zsh = {
    enable = true;
    autosuggestions.enable = true; # grey inline suggestion from history, → accepts
    syntaxHighlighting.enable = true; # valid commands green, typos red
    ohMyZsh = {
      enable = true;
      theme = "robbyrussell";
      plugins = [
        "git" # gst / gco / gl / ... shortcuts
        "sudo" # press ESC twice to prepend sudo to the current/last command
        "z" # z <fragment> jumps to frecently used directories
        "extract" # extract <archive> handles any format
      ];
    };
  };
  users.defaultUserShell = pkgs.zsh;

  # Verified entries ship as scripts in systemPackages below; aliasing them
  # here too would shadow those scripts and skip the check.
  environment.shellAliases = lib.listToAttrs
    (map (a: lib.nameValuePair a.name a.cmd)
      (lib.filter (a: !isVerified a) allAliases));

  environment.systemPackages = map mkVerified (lib.filter isVerified allAliases) ++ [
    # Quick reference for everything defined in this file.
    (pkgs.writeShellScriptBin "cheat" ''
      printf '%s' ${lib.escapeShellArg helpText}
    '')

    # Lists every file on / that is NOT persisted, i.e. everything that will
    # be erased on the next reboot. Run it before rebooting to catch state
    # you forgot to add to apps/impermanence.nix.
    (pkgs.writeShellScriptBin "fsdiff" ''
      zfs diff zroot/local/root@blank "$@" | grep -Ev '/tmp/' | less
    '')
  ];
}
