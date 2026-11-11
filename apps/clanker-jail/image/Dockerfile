# ClankerJail image: a plain mutable Debian box for an unrestricted coding
# agent. Built on demand by `clanker` (apps/clanker-jail/default.nix), tagged
# with a hash of this directory so an edit here is noticed on the next `clanker`.
#
# Only the OS base lives here. Claude Code and T3 Code install themselves into
# the persistent home volume on first start (entrypoint.sh), so they can
# self-update and survive `clanker reset`.
FROM debian:trixie-slim

# IS_SANDBOX=1: Claude Code refuses --dangerously-skip-permissions as root
# unless told it is sandboxed. Root is needed: under rootless Docker container
# root maps to the host user, so only root can write the bind-mounted /work.
# PIP_BREAK_SYSTEM_PACKAGES=1: let the agent `pip install` into the system
# Python (PEP 668 would refuse).
ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8 \
    HOME=/root \
    PATH=/root/.local/bin:/root/.cargo/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
    IS_SANDBOX=1 \
    PIP_BREAK_SYSTEM_PACKAGES=1

# A useful baseline so most tasks need no install at all; anything else is one
# `apt-get install` away (the agent is root and is told so in its CLAUDE.md).
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      ca-certificates curl wget gnupg \
      git git-lfs gh openssh-client \
      bash-completion less nano vim-tiny tmux procps psmisc file tree \
      iproute2 iputils-ping dnsutils \
      build-essential pkg-config cmake \
      python3 python3-pip python3-venv pipx \
      nodejs npm \
      ripgrep fd-find jq unzip zip xz-utils zstd \
 && ln -s /usr/bin/fdfind /usr/local/bin/fd \
 && rm -rf /var/lib/apt/lists/*

COPY CLAUDE.md settings.json /etc/clankerjail/
COPY entrypoint.sh /usr/local/bin/clankerjail-entrypoint
RUN chmod 0755 /usr/local/bin/clankerjail-entrypoint

WORKDIR /work
EXPOSE 3773
CMD ["/usr/local/bin/clankerjail-entrypoint"]
