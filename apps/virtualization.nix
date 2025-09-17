{ config, lib, pkgs, ... }:
{
  virtualisation.podman = {
    enable = true;
    dockerCompat = true;
  };

  environment.systemPackages = with pkgs; [
    pkgs.distrobox
  ];

  services.ollama = {
    enable = true;
    acceleration = "cuda";
    # loadModels = [ "deepseek-coder:6.7b" "mistral:7b" "qwen2.5-coder:1.5b"];
  };
}
