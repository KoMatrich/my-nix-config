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

  # Independent, non-blocking screen power commands for the phone. Mutter's
  # PowerSaveMode controls the panel without changing the backlight, so "on"
  # restores its previous brightness. No process or idle watch stays running.
  screenPower = pkgs.writeShellApplication {
    name = "screen-power";
    runtimeInputs = [ pkgs.glib pkgs.gnused ];
    text = ''
      dc=(--session --dest org.gnome.Mutter.DisplayConfig --object-path /org/gnome/Mutter/DisplayConfig)

      get_power_mode() {
        gdbus call "''${dc[@]}" --method org.freedesktop.DBus.Properties.Get \
          org.gnome.Mutter.DisplayConfig PowerSaveMode \
          | sed -nE 's/^\(<(int32 )?(-?[0-9]+)>,\)$/\2/p'
      }

      set_power_mode() {
        local requested=$1 actual
        gdbus call "''${dc[@]}" --method org.freedesktop.DBus.Properties.Set \
          org.gnome.Mutter.DisplayConfig PowerSaveMode "<int32 $requested>" >/dev/null
        actual=$(get_power_mode)
        if [ "$actual" != "$requested" ]; then
          printf 'screen-power: PowerSaveMode stayed at %s instead of %s\n' \
            "$actual" "$requested" >&2
          return 1
        fi
      }

      if [ "$#" -ne 1 ]; then
        printf 'Usage: %s {on|off}\n' "$0" >&2
        exit 2
      fi

      case "$1" in
        on)
          set_power_mode 0
          ;;
        off)
          if [ "$(get_power_mode)" = "-1" ]; then
            printf 'screen-power: panel power saving is unsupported\n' >&2
            exit 1
          fi

          set_power_mode 3
          ;;
        *)
          printf 'Usage: %s {on|off}\n' "$0" >&2
          exit 2
          ;;
      esac
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

        screenPower

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
                (cmd "screen-off" "Screen off" "${lib.getExe screenPower} off")
                (cmd "screen-on" "Screen on" "${lib.getExe screenPower} on")
                (cmd "session-lock" "Lock"
                  "${pkgs.systemd}/bin/loginctl lock-session")
                (cmd "session-unlock" "Unlock"
                  "${pkgs.systemd}/bin/loginctl unlock-session")
                (cmd "power-performance" "Power: performance"
                  "${pkgs.power-profiles-daemon}/bin/powerprofilesctl set performance")
                (cmd "power-saver" "Power: power saver"
                  "${pkgs.power-profiles-daemon}/bin/powerprofilesctl set power-saver")
                (cmd "system-sleep" "Sleep"
                  "${pkgs.systemd}/bin/systemctl suspend")
                (cmd "system-restart" "Restart"
                  "${pkgs.systemd}/bin/systemctl reboot")
                (cmd "system-shutdown" "Shut down"
                  "${pkgs.systemd}/bin/systemctl poweroff")
              ];
            };
        })
      ];
    };
  };
}
