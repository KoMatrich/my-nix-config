# Docs
# ====
# docs/INSTALL.md     - full (re)install runbook (disko, ZFS, blank snapshot)
# docs/DISK-LAYOUT.md - pools, datasets, what is wiped/persisted/replicated
# docs/RECOVERY.md    - disk failure & file restore procedures
# docs/CHEATSHEET.md  - daily commands and aliases (rebuild, update, fsdiff, ...)

{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";
    
    disko.url = "github:nix-community/disko";
    disko.inputs.nixpkgs.follows = "nixpkgs";
    
    home-manager.url = "github:nix-community/home-manager/release-25.05";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";
    
    impermanence.url = "github:nix-community/impermanence";
  };
  
  outputs = {
    nixpkgs,
    home-manager,
    impermanence,
    disko,
    ...
    }:
    {
      nixosConfigurations.default = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          disko.nixosModules.disko
          home-manager.nixosModules.home-manager
          impermanence.nixosModules.impermanence
          ./configuration.nix
        ];
      };
    };
}

