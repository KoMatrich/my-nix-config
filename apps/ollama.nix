{ config, lib, pkgs, ... }:
{
  services.ollama = {
    enable = true;
    package = pkgs.ollama-cuda;

    loadModels = [
      "smtek/Qwen3.8-27B:IQ2_XXS"
    ];
  };

  # Don't autostart on boot; run `systemctl start ollama` (or `ollama serve`) when needed.
  systemd.services.ollama.wantedBy = lib.mkForce [ ];
}