# Docs
# ====
# docs/INSTALL.md     - full (re)install runbook (disko, ZFS, blank snapshot)
# docs/DISK-LAYOUT.md - pools, datasets, what is wiped/persisted/replicated
# docs/RECOVERY.md    - disk failure & file restore procedures
# docs/CHEATSHEET.md  - daily commands and aliases (rebuild, update, fsdiff, ...)

{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    
    disko.url = "github:nix-community/disko";
    disko.inputs.nixpkgs.follows = "nixpkgs";
    
    home-manager.url = "github:nix-community/home-manager/release-26.05";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";
    
    impermanence.url = "github:nix-community/impermanence";

    # ComfyUI with CUDA support (uses pre-built PyTorch wheels).
    # Intentionally NOT following our nixpkgs: upstream pins nixos-unstable
    # and its CUDA packages are built/tested against that.
    comfyui-nix.url = "github:utensils/comfyui-nix";

    # Tracks upstream releases faster than nixpkgs.
    claude-code-nix.url = "github:sadjow/claude-code-nix";
  };

  outputs = {
    nixpkgs,
    home-manager,
    impermanence,
    disko,
    comfyui-nix,
    claude-code-nix,
    ...
    }:
    {
      # Named after networking.hostName so `nh os switch` / `nixos-rebuild
      # --flake /etc/nixos` resolve it automatically.
      nixosConfigurations."BLACK-BOX" = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          { nixpkgs.overlays = [ claude-code-nix.overlays.default ]; }
          disko.nixosModules.disko
          home-manager.nixosModules.home-manager
          impermanence.nixosModules.impermanence
          comfyui-nix.nixosModules.default
          ./configuration.nix
        ];
      };
    };
}

