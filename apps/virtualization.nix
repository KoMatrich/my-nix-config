{ config, lib, pkgs, ... }:
{
  virtualisation.docker = {
    enable = true;
    # Socket-activated instead: dockerd starts on the first `docker` command
    # (~2s once), rather than costing 2.1s on every boot.
    enableOnBoot = false;
  };

  # Rootless Docker: dockerd runs as the logged-in user inside a user namespace,
  # so no sudo and no root-equivalent `docker` group (membership in that group is
  # effectively root: `docker run -v /:/host`). Deliberate choice for running
  # untrusted/CTF containers. Data root is ~/.local/share/docker, which sits on
  # the persisted zroot/safe/home dataset - impermanence needs nothing.
  #
  # The rootful daemon above stays enabled but socket-activated; komatrich is not
  # in `docker`, so reaching it still needs `sudo docker -H unix:///var/run/docker.sock`.
  # Images do not migrate between the two stores.
  virtualisation.docker.rootless = {
    enable = true;
    setSocketVariable = true; # DOCKER_HOST=unix://$XDG_RUNTIME_DIR/docker.sock
  };

  environment.systemPackages = with pkgs; [
    docker-compose
    distrobox
  ];
}
