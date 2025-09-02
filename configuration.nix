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
      ./apps/antivirus.nix
      ./apps/impermanence.nix
      ./apps/virtualization.nix
      ./apps/steam.nix
    ];

  # Bootloader.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  
  boot.supportedFilesystems = [ "zfs" "ntfs" ];
  boot.initrd.systemd = {
    enable = false;
    services.initrd-rollback-root = {
      after = [ "initrd-decrypt-disks" "zfs-import-rpool.service" ];
      wantedBy = [ "initrd.target" ];
      before = [ "sysroot.mount" ];
      path = [ pkgs.zfs ];
      description = "Rollback root fs";
      unitConfig.DefaultDependencies = "no";
      serviceConfig.Type = "oneshot";
      script = "zfs rollback -r zroot/root@blank";
    };
  };

  # Disable NetworkManager-wait-online service to speed up boot time
  systemd.services.NetworkManager-wait-online.enable = false;

  # swapDevices = [ {
  #   device = "/swapfile";
  #   size = 38*1024;
  # } ];
  
  # NIXOS Boot cleanup 
  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 7d";
  };
  
  # NIXOS Auto system update
  system.autoUpgrade = {
    enable = true;
  };
  
  services.fwupd.enable = true;
  
  # Use more RAM instead DISK
  boot.kernel.sysctl = {
   # reduce swapping
   "vm.swappiness" = 10;
   # tell the kernel to use up to X% of the RAM as cache for writes and instruct kernel to use up to 50% of RAM before slowing down the process that's writing (default for dirty_background_ratio is 10).
   "vm.dirty_ratio" = 80;
   # Start background writeback (via writeback threads) at this percentage
   "vm.dirty_background_ratio" = 50;
  };

  networking.hostName = "BLACK-BOX";
  networking.hostId   = "deadbeef";

  # Enable networking
  networking.networkmanager.enable = true;

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

  # Enable the GNOME Desktop Environment.
  services.xserver.displayManager.gdm.enable = true;
  services.xserver.desktopManager.gnome.enable = true;

  # Use gpu acceleration for GTK4 apps
  environment.variables = {
    GSK_RENDERER = "ngl";
  };

  # Auto login
  services.displayManager.autoLogin.enable = true;
  services.displayManager.autoLogin.user = "komatrich";
  # Disable getty on tty1 to prevent conflicts with GDM auto login
  systemd.services."getty@tty1".enable = false;
  systemd.services."autovt@tty1".enable = false;
  # Enable Gnome Keyring integration with SDDM
  security.pam.services.sddm.enableGnomeKeyring = true;

  # Configure keymap in X11
  services.xserver.xkb = {
    layout = "cz";
    variant = "qwerty";
  };

  # Configure console keymap
  console.keyMap = "cz-lat2";

  # Enable CUPS to print documents.
  services.printing.enable = true;

  # Enable Avahi for network discovery
  services.avahi = {
    enable = true;
    nssmdns4 = true;
    openFirewall = true;
  };

  services.gvfs.enable = true;

  # Enable sound with pipewire.
  services.pulseaudio.enable = false;
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
  };

  # Define a user account
  users.users.root = {
    hashedPassword = "$6$XQ4K/YSLv6ZtTN4s$NcKy5CZRP/RYke/LYfBuI6Oel.iq9xxrVdXkunZ/mPZbpteHOiHKa//yL6PdG0d8GE0gFEvECVYmKnwKHz2O2.";
  };
  
  home-manager.useGlobalPkgs = true;
  home-manager.useUserPackages = true;

  users.users.komatrich = {
    isNormalUser = true;
    description = "KoMatrich";
    extraGroups = [ "networkmanager" "wheel" ];
    hashedPassword = "$6$XQ4K/YSLv6ZtTN4s$NcKy5CZRP/RYke/LYfBuI6Oel.iq9xxrVdXkunZ/mPZbpteHOiHKa//yL6PdG0d8GE0gFEvECVYmKnwKHz2O2.";
  };
  home-manager.users.komatrich = import ./home.nix;

  # Allow unfree packages
  nixpkgs.config.allowUnfree = true;

  # List packages installed in system profile.
  environment.systemPackages = with pkgs; [
    pkgs.git
    pkgs.git-lfs
    
    pkgs.htop
    pkgs.iftop
    pkgs.iotop
    
    pkgs.lshw
    
    pkgs.gnome-keyring
    pkgs.gnome-settings-daemon
  ];
  
  environment.gnome.excludePackages = (with pkgs; [
    atomix # puzzle game
    cheese # webcam tool
    # epiphany # web browser
    # evince # document viewer
    geary # email reader
    # gedit # text editor
    # gnome-characters
    # gnome-music
    # gnome-photos
    # gnome-terminal
    gnome-tour
    hitori # sudoku game
    iagno # go game
    tali # poker game
    totem # video player
  ]);
  
  # GSConnect
  networking.firewall = rec {
    allowedTCPPortRanges = [ { from = 1714; to = 1764; } ];
    allowedUDPPortRanges = allowedTCPPortRanges;
  };
  
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
