{ config, pkgs, voice2text, local-ci, ... }:

{
    imports = [
      voice2text.homeModules.default
      local-ci.homeModules.default
    ];

    # Push-to-talk dictation; runs as a user service from graphical-session.
    services.voice2text.enable = true;

    # The `local-ci` command, plus user timers that check GitHub and ask
    # (desktop notification) before building images or running PR tests.
    # Repos, images and settings live in config.toml, read on every run;
    # see ~/Tools/local-ci/README.md and docs/operations.md.
    services.local-ci = {
      enable = true;
      configFile = "/home/komatrich/Tools/local-ci/config.toml";
      build.enable = true; # local-ci-build: new commits missing from the registry
      test.enable = true; # local-ci-test: enable once config.toml has a [repo.test]
    };

    home.username = "komatrich";
    home.homeDirectory = "/home/komatrich";

    home.packages = [
      pkgs.vlc
      pkgs.digikam
      pkgs.discord
      pkgs.gimp pkgs.imagemagick
      pkgs.inkscape
      pkgs.blender

      pkgs.vmtouch

      pkgs.prusa-slicer

      pkgs.claude-code
      pkgs.aider-chat
      pkgs.jq
      pkgs.libnotify

      # gh copies one-time login codes with the first of these it finds.
      pkgs.wl-clipboard # Wayland: wl-copy / wl-paste
      pkgs.xclip # X11 and XWayland apps

      pkgs.chromium

      pkgs.unityhub
      pkgs.figma-linux
      pkgs.vue

      pkgs.zotero
      pkgs.obsidian

      pkgs.libreoffice-qt
      pkgs.hunspell
      pkgs.hunspellDicts.cs_CZ
      pkgs.hunspellDicts.uk_UA

      pkgs.prismlauncher
      pkgs.arduino
      pkgs.freecad
      pkgs.net-tools

      # opencode's bundled native file-watcher addon dlopen()s libstdc++.so.6
      # at runtime, which isn't on the default search path under Nix (no FHS).
      # Wrap just this binary with LD_LIBRARY_PATH rather than setting it
      # system-wide, to avoid shadowing other packages' own libstdc++.
      (pkgs.symlinkJoin {
        name = "opencode";
        paths = [ pkgs.opencode ];
        buildInputs = [ pkgs.makeWrapper ];
        postBuild = ''
          wrapProgram $out/bin/opencode \
            --suffix LD_LIBRARY_PATH : ${pkgs.stdenv.cc.cc.lib}/lib
        '';
      })
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
