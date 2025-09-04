{ config, pkgs, ... }:

{
    home.username = "komatrich";
    home.homeDirectory = "/home/komatrich";
    
    # Add programs from user profile to PATH
    home.sessionPath = [
      "$HOME/.local/bin"
    ];

    programs.bash = {
      enable = true;
      shellAliases = {
        ll = "ls -la";
        gs = "git status";
        gd = "git diff";
        gc = "git commit";
        gp = "git push";
        gl = "git pull";
        rebuild = "sudo nixos-rebuild switch --flake /etc/nixos#default --show-trace";
      };
    };

    home.packages = [
      pkgs.vlc
      pkgs.digikam
      pkgs.discord
      
      # Game development
      pkgs.godot
      pkgs.godot-mono
      pkgs.unityhub

      # Image editing
      pkgs.gimp pkgs.imagemagick
      pkgs.pixelorama
      
      pkgs.vmtouch # Keep files in memory
      
      pkgs.dconf2nix # Export and import dconf settings
      
      pkgs.uv # Python manager
      
      pkgs.gnomeExtensions.appindicator
      pkgs.gnomeExtensions.blur-my-shell
      pkgs.gnomeExtensions.gsconnect
      pkgs.gnomeExtensions.caffeine

      pkgs.firefox
      pkgs.vue
    ];

    programs.git = {
      package = pkgs.gitAndTools.gitFull;
      enable = true;
      lfs.enable = true;
      userName = "Martin Kocich";
      userEmail = "kocichmartin@gmail.com";
      extraConfig = {
        init.defaultBranch = "master";
        credential.helper = "${
            pkgs.git.override { withLibsecret = true; }
          }/bin/git-credential-libsecret";
        push = { autoSetupRemote = true; };
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
          caffeine.extensionUuid
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

    # Let Home Manager install and manage itself.
    programs.home-manager.enable = true;

    # The state version is required and should stay at the version you
    # originally installed.
    home.stateVersion = "25.05";
}
