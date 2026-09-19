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

    # llama.cpp with DSpark speculative decoding (--spec-type draft-dspark,
    # llama.cpp PR #25173, merged 2026-07-28). nixos-26.05 ships b9190
    # (2026-05-16), which predates both DFlash and DSpark. Pinned to the exact
    # rev whose CUDA build is in cache.nixos-cuda.org -- bumping it is fine,
    # but check the cache first or you are in for a local CUDA compile.
    # Deliberately NOT following our nixpkgs: the newer llama.cpp is the point.
    nixpkgs-llama.url = "github:NixOS/nixpkgs/ef34387ddd751e1ab8857adf4676492d32eb24ec";

    # Push-to-talk Whisper dictation, autostarted as a user service.
    # git+file rather than path so .venv/build artefacts stay out of the store;
    # main.py must be committed for a rebuild to pick it up. The follows is
    # required - a second nixpkgs would mean a second CUDA CTranslate2 build.
    voice2text.url = "git+file:///home/komatrich/Tools/voice2text";
    voice2text.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = {
    nixpkgs,
    nixpkgs-llama,
    home-manager,
    impermanence,
    disko,
    comfyui-nix,
    claude-code-nix,
    voice2text,
    ...
    }:
    {
      # Named after networking.hostName so `nh os switch` / `nixos-rebuild
      # --flake /etc/nixos` resolve it automatically.
      nixosConfigurations."BLACK-BOX" = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        specialArgs = { inherit nixpkgs-llama; };
        modules = [
          { nixpkgs.overlays = [ claude-code-nix.overlays.default ]; }
          disko.nixosModules.disko
          home-manager.nixosModules.home-manager
          impermanence.nixosModules.impermanence
          comfyui-nix.nixosModules.default
          # home.nix is imported by configuration.nix, which has no flake
          # inputs in scope; hand voice2text through to it.
          { home-manager.extraSpecialArgs = { inherit voice2text; }; }
          ./configuration.nix
        ];
      };
    };
}

