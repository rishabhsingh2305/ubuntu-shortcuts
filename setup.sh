#!/usr/bin/env bash
#
# Fresh Ubuntu provisioning for ubuntu-shortcuts.
#
# Run this once on a new machine, as your normal user (not root):
#   ./setup.sh
#
# It installs the base packages, Oh My Zsh, SDKMAN!, Docker, and then calls
# ./install.sh to link the repository-managed zsh configuration.

set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
REPO_ROOT=$SCRIPT_DIR
DRY_RUN=0

# shellcheck source=lib/common.sh
source "$REPO_ROOT/lib/common.sh"

if (( EUID == 0 )); then
  die "Run setup.sh as your normal user, not with sudo/root."
fi

if ! command -v sudo >/dev/null 2>&1; then
  die "sudo is required to install packages."
fi

info "updating apt package lists"
sudo apt-get update

info "installing base packages"
sudo apt-get install -y \
  ca-certificates \
  curl \
  git \
  lsof \
  openssl \
  zsh \
  docker.io \
  unzip \
  zip

if ! sudo apt-get install -y docker-compose-v2; then
  warn "docker-compose-v2 is unavailable; falling back to docker-compose"
  sudo apt-get install -y docker-compose
fi

if [[ ! -d "$HOME/.oh-my-zsh" ]]; then
  info "installing Oh My Zsh"
  sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
else
  info "Oh My Zsh already installed"
fi

if [[ ! -d "$HOME/.sdkman" ]]; then
  info "installing SDKMAN!"
  curl -s "https://get.sdkman.io" | bash
else
  info "SDKMAN! already installed"
fi

if getent group docker >/dev/null 2>&1; then
  sudo usermod -aG docker "$USER"
else
  sudo groupadd docker
  sudo usermod -aG docker "$USER"
fi

info "linking ubuntu-shortcuts"
"$REPO_ROOT/install.sh"

if [[ ${SHELL:-} != *zsh ]]; then
  info "setting zsh as the default shell"
  chsh -s "$(command -v zsh)"
else
  info "zsh is already the default shell"
fi

cat <<'EOF'

Setup complete.

  - Log out and back in (or run `newgrp docker`) for the Docker group.
  - Start a new terminal, or run: exec zsh
  - Verify: type caffeinate; caffinate help
EOF
