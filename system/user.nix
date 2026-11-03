# The one desktop user of this machine. Modules refer to config.local.user
# instead of repeating the name, so a rename is a one-line change here (plus
# `home-manager.users` in configuration.nix picking it up automatically).
{ lib, ... }:
{
  options.local.user = lib.mkOption {
    type = lib.types.str;
    default = "komatrich";
    description = "Login name of the single desktop user.";
  };
}
