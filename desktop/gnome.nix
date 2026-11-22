# GNOME desktop environment.
# Active when desktop.environment = "gnome" (the default; see desktop/default.nix).
# GDM, autologin, xkb layout and other desktop-agnostic settings stay in
# configuration.nix; this file carries everything GNOME-specific, including
# the home-manager parts for komatrich (merged with home.nix).

{ config, lib, pkgs, ... }:

let
  # Paired phone "Mini-Black-Box". The ID changes if the phone is re-paired;
  # find the new one with `dconf list /org/gnome/shell/extensions/gsconnect/device/`.
  gsconnectPhone = "fc4ca467_a6c5_46f4_8098_f2285679829a";

  # "Night mode" for the phone's Run Command: backlight to minimum, notification
  # banners off (Do Not Disturb), then panel off until the next mouse/keyboard input.
  # GNOME 49+ moved brightness into Mutter, so it goes through
  # org.gnome.Mutter.DisplayConfig instead of gsd-power. Brightness and DND stay
  # as set after waking.
  screenSleep = pkgs.writeShellApplication {
    name = "screen-sleep";
    runtimeInputs = [ pkgs.glib pkgs.gnugrep pkgs.gnused pkgs.coreutils ];
    text = ''
      dc=(--session --dest org.gnome.Mutter.DisplayConfig --object-path /org/gnome/Mutter/DisplayConfig)
      im=(--session --dest org.gnome.Mutter.IdleMonitor --object-path /org/gnome/Mutter/IdleMonitor/Core)

      # 1. Every backlit panel to its minimum.
      # Backlight = (serial, [{'connector': <'eDP-1'>, 'min': <1200>, ...}, ...])
      bl=$(gdbus call "''${dc[@]}" --method org.freedesktop.DBus.Properties.Get \
        org.gnome.Mutter.DisplayConfig Backlight)
      serial=$(sed -E 's/^\(<\(uint32 ([0-9]+),.*/\1/' <<<"$bl")
      while read -r entry; do
        connector=$(sed -nE "s/.*'connector': <'([^']+)'>.*/\1/p" <<<"$entry")
        min=$(sed -nE "s/.*'min': <(-?[0-9]+)>.*/\1/p" <<<"$entry")
        [ -n "$connector" ] && [ -n "$min" ] || continue
        gdbus call "''${dc[@]}" --method org.gnome.Mutter.DisplayConfig.SetBacklight \
          "$serial" "$connector" "$min" >/dev/null
      done < <(grep -oE '\{[^}]*\}' <<<"$bl")

      # 2. Do Not Disturb.
      gsettings set org.gnome.desktop.notifications show-banners false

      # 3. Panel off; turn it back on at the first user input. Start listening
      # before adding the watch so the signal cannot be missed.
      coproc MON { exec gdbus monitor "''${im[@]}"; }
      read -r _ <&"''${MON[0]}"  # "Monitoring signals ..." banner = subscribed
      id=$(gdbus call "''${im[@]}" --method org.gnome.Mutter.IdleMonitor.AddUserActiveWatch \
        | grep -oE '[0-9]+' | tail -n1)
      gdbus call "''${dc[@]}" --method org.freedesktop.DBus.Properties.Set \
        org.gnome.Mutter.DisplayConfig PowerSaveMode "<int32 3>" >/dev/null
      while read -r line <&"''${MON[0]}"; do
        [[ $line == *"WatchFired (uint32 $id,)"* ]] && break
      done
      kill "$MON_PID" 2>/dev/null || true
      gdbus call "''${dc[@]}" --method org.freedesktop.DBus.Properties.Set \
        org.gnome.Mutter.DisplayConfig PowerSaveMode "<int32 0>" >/dev/null
    '';
  };
in
{
  config = lib.mkIf (config.desktop.environment == "gnome") {
    # Enable the GNOME Desktop Environment.
    services.desktopManager.gnome.enable = true;

    # Google Drive in Nautilus requires both of these.
    services.gnome.gnome-online-accounts.enable = true;
    services.gvfs.enable = true;

    # Session GDM autologin lands in ("gnome" = the Wayland session).
    services.displayManager.defaultSession = "gnome";

    # Prevent lock after unlock
    security.pam.services.gdm.enableGnomeKeyring = true;
    security.pam.services.gdm-password.enableGnomeKeyring = true;

    # gnome-keyring and gnome-settings-daemon come with the GNOME module.
    environment.systemPackages = [
      pkgs.lm_sensors
    ];

    environment.gnome.excludePackages = (with pkgs; [
      atomix # puzzle game
      cheese # webcam tool
      epiphany # web browser
      # evince # document viewer
      geary # email reader
      # gedit # text editor
      # gnome-characters
      # gnome-music
      # gnome-photos
      # gnome-terminal
      # gnome-console
      gnome-tour
      hitori # sudoku game
      iagno # go game
      tali # poker game
      totem # video player
    ]);

    # GSConnect
    networking.firewall = rec {
      allowedTCPPortRanges = [ { from = 1714; to = 1764; } ];
      allowedUDPPortRanges = allowedTCPPortRanges;
    };

    # User-level GNOME config; merges with the import of home.nix.
    home-manager.users.${config.local.user} = {
      home.packages = [
        pkgs.dconf2nix

        pkgs.gnomeExtensions.appindicator
        pkgs.gnomeExtensions.blur-my-shell
        pkgs.gnomeExtensions.gsconnect
        pkgs.gnomeExtensions.caffeine
        pkgs.gnomeExtensions.freon
        # Mutter's focus-stealing prevention intercepts kitty's remote-control
        # focus request (from claude-notifications-go's background daemon) and
        # shows a "kitty is ready" notification instead of actually focusing.
        # This extension disables that deferral so the click-to-focus request
        # goes through immediately.
        pkgs.gnomeExtensions.steal-my-focus-window

        screenSleep

        (pkgs.writeShellScriptBin "toggle-touchpad" ''
          current=$(gsettings get org.gnome.desktop.peripherals.touchpad send-events)
          if [ "$current" = "'disabled-on-external-mouse'" ]; then
            gsettings set org.gnome.desktop.peripherals.touchpad send-events enabled
            notify-send "Touchpad" "Always enabled" --icon=input-touchpad
          else
            gsettings set org.gnome.desktop.peripherals.touchpad send-events disabled-on-external-mouse
            notify-send "Touchpad" "Auto-disabled when mouse connected" --icon=input-touchpad
          fi
        '')
      ];

      dconf = {
        enable = true;
        settings."org/gnome/shell" = {
          disable-user-extensions = false;
          enabled-extensions = with pkgs.gnomeExtensions; [
            appindicator.extensionUuid
            blur-my-shell.extensionUuid
            gsconnect.extensionUuid
            caffeine.extensionUuid
            freon.extensionUuid
            steal-my-focus-window.extensionUuid
            # Local extension (symlinked by ~/Tools/gui selector/selector/install.sh).
            # Must be listed here: otherwise every rebuild resets it to disabled.
            "gui-selector@komatrich"
          ];
        };
        settings."org/gnome/desktop/peripherals/touchpad" = {
          send-events = "disabled-on-external-mouse";
        };
        # NumLock on in the session too, matching the initrd passphrase prompt
        # (see system/zfs.nix). GNOME's remember-numlock-state means this is
        # re-asserted at every login.
        settings."org/gnome/desktop/peripherals/keyboard" = {
          numlock-state = true;
        };
        settings."org/gnome/settings-daemon/plugins/media-keys" = {
          custom-keybindings = [
            "/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom0/"
          ];
        };
        settings."org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom0" = {
          name = "Toggle touchpad auto-disable";
          command = "toggle-touchpad";
          binding = "<Super>F6";
        };
      };

      # GSConnect Run Command entries (phone: KDE Connect -> Run command).
      # Declarative: commands added in the GSConnect GUI are reset on rebuild.
      # Wrapped in a module so `lib` is home-manager's (lib.hm.gvariant); the
      # dconf option rejects nixpkgs' lib.gvariant values.
      imports = [
        ({ lib, ... }: {
          dconf.settings."org/gnome/shell/extensions/gsconnect/device/${gsconnectPhone}/plugin/runcommand" =
            let
              inherit (lib.hm.gvariant) mkDictionaryEntry mkVariant;
              cmd = id: name: command: mkDictionaryEntry [ id (mkVariant [
                (mkDictionaryEntry [ "name" name ])
                (mkDictionaryEntry [ "command" command ])
              ]) ];
            in {
              command-list = [
                (cmd "screen-sleep" "Screen off (dim + DND)" (lib.getExe screenSleep))
              ];
            };
        })
      ];
    };
  };
}
