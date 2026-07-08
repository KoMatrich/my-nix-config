{ config, lib, pkgs, ... }:
{
  # https://github.com/utensils/comfyui-nix
  # Module is imported in flake.nix (comfyui-nix.nixosModules.default);
  # it also injects its own overlay (comfy-ui, comfy-ui-cuda, ...).
  #
  # Web UI: http://127.0.0.1:8188
  # Data dir /var/lib/comfyui (outputs, custom nodes, workflows) is persisted
  # and replicated via apps/impermanence.nix. Models live on their own
  # zstorage dataset (big/slow SSD, not replicated - re-downloadable):
  # zstorage/comfyui-models -> /var/lib/comfyui/models (see disko-config.nix).
  services.comfyui = {
    enable = true;
    gpuSupport = "cuda";
    enableManager = true;

    port = 8188;
    listenAddress = "127.0.0.1";
    openFirewall = false;

    dataDir = "/var/lib/comfyui";
    # Don't start (and silently re-download models onto the NVMe) if the
    # models dataset isn't mounted, e.g. the SSD is dead (/games-style nofail).
    # Module wants a systemd mount unit name here, not a path
    # (systemd's path->unit escaping for /var/lib/comfyui/models).
    requiresMounts = [ "var-lib-comfyui-models.mount" ];
  };

  # The dataset root is created root-owned; hand it to the service user.
  systemd.tmpfiles.rules = [
    "z /var/lib/comfyui/models 0750 comfyui comfyui -"
  ];
}
