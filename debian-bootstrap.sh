#!/usr/bin/env bash
set -euo pipefail

# =========================
# Debian Bootstrap Script
# =========================
# Usage (from fresh install):
#   curl -fsSL https://raw.githubusercontent.com/psycho-daisies/bug-free-robot/main/debian-bootstrap.sh | bash
#
# Flags (set before the pipe or export in shell):
#   INSTALL_KDE=true|false           (default: true)
#   INSTALL_VSCODE=true|false        (default: true)
#   INSTALL_FLATPAK=true|false       (default: true)
#   INSTALL_DOCKER=true|false        (default: false)
#   INSTALL_NODE=true|false          (default: true, via nvm)
#   SET_SDDM_DEFAULT=true|false      (default: true when KDE is installed)
#   NONINTERACTIVE=true|false        (default: true; uses apt -y)
#
# Example: skip KDE, include Docker
#   INSTALL_KDE=false INSTALL_DOCKER=true curl -fsSL https://raw.githubusercontent.com/psycho-daisies/bug-free-robot/main/debian-bootstrap.sh | bash

# -------------------------
# Defaults
# -------------------------
INSTALL_KDE="${INSTALL_KDE:-false}"
INSTALL_VSCODE="${INSTALL_VSCODE:-true}"
INSTALL_FLATPAK="${INSTALL_FLATPAK:-true}"
INSTALL_DOCKER="${INSTALL_DOCKER:-false}"
INSTALL_NODE="${INSTALL_NODE:-true}"
SET_SDDM_DEFAULT="${SET_SDDM_DEFAULT:-true}"
NONINTERACTIVE="${NONINTERACTIVE:-true}"

if [[ "${NONINTERACTIVE}" == "true" ]]; then
  export DEBIAN_FRONTEND=noninteractive
  APT_YES="-y"
else
  APT_YES=""
fi

# -------------------------
# Helpers
# -------------------------
need_cmd() { command -v "$1" >/dev/null 2>&1; }
log() { printf "\n\033[1;36m[bootstrap]\033[0m %s\n" "$*"; }
err() { printf "\n\033[1;31m[error]\033[0m %s\n" "$*" >&2; }

require_sudo() {
  if [[ "$(id -u)" -eq 0 ]]; then
    SUDO=""
  else
    if ! need_cmd sudo; then
      err "sudo is required; installing."
      su -c "apt-get update && apt-get install -y sudo"
    fi
    SUDO="sudo"
  fi
}

apt_update() {
  log "Updating apt package lists…"
  ${SUDO} apt-get update -y
}

apt_install() {
  # shellcheck disable=SC2068
  ${SUDO} apt-get install ${APT_YES} $@
}

codename() {
  . /etc/os-release
  echo "${VERSION_CODENAME:-bookworm}"
}

ensure_basic_tools() {
  log "Installing base tooling…"
  apt_install \
    ca-certificates gnupg lsb-release software-properties-common \
    build-essential pkg-config cmake \
    curl wget unzip zip tar xz-utils \
    git git-lfs \
    python3 python3-pip python3-venv \
    ripgrep fd-find fzf jq \
    htop btop neovim nano \
    tmux tree \
    openssh-client \
    flameshot \
    net-tools dnsutils
  # Debian names fd as fdfind (create convenience alias)
  if ! grep -q "alias fd=" ~/.bashrc 2>/dev/null; then
    echo "alias fd=fdfind" >> ~/.bashrc
  fi
}

install_kde() {
  [[ "${INSTALL_KDE}" == "true" ]] || { log "Skipping KDE Plasma."; return; }
  log "Installing KDE Plasma (task-kde-desktop)…"
  apt_install task-kde-desktop

  if [[ "${SET_SDDM_DEFAULT}" == "true" ]]; then
    # Prefer sddm display manager if present
    if need_cmd dpkg-reconfigure; then
      log "Setting SDDM as default display manager (noninteractive)…"
      echo sddm shared/default-x-display-manager select sddm | ${SUDO} debconf-set-selections || true
      ${SUDO} dpkg-reconfigure -f noninteractive sddm || true
    fi
  fi

  # Nice KDE apps
  apt_install konsole dolphin krusader
}

install_terminals() {
  log "Installing terminals…"
  # KDE's Konsole already installed if KDE chosen
  apt_install kitty tilix alacritty
  # You can choose your favorite later; all coexist fine.
}

install_file_managers() {
  log "Installing extra file managers…"
  # Dolphin/krusader installed with KDE; add cross-DE choices:
  apt_install doublecmd-qt thunar nemo ranger
}

install_flatpak() {
  [[ "${INSTALL_FLATPAK}" == "true" ]] || { log "Skipping Flatpak."; return; }
  log "Installing Flatpak and adding Flathub…"
  apt_install flatpak
  # Integrate with KDE Discover if present
  apt_install plasma-discover-backend-flatpak || true

  if ! need_cmd flatpak; then
    err "Flatpak not found after install."
    return
  fi

  if ! flatpak remotes | grep -q flathub; then
    ${SUDO} -u "$SUDO_USER" flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo || true
  fi
}

install_vscode() {
  [[ "${INSTALL_VSCODE}" == "true" ]] || { log "Skipping VS Code."; return; }
  log "Adding Microsoft VS Code repository and installing Code…"
  local CODENAME; CODENAME="$(codename)"

  # Microsoft GPG key & repo
  mkdir -p /etc/apt/keyrings
  curl -fsSL https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor | ${SUDO} tee /etc/apt/keyrings/packages.microsoft.gpg >/dev/null
  ${SUDO} chmod go+r /etc/apt/keyrings/packages.microsoft.gpg

  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/packages.microsoft.gpg] https://packages.microsoft.com/repos/code stable main" | ${SUDO} tee /etc/apt/sources.list.d/vscode.list > /dev/null

  apt_update
  apt_install code
}

install_node_nvm() {
  [[ "${INSTALL_NODE}" == "true" ]] || { log "Skipping Node (nvm)."; return; }
  log "Installing Node via nvm (user-local)…"
  if [[ -n "${SUDO_USER:-}" && "${SUDO_USER}" != "root" ]]; then
    local TARGET_USER="${SUDO_USER}"
  else
    local TARGET_USER="${USER}"
  fi

  local NVM_DIR="/home/${TARGET_USER}/.nvm"
  if [[ "${TARGET_USER}" == "root" ]]; then NVM_DIR="/root/.nvm"; fi

  # Install nvm as the target user
  su - "${TARGET_USER}" -c 'bash -lc "curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash"'
  su - "${TARGET_USER}" -c 'bash -lc "export NVM_DIR=\"$HOME/.nvm\" && . \"$NVM_DIR/nvm.sh\" && nvm install --lts && nvm alias default lts/*"'
}

install_docker() {
  [[ "${INSTALL_DOCKER}" == "true" ]] || { log "Skipping Docker."; return; }
  echo "Skipping docker"
  # log "Installing Docker Engine + Compose from Docker’s repo…"
  # local ARCH; ARCH="$(dpkg --print-architecture)"
  # local CODENAME; CODENAME="$(codename)"

  # apt_install \
  #   ca-certificates curl gnupg

  # install -m 0755 -d /etc/apt/keyrings
  # curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor | ${SUDO} tee /etc/apt/keyrings/docker.gpg >/dev/null
  # ${SUDO} chmod a+r /etc/apt/keyrings/docker.gpg

  # echo "deb [arch=${ARCH} signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian ${CODENAME} stable" | ${SUDO} tee /etc/apt/sources.list.d/docker.list > /dev/null

  # apt_update
  # apt_install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

  # # Add current user to docker group
  # local U="${SUDO_USER:-$USER}"
  # ${SUDO} usermod -aG docker "$U" || true
  # log "Docker installed. You may need to log out and back in for docker group to take effect."
}

post_tweaks() {
  log "Post-install tweaks…"
  # Fastfetch (nicer neofetch) if available
  apt_install fastfetch || true

  # Git defaults (only set if missing)
  if ! git config --global user.name >/dev/null 2>&1; then
    git config --global user.name "${SUDO_USER:-$USER}"
  fi
  if ! git config --global user.email >/dev/null 2>&1; then
    git config --global user.email "${SUDO_USER:-$USER}@localhost"
  fi
  git config --global init.defaultBranch main

  # Nice default bash improvements (idempotent)
  if ! grep -q "HISTCONTROL=ignoreboth" ~/.bashrc 2>/dev/null; then
    cat >> ~/.bashrc <<'EOF'
# Quality of life
HISTCONTROL=ignoredups:ignorespace
shopt -s histappend
PROMPT_DIRTRIM=3
export EDITOR=nvim
# fzf if present
[ -f ~/.fzf.bash ] && source ~/.fzf.bash
EOF
  fi
}

main() {
  require_sudo
  apt_update
  ensure_basic_tools
  install_vscode
  install_kde
  install_terminals
  install_file_managers
  install_flatpak
  install_node_nvm
  install_docker
  post_tweaks

  log "Setup Done! Reboot if you installed a new desktop or display manager."
}

main "$@"
