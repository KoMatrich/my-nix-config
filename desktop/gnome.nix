# GNOME desktop environment.
# Import this file (and only this one) from configuration.nix to use GNOME.
# GDM, autologin, xkb layout and other desktop-agnostic settings stay in
# configuration.nix; this file carries everything GNOME-specific, including
# the home-manager parts for komatrich (merged with home.nix).

{ config, pkgs, ... }:

{
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

  environment.systemPackages = with pkgs; [
    pkgs.gnome-keyring
    pkgs.gnome-settings-daemon
    pkgs.lm_sensors
  ];

  environment.gnome.excludePackages = (with pkgs; [
    atomix # puzzle game
    cheese # webcam tool
    # epiphany # web browser
    # evince # document viewer
    geary # email reader
    # gedit # text editor
    # gnome-characters
    # gnome-music
    # gnome-photos
    # gnome-terminal
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
  home-manager.users.komatrich = {
    home.packages = [
      pkgs.dconf2nix

      pkgs.gnomeExtensions.appindicator
      pkgs.gnomeExtensions.blur-my-shell
      pkgs.gnomeExtensions.gsconnect
      pkgs.gnomeExtensions.caffeine
      pkgs.gnomeExtensions.freon

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
  };
}
