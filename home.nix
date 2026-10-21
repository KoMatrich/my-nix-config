{ config, lib, pkgs, voice2text, local-ci, pi-flake, ... }:

{
    imports = [
      voice2text.homeModules.default
      local-ci.homeModules.default
      pi-flake.homeManagerModules.default
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
      build.enable = false; # local-ci-build: new commits missing from the registry
      test.enable = false; # local-ci-test: enable once config.toml has a [repo.test]
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
      pkgs.claude-desktop
      pkgs.aider-chat
      # Herdr (herdr.dev) agent runtime; provided by the herdr flake's overlay
      # (see flake.nix) and built from source there.
      pkgs.herdr
      pkgs.jq
      pkgs.libnotify

      # CLI productivity: fast search (ripgrep/fd), structural
      # search-and-rewrite (ast-grep), command benchmarking (hyperfine).
      # delta is wired below via programs.delta, not listed here.
      pkgs.ripgrep
      pkgs.fd
      pkgs.ast-grep
      pkgs.hyperfine

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

      pkgs.arduino
      pkgs.freecad
      pkgs.net-tools

      # Raspberry Pi Imager, for writing SD cards. nixos-26.05 ships 2.0.9;
      # upstream is at 2.0.12, so version + src are overridden here. Drop the
      # override once nixpkgs catches up (check `nix eval nixpkgs#rpi-imager.version`).
      (pkgs.rpi-imager.overrideAttrs (old: rec {
        version = "2.0.12";
        src = pkgs.fetchFromGitHub {
          owner = "raspberrypi";
          repo = "rpi-imager";
          tag = "v${version}";
          hash = "sha256-oIq7+NxTh/IQH78xSfXLZeKx7uMJ3T7THychdb3QcZg=";
        };
      }))

      # Bootable USB writers (Rufus is Windows-only). Impression: GNOME app
      # for Linux/hybrid ISOs (dd-style). WoeUSB-ng: Windows installer ISOs,
      # which can't simply be dd'd (needs NTFS/UEFI:NTFS split) - `woeusbgui`
      # or `sudo woeusb --device win.iso /dev/sdX`. Ventoy is left out:
      # nixpkgs marks it insecure (prebuilt binary blobs).
      pkgs.impression
      pkgs.woeusb-ng

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

    programs.delta = {
      enable = true;
      enableGitIntegration = true;
    };

    # Pi coding agent, installed globally (the module adds it to home.packages)
    # together with Superpowers and the pi-subagents delegation extension.
    # `agentFiles.models` is a read-only symlink into the Nix store declaring the
    # same e-INFRA gateway opencode uses; Pi runs the apiKey command at request
    # time, so the token never lands in the store. The model list lives in
    # ./pi-models.nix and is refreshed with `pi-models-refresh` (then commit).
    programs.pi-coding-agent = {
      enable = true;

      # Left empty on purpose: the module runs `pi install` on every
      # activation with no failure tolerance, so a boot-time activation
      # (network not up yet, NetworkManager-wait-online is disabled) failed
      # the whole home-manager unit. Installed by piExtensions below instead.
      extensions = [ ];

      agentFiles.models = {
        value = {
          providers = {
            e-infra = {
              name = "LLM AI e-infra";
              baseUrl = "https://llm.ai.e-infra.cz/v1";
              api = "openai-completions";
              apiKey = "!cat /home/komatrich/.config/opencode/einfra-token";
              models = import ./pi-models.nix;
            };
          };
        };
      };
    };

    # Best-effort Pi extension install/refresh: an offline boot keeps the
    # already-cached copies instead of failing activation.
    home.activation.piExtensions = lib.hm.dag.entryAfter [ "piCodingAgentConfig" ] ''
      for ext in git:github.com/obra/superpowers npm:pi-subagents; do
        echo "[Pi] installing extension: $ext"
        PATH="${pkgs.gitMinimal}/bin:$PATH" ${config.programs.pi-coding-agent.package}/bin/pi install "$ext" 2>&1 \
          || echo "[Pi] could not install $ext (offline?), keeping cached copy"
      done
    '';

    programs.direnv.enable = true;
    programs.vscode = {
      enable = true;
    };

    # kitty: claude-notifications-go has full tab-level click-to-focus support
    # for it (unlike GNOME Console, which is window-level only). Remote
    # control (scoped to a per-instance socket, not exposed to other apps)
    # lets it jump straight to the exact tab, via $KITTY_LISTEN_ON.
    programs.kitty.enable = true;
    programs.kitty.settings = {
      allow_remote_control = "socket-only";
      listen_on = "unix:/tmp/kitty-{kitty_pid}";
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
