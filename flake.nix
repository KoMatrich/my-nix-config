# Install NIXOS
# =============
# Boot up live USB
# Move all files to /tmp
# Format disks:
# sudo nix --experimental-features "nix-command flakes" run github:nix-community/disko/latest -- --mode destroy,format,mount /tmp/disk-config.nix
# Regenerate config:
# nixos-generate-config --no-filesystems --root /mnt
# Copy files
# cp -r /tmp/nixos /mnt/etc/nixos
# Install
# sudo nixos-install --flake /mnt/etc/nixos#default

# Rebuild
# =======
# sudo nixos-rebuild switch --flake /etc/nixos#default

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

