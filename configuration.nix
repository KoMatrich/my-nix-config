# Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running ‘nixos-help’).

{ config, lib, pkgs, ... }:

{
  imports =
    [ # Include the results of the hardware scan.
      ./hardware-configuration.nix
      ./disko-config.nix
      ./nvidia.nix
      ./apps/nvidia-open-test.nix # "nvidia-open" boot entry + gpu-driver-test
      ./system/user.nix
      ./system/notify.nix       # desktop alerts: failed backups, ZFS/SMART faults
      ./system/zfs.nix
      ./system/replication.nix
      ./system/usb-backup.nix   # offline backup to the USB HDD on plug-in
      ./system/shell.nix
      ./system/zerotier.nix
      ./system/firewall.nix
      ./system/power.nix
      ./system/sleep.nix        # lid handling + "do not suspend while busy"
      ./apps/impermanence.nix
      ./apps/virtualization.nix
      ./apps/devbox.nix         # `devbox` / `yolo`: sandbox for npm + Claude YOLO mode
      ./apps/steam.nix
      ./apps/heroic.nix
      ./apps/prismlauncher.nix
      ./apps/devshells.nix
      ./apps/owon-vds1022.nix
      ./apps/gnome-network-displays.nix
      ./apps/godot.nix
      ./apps/quest.nix          # Meta Quest dev: adb + WiVRn streaming
      ./apps/tailscale.nix
      ./apps/iphone.nix         # iPhone USB access + `iphone-backup` (USB/Wi-Fi)
      ./apps/llm.nix

      # GNOME by default; Hyprland as a boot-menu specialisation.
      ./desktop
    ];

  # Bootloader.
  boot.loader.systemd-boot.enable = true;
  # The ESP is 1 GiB and every NVIDIA kernel + initrd pair is large; without a
  # cap, a burst of rebuilds inside nh's 7-day window can fill /boot and make
  # a switch fail half-way. Older generations stay in the store until `gc`.
  boot.loader.systemd-boot.configurationLimit = 10;
  boot.loader.efi.canTouchEfiVariables = true;
  # Skip the boot menu; hold Space during firmware handoff to get it back
  # (e.g. to select an older generation, or the hyprland / nvidia-open
  # specialisations).
  boot.loader.timeout = 0;

  services.fwupd.enable = true;

  # Compressed swap in RAM; no disk swap, no hibernation.
  # lz4 over zstd: several times cheaper to compress/decompress, at a worse
  # ratio (~2:1 vs ~3:1) — the CPU cost under memory pressure matters more.
  zramSwap = {
    enable = true;
    algorithm = "lz4";
    memoryPercent = 50;
  };
  # zram is faster than reclaiming page cache, so swap aggressively into it.
  boot.kernel.sysctl."vm.swappiness" = 80;
  # No swap readahead: zram has no seek cost to amortize, so reading 8 pages
  # per fault (the default, 3) just decompresses pages nobody asked for.
  boot.kernel.sysctl."vm.page-cluster" = 0;
  # Task delay accounting: needed for iotop's SWAPIN/IO> columns. Off by
  # default (small per-context-switch overhead); fine to enable on a desktop.
  boot.kernel.sysctl."kernel.task_delayacct" = 1;

  networking.hostName = "BLACK-BOX";
  networking.hostId   = "deadbeef";

  # Enable networking
  networking.networkmanager.enable = true;
  # Nothing on the boot path needs a synchronous "network is up" barrier;
  # this only added 5.5s to multi-user.target.
  systemd.services.NetworkManager-wait-online.enable = false;

  # Set your time zone.
  time.timeZone = "Europe/Prague";

  # Select internationalisation properties.
  i18n.defaultLocale = "en_US.UTF-8";

  i18n.extraLocaleSettings = {
    LC_ADDRESS = "cs_CZ.UTF-8";
    LC_IDENTIFICATION = "cs_CZ.UTF-8";
    LC_MEASUREMENT = "cs_CZ.UTF-8";
    LC_MONETARY = "cs_CZ.UTF-8";
    LC_NAME = "cs_CZ.UTF-8";
    LC_NUMERIC = "cs_CZ.UTF-8";
    LC_PAPER = "cs_CZ.UTF-8";
    LC_TELEPHONE = "cs_CZ.UTF-8";
    LC_TIME = "cs_CZ.UTF-8";
  };

  # Enable the X11 windowing system.
  services.xserver.enable = true;

  # Display manager, shared by both desktop environments (see desktop/).
  services.displayManager.gdm.enable = true;

  # ~/.local/bin on PATH (uv, pipx, ...). sudo below does NOT see it.
  environment.localBinInPath = true;

  # sudo gets a fixed PATH instead of inheriting the user's. Otherwise anything
  # running as komatrich could drop e.g. ~/.local/bin/env and have it run as
  # root on the next sudo -- that is also how `sudo env` (and so nh) once
  # silently ran uv's env script instead of coreutils (see CLAUDE.md).
  security.sudo.extraConfig = ''
    Defaults secure_path="/run/wrappers/bin:/run/current-system/sw/bin:/etc/profiles/per-user/root/bin:/nix/var/nix/profiles/default/bin"
  '';

  # Use gpu acceleration for GTK4 apps (NVIDIA workaround, desktop-agnostic)
  environment.variables = {
    GSK_RENDERER = "ngl";
  };

  # Auto login
  services.displayManager.autoLogin.enable = true;
  services.displayManager.autoLogin.user = config.local.user;
  # Disable getty on tty1 to prevent conflicts with GDM auto login
  systemd.services."getty@tty1".enable = false;
  systemd.services."autovt@tty1".enable = false;
  # Configure keymap in X11
  services.xserver.xkb = {
    layout = "cz";
    variant = "qwerty";
  };

  # Configure console keymap
  console.keyMap = "cz-lat2";

  services.printing = {
    enable  = true;
    drivers = [ pkgs.canon-cups-ufr2 ];
  };

  services.avahi = {
    enable       = true;
    nssmdns4     = true;
    openFirewall = true;
  };

  # Enable sound with pipewire.
  services.pulseaudio.enable = false;
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
  };

  # User accounts. Password hashes live outside git on the persisted dataset;
  # created during install with mkpasswd (see docs/INSTALL.md).
  users.mutableUsers = false;
  users.users.root = {
    hashedPasswordFile = "/persist/passwords/root";
  };

  home-manager.useGlobalPkgs = true;
  home-manager.useUserPackages = true;
  # A dotfile that exists but is not managed yet gets moved aside as
  # <file>.hm-bak instead of aborting the whole activation.
  home-manager.backupFileExtension = "hm-bak";

  users.users.${config.local.user} = {
    isNormalUser = true;
    description = "KoMatrich";
    extraGroups = [ "networkmanager" "wheel" "dialout" "input" ];
    hashedPasswordFile = "/persist/passwords/${config.local.user}";
  };
  home-manager.users.${config.local.user} = import ./home.nix;

  # Allow unfree packages
  nixpkgs.config.allowUnfree = true;

  # List packages installed in system profile.
  environment.systemPackages = [
    pkgs.git
    pkgs.git-lfs
    pkgs.gh

    pkgs.htop
    pkgs.iftop
    pkgs.iotop

    pkgs.lshw

    pkgs.pre-commit
    pkgs.at

    # PulseAudio CLI tools (pactl) for Steam audio device queries.
    # PipeWire's pulse compatibility layer provides the socket; this
    # provides only the client binary, not a conflicting daemon.
    pkgs.pulseaudio
  ];

  programs.nix-ld.enable = true;
  programs.appimage.enable = true;
  programs.appimage.binfmt = true;

  nix.settings.experimental-features = [ "nix-command" "flakes" ];
  # Flake-only system: no channels. `nixpkgs` in `nix shell nixpkgs#foo` and
  # <nixpkgs> both resolve to this system's pinned nixpkgs (flake registry).
  nix.channel.enable = false;
  nix.settings.auto-optimise-store = true;

  # CUDA packages are unfree, so cache.nixos.org never has them (llama-cpp
  # with cudaSupport, ollama-cuda). The NixOS CUDA team's cache does, as long
  # as we don't change cudaCapabilities (that changes the store hash).
  #
  # ros.cachix.org is nix-ros-overlay's binary cache (~/Repos/ros-test/nix).
  # Without it here nix ignores the flake's extra-substituters (we're not a
  # trusted user) and compiles ROS 2 from source.
  # ?priority: cache.nixos.org advertises 40 (lower = asked first). Without
  # these, every store path was looked up on both extra caches before the
  # main one, which made every build/switch slower to start.
  nix.settings.substituters = [
    "https://cache.nixos-cuda.org?priority=45"
    "https://ros.cachix.org?priority=50"
  ];
  nix.settings.trusted-public-keys = [
    "cache.nixos-cuda.org:74DUi4Ye579gUqzH4ziL9IyiJBlDpMRn9MBN8oNan9M="
    "ros.cachix.org-1:dSyZxI8geDCJrwgvCOHDoAfOm5sV1wCPjBkKL+38Rvo="
  ];

  services.thermald.enable = true;

  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken. It‘s perfectly fine and recommended to leave
  # this value at the release version of the first install of this system.
  # Before changing this value read the documentation for this option
  # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
  system.stateVersion = "25.05"; # Did you read the comment?
}
