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
        { name = "rebuild"; cmd = "nh os switch"; desc = "Apply config changes from /etc/nixos"; }
        { name = "update"; cmd = "nh os switch --update"; desc = "Update flake inputs + rebuild"; }
        { name = "gc"; cmd = "nh clean all ${gcArgs}"; desc = "Delete old generations (keeps 7 days / last 5; dev shells expire separately after 30 days)"; }
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

  environment.shellAliases = lib.listToAttrs
    (map (a: lib.nameValuePair a.name a.cmd)
      (lib.concatMap (g: g.aliases) aliasGroups));

  environment.systemPackages = [
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
