# Hyprland desktop environment (full starter setup).
# Import this file (and only this one) from configuration.nix to use Hyprland.
# GDM, autologin, xkb layout and other desktop-agnostic settings stay in
# configuration.nix; this file carries everything Hyprland-specific, including
# the home-manager parts for komatrich (merged with home.nix).
#
# Companion apps (Hyprland has no built-in bar/launcher/notifications):
#   waybar    - status bar, styled like GNOME's top bar (systemd user service)
#   wofi      - application launcher
#   mako      - notification daemon (D-Bus activated)
#   kitty     - terminal
#   hyprpaper - wallpaper
#   hyprlock  - screen locker
#   hypridle  - idle daemon (lock -> screen off -> suspend)
#   nm-applet - NetworkManager tray icon
#   grim/slurp            - screenshots
#   wl-clipboard/cliphist - clipboard + history
#
# Look: GNOME-like dark Adwaita (adw-gtk3-dark, Adwaita icons/cursor,
# Cantarell font, Adwaita-blue #3584e4 accent) with subtle animations,
# small rounding and no blur/transparency.

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

  # Unlock the keyring on login; same wiring gnome.nix has.
  security.pam.services.gdm.enableGnomeKeyring = true;
  security.pam.services.gdm-password.enableGnomeKeyring = true;

  # hyprlock authenticates via PAM; without this entry unlocking always fails.
  # Deliberately NOT programs.hyprlock.enable: that would force-enable a
  # second, NixOS-level hypridle service fighting the home-manager one below.
  security.pam.services.hyprlock = { };

  # dconf backend for the gtk/colorScheme settings below (GNOME did this
  # implicitly).
  programs.dconf.enable = true;

  # Fonts for the bar, terminal and GTK apps (GNOME ships its own set).
  fonts.packages = [
    pkgs.cantarell-fonts            # GNOME UI font (waybar, GTK, wofi, mako)
    pkgs.nerd-fonts.jetbrains-mono  # terminal / monospace
    pkgs.nerd-fonts.symbols-only    # "Symbols Nerd Font" icon glyphs for waybar
    pkgs.noto-fonts                 # broad fallback
    pkgs.noto-fonts-color-emoji     # emoji fallback
  ];

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
  home-manager.users.komatrich =
    let
      wallpaper = pkgs.nixos-artwork.wallpapers.simple-dark-gray.gnomeFilePath;
    in
    {
      home.packages = [
        pkgs.grim           # screenshot (whole output / region)
        pkgs.slurp          # region selector for grim
        pkgs.wl-clipboard   # wl-copy / wl-paste
        pkgs.cliphist       # clipboard history
        pkgs.brightnessctl  # backlight control keys
        pkgs.polkit_gnome   # graphical polkit auth agent
        pkgs.pavucontrol    # volume mixer (waybar right-click)
      ];

      # GNOME-like dark theming: adw-gtk3 ports the libadwaita look to GTK3.
      home.pointerCursor = {
        package = pkgs.adwaita-icon-theme;  # ships the Adwaita cursor theme
        name = "Adwaita";
        size = 24;
        gtk.enable = true;
        hyprcursor.enable = true;  # falls back to XCursor at runtime
      };

      gtk = {
        enable = true;
        theme = {
          name = "adw-gtk3-dark";
          package = pkgs.adw-gtk3;
        };
        iconTheme = {
          name = "Adwaita";
          package = pkgs.adwaita-icon-theme;
        };
        font = {
          name = "Cantarell";
          size = 11;
          package = pkgs.cantarell-fonts;
        };
        # Also sets dconf org/gnome/desktop/interface color-scheme=prefer-dark
        # so libadwaita apps follow the dark theme.
        colorScheme = "dark";
      };

      qt = {
        enable = true;
        platformTheme.name = "adwaita";  # GNOME-like decorations for Qt apps
        style.name = "adwaita-dark";     # pulls in adwaita-qt + adwaita-qt6
      };

      programs.kitty = {
        enable = true;
        font = {
          name = "JetBrainsMono Nerd Font";
          size = 11;
          package = pkgs.nerd-fonts.jetbrains-mono;
        };
        themeFile = "adwaita_dark";
        settings = {
          window_padding_width = 8;
          scrollback_lines = 10000;
          enable_audio_bell = false;
          confirm_os_window_close = 0;
        };
      };

      programs.wofi = {
        enable = true;
        settings = {
          show = "drun";
          width = 600;
          height = 350;
          location = "center";
          prompt = "Search…";
          allow_images = true;
          insensitive = true;
          hide_scroll = true;
        };
        style = ''
          window {
            background-color: #1c1c28;
            border: 1px solid #3584e4;
            border-radius: 12px;
            font-family: "Cantarell";
            font-size: 11pt;
            color: #e6e6e6;
          }
          #input {
            margin: 8px;
            border-radius: 8px;
            border: none;
            background-color: #2a2a38;
            color: #e6e6e6;
          }
          #entry {
            padding: 6px;
            border-radius: 8px;
          }
          #entry:selected {
            background-color: #3584e4;
            color: #ffffff;
          }
        '';
      };

      # Notification daemon; started on demand via D-Bus.
      services.mako = {
        enable = true;
        settings = {
          font = "Cantarell 11";
          background-color = "#242430f0";
          text-color = "#e6e6e6";
          border-color = "#3584e4";
          border-size = 1;
          border-radius = 12;
          default-timeout = 5000;
          max-visible = 5;
          anchor = "top-right";
          margin = "8";
          padding = "12";
          icons = true;
          max-icon-size = 48;
        };
      };

      # dbus-broker refuses to D-Bus-activate mako (its service file
      # fr.emersion.mako.service is not named after org.freedesktop.
      # Notifications), so start it explicitly with the session.
      systemd.user.services.mako = {
        Unit = {
          Description = "Mako notification daemon";
          PartOf = [ "graphical-session.target" ];
          After = [ "graphical-session.target" ];
        };
        Service = {
          Type = "dbus";
          BusName = "org.freedesktop.Notifications";
          ExecStart = "${pkgs.mako}/bin/mako";
          Restart = "on-failure";
        };
        Install.WantedBy = [ "graphical-session.target" ];
      };

      programs.waybar = {
        enable = true;
        # Start via graphical-session.target instead of exec-once so it gets
        # restarted automatically if it crashes.
        systemd.enable = true;
        # GNOME top bar layout: workspaces left, clock center, system
        # indicators right.
        settings.mainBar = {
          layer = "top";
          position = "top";
          height = 34;
          spacing = 4;
          modules-left = [ "hyprland/workspaces" ];
          modules-center = [ "clock" ];
          modules-right = [ "tray" "wireplumber" "network" "battery" ];

          "hyprland/workspaces" = {
            format = "{id}";
            on-click = "activate";
            # Always show workspaces 1-3, like GNOME's static workspaces.
            persistent-workspaces."*" = 3;
          };
          clock = {
            format = "{:%a %b %d  %H:%M}";
            tooltip-format = "<tt><small>{calendar}</small></tt>";
            calendar.format.today = "<span color='#3584e4'><b>{}</b></span>";
          };
          tray = {
            spacing = 8;
            icon-size = 16;
          };
          wireplumber = {
            format = "{icon} {volume}%";
            format-muted = "󰝟";
            format-icons = [ "󰕿" "󰖀" "󰕾" ];
            on-click = "wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle";
            on-click-right = "pavucontrol";
            scroll-step = 5;
          };
          network = {
            format-wifi = "{icon}";
            format-icons = [ "󰤯" "󰤟" "󰤢" "󰤥" "󰤨" ];
            format-ethernet = "󰈀";
            format-disconnected = "󰤭";
            tooltip-format-wifi = "{essid} ({signalStrength}%)";
            tooltip-format-ethernet = "{ifname} {ipaddr}";
          };
          battery = {
            format = "{icon} {capacity}%";
            format-charging = "󰂄 {capacity}%";
            format-icons = [ "󰁺" "󰁻" "󰁼" "󰁽" "󰁾" "󰁿" "󰂀" "󰂁" "󰂂" "󰁹" ];
            states = {
              warning = 30;
              critical = 15;
            };
          };
        };
        # Solid dark full-width bar with GNOME-shell-like pill highlights.
        style = ''
          * {
            font-family: "Cantarell", "Symbols Nerd Font";
            font-size: 11pt;
            min-height: 0;
          }
          window#waybar {
            background: #1c1c28;
            color: #e6e6e6;
          }
          #workspaces button {
            padding: 0 10px;
            margin: 4px 2px;
            border-radius: 999px;
            color: #9a9aa5;
            background: transparent;
            transition: background-color 150ms ease;
          }
          #workspaces button:hover {
            background: rgba(255, 255, 255, 0.08);
          }
          #workspaces button.active {
            color: #ffffff;
            background: rgba(255, 255, 255, 0.14);
          }
          #clock {
            font-weight: bold;
          }
          #tray, #wireplumber, #network, #battery {
            padding: 0 10px;
            margin: 4px 0;
          }
          #battery.critical:not(.charging) {
            color: #e01b24;
          }
        '';
      };

      services.hyprpaper = {
        enable = true;
        # hyprpaper 0.8 format: no more preload, wallpaper is a block.
        settings = {
          splash = false;
          wallpaper = {
            monitor = "";  # all monitors
            path = wallpaper;
            fit_mode = "cover";
          };
        };
      };

      # Needs security.pam.services.hyprlock above to accept the password.
      programs.hyprlock = {
        enable = true;
        settings = {
          general = {
            hide_cursor = true;
            ignore_empty_input = true;
          };
          # Solid dark background; deliberately no blur/screenshot.
          background = [
            {
              monitor = "";
              path = "";
              color = "rgb(1c1c28)";
            }
          ];
          label = [
            {
              monitor = "";
              text = "$TIME";
              font_family = "Cantarell";
              font_size = 72;
              color = "rgb(e6e6e6)";
              position = "0, 160";
              halign = "center";
              valign = "center";
            }
          ];
          input-field = [
            {
              monitor = "";
              size = "280, 48";
              rounding = 12;
              outline_thickness = 2;
              outer_color = "rgb(3584e4)";
              inner_color = "rgb(2a2a38)";
              font_color = "rgb(e6e6e6)";
              placeholder_text = "Password";
              fade_on_empty = false;
              position = "0, -40";
              halign = "center";
              valign = "center";
            }
          ];
        };
      };

      services.hypridle = {
        enable = true;
        settings = {
          general = {
            lock_cmd = "pidof hyprlock || hyprlock";  # no double instances
            before_sleep_cmd = "loginctl lock-session";
            after_sleep_cmd = "hyprctl dispatch dpms on";
          };
          listener = [
            {
              # 5 min: lock
              timeout = 300;
              on-timeout = "loginctl lock-session";
            }
            {
              # 8 min: screen off
              timeout = 480;
              on-timeout = "hyprctl dispatch dpms off";
              on-resume = "hyprctl dispatch dpms on";
            }
            {
              # 25 min: suspend
              timeout = 1500;
              on-timeout = "systemctl suspend";
            }
          ];
        };
      };

      # Wifi icon in the tray.
      services.network-manager-applet.enable = true;
      # MPRIS daemon so the media keys control the last active player.
      services.playerctld.enable = true;

      wayland.windowManager.hyprland = {
        enable = true;
        # Use the Hyprland package installed by programs.hyprland above;
        # home-manager only manages the configuration.
        package = null;
        portalPackage = null;

        # Import the whole session environment (incl. PATH) into systemd/D-Bus
        # so waybar on-click commands, hypridle's lock_cmd etc. resolve.
        systemd.variables = [ "--all" ];

        settings = {
          "$mod" = "SUPER";

          # Every monitor at its preferred resolution, auto-placed, scale 1.
          monitor = ",preferred,auto,1";

          env = [
            "XCURSOR_THEME,Adwaita"
            "XCURSOR_SIZE,24"
            "QT_WAYLAND_DISABLE_WINDOWDECORATION,1"
          ];

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
            "col.active_border" = "rgb(3584e4)";    # Adwaita blue
            "col.inactive_border" = "rgb(3a3a46)";
          };

          decoration = {
            rounding = 8;
            blur.enabled = false;  # deliberate: no blur/transparency
            shadow = {
              enabled = true;
              range = 12;
              render_power = 2;
              color = "rgba(00000055)";
            };
          };

          # Short, GNOME-like restrained animations (speed is in 100ms units).
          animations = {
            enabled = true;
            bezier = [ "easeOut, 0.25, 1, 0.5, 1" ];
            animation = [
              "windows, 1, 2, easeOut, popin 90%"
              "windowsOut, 1, 2, easeOut, popin 90%"
              "fade, 1, 2, default"
              "border, 1, 3, default"
              "workspaces, 1, 3, easeOut, slide"
            ];
          };

          misc = {
            disable_hyprland_logo = true;
            disable_splash_rendering = true;
            force_default_wallpaper = 0;
          };

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

            # Lock (hypridle relays loginctl lock to hyprlock)
            "$mod, L, exec, loginctl lock-session"

            # Window management
            "$mod, Q, killactive"
            "$mod, M, exit"
            "$mod, F, fullscreen"
            "$mod SHIFT, Space, togglefloating"
            "$mod, left, movefocus, l"
            "$mod, right, movefocus, r"
            "$mod, up, movefocus, u"
            "$mod, down, movefocus, d"
            "$mod SHIFT, left, movewindow, l"
            "$mod SHIFT, right, movewindow, r"
            "$mod SHIFT, up, movewindow, u"
            "$mod SHIFT, down, movewindow, d"
            "$mod CTRL, left, resizeactive, -40 0"
            "$mod CTRL, right, resizeactive, 40 0"
            "$mod CTRL, up, resizeactive, 0 -40"
            "$mod CTRL, down, resizeactive, 0 40"
            "ALT, Tab, cyclenext"
            "ALT, Tab, bringactivetotop"

            # Screenshots
            # Region to clipboard
            ", Print, exec, grim -g \"$(slurp)\" - | wl-copy"
            # Full screen to ~/Pictures
            "SHIFT, Print, exec, grim ~/Pictures/screenshot-$(date +%Y%m%d-%H%M%S).png"

            # Workspaces (below, via keycodes)
            "$mod, mouse_down, workspace, e+1"
            "$mod, mouse_up, workspace, e-1"
          ]
          # Workspace switching by keycode (code:10-18 = number row 1-9):
          # on the cz layout the unshifted number row emits +ěščřžýáíé, so
          # keysym binds like "$mod, 1" would never match.
          ++ builtins.concatLists (builtins.genList (i:
            let
              ws = toString (i + 1);
              key = "code:${toString (i + 10)}";
            in [
              "$mod, ${key}, workspace, ${ws}"
              "$mod SHIFT, ${key}, movetoworkspace, ${ws}"
            ]) 9);

          # Drag windows with the mouse (272 = left button, 273 = right).
          bindm = [
            "$mod, mouse:272, movewindow"
            "$mod, mouse:273, resizewindow"
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
            ", XF86AudioMicMute, exec, wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle"
            ", XF86AudioPlay, exec, playerctl play-pause"
            ", XF86AudioNext, exec, playerctl next"
            ", XF86AudioPrev, exec, playerctl previous"
          ];
        };
      };
    };
}
