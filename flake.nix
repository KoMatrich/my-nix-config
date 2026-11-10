# Docs
# ====
# docs/INSTALL.md     - full (re)install runbook (disko, ZFS, blank snapshot)
# docs/DISK-LAYOUT.md - pools, datasets, what is wiped/persisted/replicated
# docs/RECOVERY.md    - disk failure & file restore procedures
# docs/CHEATSHEET.md  - daily commands and aliases (rebuild, update, fsdiff, ...)
# docs/DEVBOX.md      - sandbox for npm / untrusted builds / Claude YOLO mode

{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    
    disko.url = "github:nix-community/disko";
    disko.inputs.nixpkgs.follows = "nixpkgs";
    
    home-manager.url = "github:nix-community/home-manager/release-26.05";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";
    
    # impermanence's own nixpkgs/home-manager inputs are only used by its
    # tests; follow ours so the lock does not carry two more nixpkgs copies.
    impermanence.url = "github:nix-community/impermanence";
    impermanence.inputs.nixpkgs.follows = "nixpkgs";
    impermanence.inputs.home-manager.follows = "home-manager";

    # Tracks upstream releases faster than nixpkgs. Deliberately NOT following
    # our nixpkgs: its overlay builds against our package set anyway, and the
    # unfollowed lock entry is only what upstream tests/caches against.
    claude-code-nix.url = "github:sadjow/claude-code-nix";

    # llama.cpp with DSpark speculative decoding (--spec-type draft-dspark,
    # llama.cpp PR #25173, merged 2026-07-28). nixos-26.05 ships b9190
    # (2026-05-16), which predates both DFlash and DSpark. Pinned to the exact
    # rev whose CUDA build is in cache.nixos-cuda.org -- bumping it is fine,
    # but check the cache first or you are in for a local CUDA compile.
    # Deliberately NOT following our nixpkgs: the newer llama.cpp is the point.
    nixpkgs-llama.url = "github:NixOS/nixpkgs/ef34387ddd751e1ab8857adf4676492d32eb24ec";

    # On-demand CI from this PC: `local-ci build` (images to ghcr.io) and
    # `local-ci test` (tests for pull requests), as user timers that ask before
    # running.
    # git+file, so changes must be committed there and then picked up with
    # `nix flake update local-ci`.
    # That path only exists on BLACK-BOX: GitHub Actions and a from-scratch
    # install evaluate with `--override-input local-ci path:./ci/local-ci-stub`
    # instead (see .github/workflows/check.yml and docs/INSTALL.md).
    local-ci.url = "git+file:///home/komatrich/Tools/local-ci";
    local-ci.inputs.nixpkgs.follows = "nixpkgs";

    # Herdr — agent runtime / terminal workspace manager (https://herdr.dev).
    # Builds from source (Rust), so it deliberately does NOT follow our
    # nixpkgs: upstream pins nixos-unstable plus the rust-overlay toolchain it
    # is tested against. Exposes an overlay (applied in outputs below) and is
    # installed as pkgs.herdr in home.nix. Bump by editing the tag here.
    herdr.url = "github:herdrdev/herdr/v0.9.5";

    # T3 Code (t3.codes) -- our fork of clementpoiret/t3code-flake, which wraps
    # the official release AppImage and bumps itself daily. Applied as an
    # overlay below and installed as pkgs.t3code-desktop in home.nix. Following
    # our nixpkgs is safe: the overlay builds against the system package set.
    # Pick up a new T3 Code release with `nix flake update t3code`.
    t3code.url = "github:KoMatrich/t3code-flake";
    t3code.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = {
    nixpkgs,
    nixpkgs-llama,
    home-manager,
    impermanence,
    disko,
    claude-code-nix,
    local-ci,
    herdr,
    t3code,
    ...
    }:
    let
      system = "x86_64-linux";
    in
    {
      # Named after networking.hostName so `nh os switch` / `nixos-rebuild
      # --flake /etc/nixos` resolve it automatically.
      nixosConfigurations."BLACK-BOX" = nixpkgs.lib.nixosSystem {
        specialArgs = { inherit nixpkgs-llama; };
        modules = [
          {
            nixpkgs.overlays = [
              claude-code-nix.overlays.default
              herdr.overlays.default
              t3code.overlays.default
              # Claude Desktop (Anthropic's Linux beta, only shipped as a .deb),
              # repackaged in-repo; update procedure in its package.nix.
              (final: _prev: { claude-desktop = final.callPackage ./pkgs/claude-desktop/package.nix { }; })
            ];
          }
          disko.nixosModules.disko
          home-manager.nixosModules.home-manager
          impermanence.nixosModules.impermanence
          # home.nix is imported by configuration.nix, which has no flake
          # inputs in scope; hand local-ci through to it.
          { home-manager.extraSpecialArgs = { inherit local-ci; }; }
          ./configuration.nix
        ];
      };

      # `nix fmt <file>` (RFC 166 style). Not run over the whole repo yet, to
      # keep history readable; format files as you touch them.
      formatter.${system} = nixpkgs.legacyPackages.${system}.nixfmt;
    };
}

