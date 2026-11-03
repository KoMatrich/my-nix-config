# Stand-in for the real local-ci flake (git+file:///home/komatrich/Tools/local-ci),
# which only exists on BLACK-BOX itself. GitHub Actions and a from-scratch
# install from the live ISO cannot reach that path, so they evaluate with
#   --override-input local-ci path:./ci/local-ci-stub
# This stub accepts the services.local-ci settings home.nix uses and does
# nothing with them.
{
  description = "No-op stand-in for local-ci (CI / install only)";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";

  outputs = { nixpkgs, ... }: {
    homeModules.default = { lib, ... }: {
      options.services.local-ci = lib.mkOption {
        type = lib.types.attrsOf lib.types.anything;
        default = { };
        description = "Ignored: local-ci stub.";
      };
    };
  };
}
