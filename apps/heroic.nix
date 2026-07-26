{ config, lib, pkgs, ... }:
{
  # Heroic Games Launcher (Epic, GOG, Amazon).
  # Game library lives on the big/slow SSD next to Steam's (/games).
  # One-time setup after install: Heroic -> Settings -> Default Install Path
  # -> /games/heroic (the choice is stored in ~/.config/heroic, which is
  # persisted on /home, same as save games and Wine/Proton prefixes).
  environment.systemPackages = [
    pkgs.heroic
  ];
}
