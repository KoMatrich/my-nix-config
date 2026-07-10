# Hyprland desktop environment (full starter setup).
# Import this file (and only this one) from configuration.nix to use Hyprland.
# GDM, autologin, xkb layout and other desktop-agnostic settings stay in
# configuration.nix; this file carries everything Hyprland-specific, including
# the home-manager parts for komatrich (merged with home.nix).
#
# Companion apps (Hyprland has no built-in bar/launcher/notifications):
#   waybar  - status bar (runs as a systemd user service)
#   wofi    - application launcher
#   mako    - notification daemon (D-Bus activated)
#   kitty   - terminal
#   grim/slurp        - screenshots
#   wl-clipboard/cliphist - clipboard + history

{ config, pkgs, ... }:

{
  # Installs Hyprland, registers the "hyprland" session with GDM and pulls in
  # xdg-desktop-portal-hyprland. XWayland is enabled by default.
  programs.hyprland.enable = true;

  # Session GDM autologin lands in.
  services.displayManager.defaultSession = "hyprland";

  # Run Electron/Chromium apps natively on Wayland.
  environment.sessionVariables.NIXOS_OZONE_WL = "1";

  # The hyprland portal lacks FileChooser etc.; the GTK portal fills the gaps.
  xdg.portal.extraPortals = [ pkgs.xdg-desktop-portal-gtk ];

  # Secret storage for apps. GNOME enables this implicitly; Hyprland must ask.
  services.gnome.gnome-keyring.enable = true;

  # Aggressive NVIDIA env vars. Do NOT enable while on PRIME offload (the
  # default), where the Intel iGPU renders the desktop - these would force
  # everything onto the NVIDIA GPU and break offload. Only consider them when
  # running the "docked" specialisation (prime.sync, NVIDIA primary).
  # environment.sessionVariables = {
  #   GBM_BACKEND = "nvidia-drm";
  #   __GLX_VENDOR_LIBRARY_NAME = "nvidia";
  #   LIBVA_DRIVER_NAME = "nvidia";
  # };

  # User-level Hyprland config; merges with the import of home.nix.
  home-manager.users.komatrich = {
    home.packages = [
      pkgs.grim           # screenshot (whole output / region)
      pkgs.slurp          # region selector for grim
      pkgs.wl-clipboard   # wl-copy / wl-paste
      pkgs.cliphist       # clipboard history
      pkgs.brightnessctl  # backlight control keys
      pkgs.polkit_gnome   # graphical polkit auth agent
    ];

    programs.kitty.enable = true;
    programs.wofi.enable = true;

    # Notification daemon; started on demand via D-Bus.
    services.mako.enable = true;

    programs.waybar = {
      enable = true;
      # Start via graphical-session.target instead of exec-once so it gets
      # restarted automatically if it crashes.
      systemd.enable = true;
      settings.mainBar = {
        layer = "top";
        position = "top";
        height = 30;
        modules-left = [ "hyprland/workspaces" ];
        modules-center = [ "hyprland/window" ];
        modules-right = [ "tray" "wireplumber" "network" "battery" "clock" ];

        "hyprland/window".max-length = 60;
        tray.spacing = 8;
        wireplumber = {
          format = "vol {volume}%";
          format-muted = "muted";
          on-click = "wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle";
        };
        network = {
          format-wifi = "wifi {signalStrength}%";
          format-ethernet = "eth";
          format-disconnected = "offline";
        };
        battery = {
          format = "bat {capacity}%";
          format-charging = "chr {capacity}%";
          states = { warning = 30; critical = 15; };
        };
        clock.format = "{:%a %d.%m. %H:%M}";
      };
    };

    wayland.windowManager.hyprland = {
      enable = true;
      # Use the Hyprland package installed by programs.hyprland above;
      # home-manager only manages the configuration.
      package = null;
      portalPackage = null;

      settings = {
        "$mod" = "SUPER";

        # Every monitor at its preferred resolution, auto-placed, scale 1.
        monitor = ",preferred,auto,1";

        input = {
          # xkb settings in configuration.nix only apply to X11/GNOME;
          # Hyprland needs its own copy of the layout.
          kb_layout = "cz";
          kb_variant = "qwerty";
          touchpad.natural_scroll = true;
        };

        # NVIDIA cursor glitch fix; harmless on Intel.
        cursor.no_hardware_cursors = true;

        general = {
          gaps_in = 4;
          gaps_out = 8;
          border_size = 2;
        };
        decoration.rounding = 6;

        exec-once = [
          # Clipboard history collection.
          "wl-paste --type text --watch cliphist store"
          "wl-paste --type image --watch cliphist store"
          # Graphical auth prompts (e.g. when an app needs root).
          "${pkgs.polkit_gnome}/libexec/polkit-gnome-authentication-agent-1"
        ];

        bind = [
          # Apps
          "$mod, Return, exec, kitty"
          "$mod, D, exec, wofi --show drun"
          "$mod, V, exec, cliphist list | wofi --dmenu | cliphist decode | wl-copy"

          # Window management
          "$mod, Q, killactive"
          "$mod, M, exit"
          "$mod, F, fullscreen"
          "$mod SHIFT, Space, togglefloating"
          "$mod, left, movefocus, l"
          "$mod, right, movefocus, r"
          "$mod, up, movefocus, u"
          "$mod, down, movefocus, d"

          # Screenshots
          # Region to clipboard
          ", Print, exec, grim -g \"$(slurp)\" - | wl-copy"
          # Full screen to ~/Pictures
          "SHIFT, Print, exec, grim ~/Pictures/screenshot-$(date +%Y%m%d-%H%M%S).png"

          # Workspaces
          "$mod, 1, workspace, 1"
          "$mod, 2, workspace, 2"
          "$mod, 3, workspace, 3"
          "$mod, 4, workspace, 4"
          "$mod, 5, workspace, 5"
          "$mod, 6, workspace, 6"
          "$mod, 7, workspace, 7"
          "$mod, 8, workspace, 8"
          "$mod, 9, workspace, 9"
          "$mod SHIFT, 1, movetoworkspace, 1"
          "$mod SHIFT, 2, movetoworkspace, 2"
          "$mod SHIFT, 3, movetoworkspace, 3"
          "$mod SHIFT, 4, movetoworkspace, 4"
          "$mod SHIFT, 5, movetoworkspace, 5"
          "$mod SHIFT, 6, movetoworkspace, 6"
          "$mod SHIFT, 7, movetoworkspace, 7"
          "$mod SHIFT, 8, movetoworkspace, 8"
          "$mod SHIFT, 9, movetoworkspace, 9"
        ];

        # Repeat while held (volume/brightness).
        bindel = [
          ", XF86AudioRaiseVolume, exec, wpctl set-volume -l 1.0 @DEFAULT_AUDIO_SINK@ 5%+"
          ", XF86AudioLowerVolume, exec, wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-"
          ", XF86MonBrightnessUp, exec, brightnessctl set 5%+"
          ", XF86MonBrightnessDown, exec, brightnessctl set 5%-"
        ];
        # Work even when the screen is locked.
        bindl = [
          ", XF86AudioMute, exec, wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"
        ];
      };
    };

    # Possible follow-ups:
    # programs.hyprlock.enable = true;   # screen locker
    # services.hypridle.enable = true;   # idle daemon (lock/dpms timeouts)
    # services.hyprpaper.enable = true;  # wallpaper
  };
}
