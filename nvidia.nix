{ config, lib, pkgs, ... }:
{
  # Enable OpenGL
  hardware.graphics = {
    enable = true;
    # 32-bit Mesa drivers for the Intel iGPU path; without this, 32-bit
    # games that don't use PRIME offload fall back to llvmpipe (software).
    # NVIDIA's 32-bit libs are auto-included by the NVIDIA module.
    enable32Bit = true;
    extraPackages = [
      pkgs.intel-compute-runtime
      pkgs.level-zero
    ];
  };
  
  # Load nvidia driver for Xorg and Wayland
  services.xserver.videoDrivers = [
    "nvidia"
  ];
  
  # Dual GPU support
  services.switcherooControl.enable = true;

  hardware.nvidia = {
    # Modesetting is required.
    modesetting.enable = true;

    # Nvidia power management. Experimental, and can cause sleep/suspend to fail.
    # Enable this if you have graphical corruption issues or application crashes after waking
    # up from sleep. This fixes it by saving the entire VRAM memory to /tmp/ instead 
    # of just the bare essentials.
    powerManagement.enable = true;

    # Fine-grained power management. Turns off GPU when not in use.
    # Experimental and only works on modern Nvidia GPUs (Turing or newer).
    powerManagement.finegrained = true;

    # Use the NVidia open source kernel module (not to be confused with the
    # independent third-party "nouveau" open source driver).
    # Support is limited to the Turing and later architectures. Full list of 
    # supported GPUs is at: 
    # https://github.com/NVIDIA/open-gpu-kernel-modules#compatible-gpus 
    # Only available from driver 515.43.04+
    open = false;

    # Enable the Nvidia settings menu,
    # accessible via `nvidia-settings`.
    nvidiaSettings = true;

    # Optionally, you may need to select the appropriate driver version for your specific GPU.
    package = config.boot.kernelPackages.nvidiaPackages.stable;
    
    prime = {
      offload = {
        enable = true;
        enableOffloadCmd = true;
      };
      
      intelBusId = "PCI:0:2:0";
      nvidiaBusId = "PCI:1:0:0";
    };

  };

  # specialisation = {
  #   docked.configuration = {
  #     system.nixos.tags = [ "docked" ];
  #     hardware.nvidia = {
  #       prime.offload.enable = lib.mkForce false;
  #       prime.offload.enableOffloadCmd = lib.mkForce false;
  #       powerManagement.finegrained = lib.mkForce false;

  #       prime.sync.enable = lib.mkForce true;
  #     };
  #   };
  # };
}
