{ config, lib, pkgs, ... }:
{
  # https://github.com/utensils/comfyui-nix
  # Module is imported in flake.nix (comfyui-nix.nixosModules.default);
  # it also injects its own overlay (comfy-ui, comfy-ui-cuda, ...).
  #
  # Web UI: http://127.0.0.1:8188
  # Models go to /var/lib/comfyui/models (persisted, see apps/impermanence.nix).
  services.comfyui = {
    enable = true;
    gpuSupport = "cuda";
    enableManager = true;

    port = 8188;
    listenAddress = "127.0.0.1";
    openFirewall = false;

    dataDir = "/var/lib/comfyui";
  };
}
