{ config, pkgs, ... }:

{
    home.username = "komatrich";
    home.homeDirectory = "/home/komatrich";

    home.packages = [
      pkgs.vlc
      pkgs.digikam
      pkgs.discord
      pkgs.gimp pkgs.imagemagick
      
      pkgs.godot
      pkgs.godot-mono
      
      pkgs.vmtouch
      
      pkgs.dconf2nix
      
      pkgs.uv
      
      pkgs.gnomeExtensions.appindicator
      pkgs.gnomeExtensions.blur-my-shell
      pkgs.gnomeExtensions.gsconnect

      pkgs.unityhub
    ];
    
    programs.git = {
      package = pkgs.gitAndTools.gitFull;
      enable = true;
      lfs.enable = true;
      userName = "Martin Kocich";
      userEmail = "kocichmartin@gmail.com";
      extraConfig = {
        init.defaultBranch = "main";
      };
    };

    dconf = {
      enable = true;
      settings."org/gnome/shell" = {
        disable-user-extensions = false;
        enabled-extensions = with pkgs.gnomeExtensions; [
          appindicator.extensionUuid
          blur-my-shell.extensionUuid
          gsconnect.extensionUuid
        ];
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

    # Let Home Manager install and manage itself.
    programs.home-manager.enable = true;

    # The state version is required and should stay at the version you
    # originally installed.
    home.stateVersion = "25.05";
}
