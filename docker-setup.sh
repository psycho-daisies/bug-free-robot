#!/usr/bin/env bash
set -euo pipefail

# Docker Engine + Compose on Debian 12 (official apt repo, non-root usage)
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/<you>/<repo>/main/docker-setup.sh | bash

log(){ printf "\n\033[1;36m[docker-setup]\033[0m %s\n" "$*"; }
err(){ printf "\n\033[1;31m[error]\033[0m %s\n" "$*" >&2; }

# Require sudo if not root
if [[ "$(id -u)" -ne 0 ]]; then
  command -v sudo >/dev/null || { err "sudo is required"; exit 1; }
  SUDO="sudo"
else
  SUDO=""
fi

log "Updating apt and installing prerequisites…"
${SUDO} apt-get update -y
${SUDO} apt-get install -y ca-certificates curl

log "Adding Docker GPG key (ASC, no dearmor)…"
${SUDO} install -m 0755 -d /etc/apt/keyrings
${SUDO} curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc
${SUDO} chmod a+r /etc/apt/keyrings/docker.asc

log "Adding Docker apt repository…"
ARCH="$(dpkg --print-architecture)"
CODENAME="$(. /etc/os-release && echo "$VERSION_CODENAME")"
echo "deb [arch=${ARCH} signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian ${CODENAME} stable" \
  | ${SUDO} tee /etc/apt/sources.list.d/docker.list >/dev/null

${SUDO} apt-get update -y

log "Installing Docker Engine, CLI, Buildx, and Compose plugin…"
${SUDO} apt-get install -y \
  docker-ce docker-ce-cli containerd.io \
  docker-buildx-plugin docker-compose-plugin

# Non-root setup
USER_NAME="${SUDO_USER:-$USER}"
log "Ensuring 'docker' group exists and adding ${USER_NAME} to it…"
getent group docker >/dev/null || ${SUDO} groupadd docker
${SUDO} usermod -aG docker "${USER_NAME}"

log "Done adding ${USER_NAME} to docker group."
log "Activate membership now with:  newgrp docker"
log "Or log out and back in before running Docker without sudo."

# Quick test (may require newgrp/log out first)
log "Testing Docker (will succeed after group is active)…"
if docker run --rm hello-world >/dev/null 2>&1; then
  log "Docker test successful!"
else
  log "Install complete. Run 'newgrp docker' and then: docker run --rm hello-world"
fi

log "Verify versions with:  docker --version  &&  docker compose version"
