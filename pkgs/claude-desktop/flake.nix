# Claude Desktop (Anthropic's official Linux beta) repackaged for NixOS.
#
# Anthropic only ships a .deb via their apt repo; it is a prebuilt Electron app,
# so this unpacks it and patches the ELF binaries with autoPatchelfHook.
#
# Update: bump `version` + `hash` below (newest entry in
#   https://downloads.claude.ai/claude-desktop/apt/stable/dists/stable/main/binary-amd64/Packages
# -- the SHA256 listed there is hex; `nix hash convert --hash-algo sha256 --to sri <hex>`).
# The app does not self-update on Linux.
{
  description = "Claude Desktop (Anthropic .deb repackaged for NixOS)";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";

  outputs = { self, nixpkgs }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs { inherit system; config.allowUnfree = true; };

      claude-desktop = pkgs.callPackage ./package.nix { };
    in
    {
      packages.${system} = {
        inherit claude-desktop;
        default = claude-desktop;
      };

      # `pkgs.claude-desktop` in any config that applies this overlay.
      overlays.default = final: _prev: {
        claude-desktop = final.callPackage ./package.nix { };
      };
    };
}
