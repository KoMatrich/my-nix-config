{ config, lib, pkgs, ... }:
{
  # Prism Launcher (Minecraft). The nixpkgs build bundles JDK 8/17/21 and
  # picks the right one per instance, so no separate Java install is needed.
  # Instances, accounts and mods live in ~/.local/share/PrismLauncher, which
  # is on /home and therefore persisted.
  #
  # This machine runs NVIDIA PRIME offload, so Minecraft renders on the Intel
  # iGPU by default. For the dGPU: Prism -> instance -> Settings -> Custom
  # commands -> Wrapper command: `nvidia-offload`.
  environment.systemPackages = [
    pkgs.prismlauncher
  ];
}
