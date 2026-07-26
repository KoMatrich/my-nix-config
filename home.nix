{ config, pkgs, ... }:

{
    home.username = "komatrich";
    home.homeDirectory = "/home/komatrich";

    home.packages = [
      pkgs.vlc
      pkgs.digikam
      pkgs.discord
      pkgs.gimp pkgs.imagemagick

      pkgs.vmtouch

      pkgs.prusa-slicer

      pkgs.claude-code
      pkgs.jq
      pkgs.libnotify

      pkgs.chromium

      pkgs.unityhub
      pkgs.figma-linux
      pkgs.vue

      pkgs.zotero
      pkgs.obsidian

      pkgs.spotify
    ];
    
    programs.git = {
      package = pkgs.gitFull;
      enable = true;
      lfs.enable = true;
      settings = {
        user.name = "Martin Kocich";
        user.email = "kocichmartin@gmail.com";
        init.defaultBranch = "main";
      };
    };

    programs.direnv.enable = true;
    programs.vscode = {
      enable = true;
    };

    services.gpg-agent = {
      enable = true;
      enableSshSupport = true;
      defaultCacheTtl = 1800;
    };
    
    programs.firefox.enable = true;
    # Keep the pre-26.05 profile location; the existing profile lives here.
    programs.firefox.configPath = ".mozilla/firefox";

    # Let Home Manager install and manage itself.
    programs.home-manager.enable = true;

    # The state version is required and should stay at the version you
    # originally installed.
    home.stateVersion = "25.05";
}
