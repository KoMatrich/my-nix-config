# Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running ‘nixos-help’).

{ config, pkgs, home-manager, ... }:

{
  imports =
    [ # Include the results of the hardware scan.
      ./hardware-configuration.nix
      ./disko-config.nix
      ./nvidia.nix
      ./system/zfs.nix
      ./system/replication.nix
      ./system/shell.nix
      ./system/zerotier.nix
      ./system/firewall.nix
      ./system/power.nix
      ./apps/antivirus.nix
      ./apps/impermanence.nix
      ./apps/virtualization.nix
      ./apps/steam.nix
      ./apps/heroic.nix
      ./apps/devshells.nix
      ./apps/owon-vds1022.nix
      # ./apps/comfyui.nix
      ./apps/godot.nix
      
      # Desktop environment: import exactly ONE of these.
      ./desktop/gnome.nix
      # ./desktop/hyprland.nix
    ];

  # Bootloader.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  # Skip the boot menu; hold Space during firmware handoff to get it back
  # (e.g. to select an older generation).
  boot.loader.timeout = 0;

  services.fwupd.enable = true;

  # Compressed swap in RAM; no disk swap, no hibernation.
  zramSwap = {
    enable = true;
    algorithm = "zstd";
    memoryPercent = 75;
  };
  # zram is faster than reclaiming page cache, so swap aggressively into it.
  boot.kernel.sysctl."vm.swappiness" = 180;

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

  # Use gpu acceleration for GTK4 apps (NVIDIA workaround, desktop-agnostic)
  environment.localBinInPath = true;
  environment.variables = {
    GSK_RENDERER = "ngl";
  };

  # Auto login
  services.displayManager.autoLogin.enable = true;
  services.displayManager.autoLogin.user = "komatrich";
  # Prevent sleep on lid close on power
  services.logind.lidSwitch = "ignore";
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

  users.users.komatrich = {
    isNormalUser = true;
    description = "KoMatrich";
    # "input" lets voice2text read /dev/input/event* directly for its
    # push-to-talk key. Under Wayland an X11/XRecord listener only sees keys
    # while an XWayland window has focus, which is almost never. Note this also
    # means any process running as this user can read all keyboard input.
    extraGroups = [ "networkmanager" "wheel" "dialout" "input" ];
    hashedPasswordFile = "/persist/passwords/komatrich";
  };
  home-manager.users.komatrich = import ./home.nix;

  # Allow unfree packages
  nixpkgs.config.allowUnfree = true;

  # List packages installed in system profile.
  environment.systemPackages = with pkgs; [
    pkgs.git
    pkgs.git-lfs
    pkgs.gh

    pkgs.htop
    pkgs.iftop
    pkgs.iotop

    pkgs.lshw

    pkgs.pre-commit

    # PulseAudio CLI tools (pactl) for Steam audio device queries.
    # PipeWire's pulse compatibility layer provides the socket; this
    # provides only the client binary, not a conflicting daemon.
    pkgs.pulseaudio

    (pkgs.llama-cpp.override { cudaSupport = true; })
  ];

  programs.nix-ld.enable = true;
  programs.appimage.enable = true;
  programs.appimage.binfmt = true;
  
  nix.settings.experimental-features = [ "nix-command" "flakes" ];
    
  services.thermald.enable = true;

  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken. It‘s perfectly fine and recommended to leave
  # this value at the release version of the first install of this system.
  # Before changing this value read the documentation for this option
  # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
  system.stateVersion = "25.05"; # Did you read the comment?
}
