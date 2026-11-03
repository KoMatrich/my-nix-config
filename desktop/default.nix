# Desktop environment selection.
#
# Both desktops are always imported (so `nix flake check` evaluates both and
# neither can silently rot); `desktop.environment` decides which one is
# actually active. GNOME is the default system; Hyprland is a specialisation,
# i.e. a second boot entry ("hyprland") built from the same config:
#   - pick it in the boot menu (hold Space at power-on; timeout is 0), or
#   - switch the running system: `sudo /run/current-system/specialisation/hyprland/bin/switch-to-configuration switch`
#     (log out/in afterwards; `rebuild` returns to GNOME).
# GDM, autologin, xkb layout and other desktop-agnostic settings stay in
# configuration.nix.
{ config, lib, ... }:
{
  imports = [
    ./gnome.nix
    ./hyprland.nix
  ];

  options.desktop.environment = lib.mkOption {
    type = lib.types.enum [ "gnome" "hyprland" ];
    default = "gnome";
    description = "Which desktop environment this system (or specialisation) runs.";
  };

  config.specialisation.hyprland.configuration = {
    system.nixos.tags = [ "hyprland" ];
    desktop.environment = lib.mkForce "hyprland";
  };
}
