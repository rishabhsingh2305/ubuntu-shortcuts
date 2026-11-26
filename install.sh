#!/usr/bin/env bash
#
# ubuntu-shortcuts installer.
#
# Makes this repository the source of truth for the zsh configuration:
#   ~/.oh-my-zsh/custom/autoload.zsh -> <repo>/zsh/autoload.zsh
#   ~/.oh-my-zsh/custom/aliases.zsh  -> <repo>/zsh/aliases.zsh
#
# Safe to run repeatedly. No sudo is used for anything under $HOME.
#
# Usage:
#   ./install.sh [--dry-run] [--copy] [--uninstall] [zsh] [docker] [all]
#
# Modules:
#   zsh      Link the zsh entrypoint and aliases (default)
#   docker   Ensure docker/mysql/.env exists and validate compose files (default)
#   all      Both modules (default)
#
# Options:
#   --dry-run     Print actions without changing anything
#   --copy        Install a detached copy under ~/.local/share/ubuntu-shortcuts
#   --uninstall   Remove links that point into this repo and restore the latest backup
#   -h, --help    Show this help text

set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
REPO_ROOT=$SCRIPT_DIR

# If this script was fetched on its own (curl | bash), clone the repository.
if [[ ! -f "$REPO_ROOT/lib/common.sh" ]]; then
  if ! command -v git >/dev/null 2>&1; then
    printf '[error] git is required to bootstrap the repository.\n' >&2
    exit 1
  fi
  INSTALL_ROOT=${XDG_DATA_HOME:-$HOME/.local/share}/ubuntu-shortcuts
  if [[ ! -d "$INSTALL_ROOT/.git" ]]; then
    printf '[info] cloning %s into %s\n' "${UBUNTU_SHORTCUTS_REPO:-https://github.com/rishabhsingh2305/ubuntu-shortcuts.git}" "$INSTALL_ROOT"
    mkdir -p -- "$(dirname -- "$INSTALL_ROOT")"
    git clone --depth 1 "${UBUNTU_SHORTCUTS_REPO:-https://github.com/rishabhsingh2305/ubuntu-shortcuts.git}" "$INSTALL_ROOT"
  else
    git -C "$INSTALL_ROOT" pull --ff-only
  fi
  REPO_ROOT=$INSTALL_ROOT
fi

# shellcheck source=lib/common.sh
source "$REPO_ROOT/lib/common.sh"

ZSH_CUSTOM=${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}
STATE_DIR=${XDG_STATE_HOME:-$HOME/.local/state}/ubuntu-shortcuts
BACKUP_DIR="$STATE_DIR/backups/$(date +%Y%m%d-%H%M%S)"
DRY_RUN=0
COPY_MODE=0
UNINSTALL=0
DO_ZSH=1
DO_DOCKER=1
MODULES=()

usage() {
  cat <<'EOF'
ubuntu-shortcuts installer.

Makes this repository the source of truth for the zsh configuration:
  ~/.oh-my-zsh/custom/autoload.zsh -> <repo>/zsh/autoload.zsh
  ~/.oh-my-zsh/custom/aliases.zsh  -> <repo>/zsh/aliases.zsh

Safe to run repeatedly. No sudo is used for anything under $HOME.

Usage:
  ./install.sh [--dry-run] [--copy] [--uninstall] [zsh] [docker] [all]

Modules:
  zsh      Link the zsh entrypoint and aliases (default)
  docker   Ensure docker/mysql/.env exists and validate compose files (default)
  all      Both modules (default)

Options:
  --dry-run     Print actions without changing anything
  --copy        Install a detached copy under ~/.local/share/ubuntu-shortcuts
  --uninstall   Remove links that point into this repo and restore the latest backup
  -h, --help    Show this help text
EOF
}

while (( $# > 0 )); do
  case $1 in
    --dry-run)
      DRY_RUN=1
      ;;
    --copy)
      COPY_MODE=1
      ;;
    --uninstall)
      UNINSTALL=1
      ;;
    zsh|docker|all)
      MODULES+=("$1")
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      die "Unknown option or module: $1 (try --help)"
      ;;
  esac
  shift
done

if (( ${#MODULES[@]} > 0 )); then
  DO_ZSH=0
  DO_DOCKER=0
  for module in "${MODULES[@]}"; do
    case $module in
      zsh) DO_ZSH=1 ;;
      docker) DO_DOCKER=1 ;;
      all) DO_ZSH=1; DO_DOCKER=1 ;;
    esac
  done
fi

install_zsh() {
  if [[ ! -d "$HOME/.oh-my-zsh" ]]; then
    warn "Oh My Zsh not found at $HOME/.oh-my-zsh; run ./setup.sh first."
    warn "Links will still be created, but they will not load until OMZ is installed."
  fi

  link_file "$REPO_ROOT/zsh/autoload.zsh" "$ZSH_CUSTOM/autoload.zsh"
  link_file "$REPO_ROOT/zsh/aliases.zsh" "$ZSH_CUSTOM/aliases.zsh"

  # Remove the old monolithic download from .zshrc, if present.
  if [[ -f "$HOME/.zshrc" ]] && grep -Eq '^[[:space:]]*source[[:space:]]+.*\.my_zsh_functions' "$HOME/.zshrc"; then
    backup_path "$HOME/.zshrc"
    if (( ! DRY_RUN )); then
      sed -i '/\.my_zsh_functions/s/^/# [ubuntu-shortcuts] /' "$HOME/.zshrc"
    fi
    info "disabled the legacy .my_zsh_functions source line in .zshrc"
  fi

  # Migrate the original caffeinate function out of the OMZ custom directory.
  # The repo copy is authoritative; the old file is preserved in the backup.
  local old_caffeinate="$ZSH_CUSTOM/functions/caffeinate"
  if [[ -f $old_caffeinate && ! -L $old_caffeinate && -f "$REPO_ROOT/zsh/functions/caffeinate" ]]; then
    backup_path "$old_caffeinate"
    if (( ! DRY_RUN )); then
      rm -f -- "$old_caffeinate"
    fi
    info "removed the old custom/functions/caffeinate (now owned by the repo)"
  fi
}

docker_env_example() {
  local dir=$1
  printf '%s\n' \
    '# Local MySQL settings (gitignored).' \
    'MYSQL_ROOT_PASSWORD=change-me' \
    'MYSQL_DATABASE=appdb' \
    'MYSQL_USER=appuser' \
    'MYSQL_PASSWORD=change-me-too' >| "$dir"
}

install_docker() {
  local mysql_dir="$REPO_ROOT/docker/mysql"
  local env_file="$mysql_dir/.env"
  local env_example="$mysql_dir/.env.example"

  if [[ ! -f $env_example ]]; then
    if (( DRY_RUN )); then
      printf '[dry-run] create %s\n' "$env_example"
    else
      docker_env_example "$env_example"
      info "created $env_example"
    fi
  fi

  if [[ ! -f $env_file ]]; then
    if (( DRY_RUN )); then
      printf '[dry-run] create %s with generated passwords\n' "$env_file"
    else
      local root_pw user_pw
      if command -v openssl >/dev/null 2>&1; then
        root_pw=$(openssl rand -hex 16)
        user_pw=$(openssl rand -hex 16)
      else
        root_pw=$(od -An -N16 -tx1 /dev/urandom | tr -d ' \n')
        user_pw=$(od -An -N16 -tx1 /dev/urandom | tr -d ' \n')
      fi
      sed -e "s|^MYSQL_ROOT_PASSWORD=.*|MYSQL_ROOT_PASSWORD=$root_pw|" \
          -e "s|^MYSQL_PASSWORD=.*|MYSQL_PASSWORD=$user_pw|" \
          "$env_example" >| "$env_file"
      chmod 600 -- "$env_file"
      info "created $env_file with generated MySQL passwords"
      info "edit that file if you want to choose your own passwords"
    fi
  fi

  if command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
    if (( ! DRY_RUN )); then
      if (cd "$mysql_dir" && docker compose config >/dev/null 2>&1); then
        info "docker/mysql/compose.yml is valid"
      else
        warn "docker compose could not validate docker/mysql/compose.yml"
      fi
      if docker compose -f "$REPO_ROOT/docker/kafka/compose.yml" config >/dev/null 2>&1; then
        info "docker/kafka/compose.yml is valid"
      else
        warn "docker compose could not validate docker/kafka/compose.yml"
      fi
    fi
  else
    info "docker compose not available; skipping compose validation"
  fi
}

verify_zsh() {
  if ! command -v zsh >/dev/null 2>&1; then
    warn "zsh is not installed; skipping zsh verification"
    return 0
  fi

  local functions=("$REPO_ROOT"/zsh/functions/*)
  zsh -n "$REPO_ROOT/zsh/autoload.zsh" "$REPO_ROOT/zsh/aliases.zsh" "${functions[@]}"

  # shellcheck disable=SC2016  # this is zsh code; $ZSH_CUSTOM is expanded there
  ZSH_CUSTOM=$ZSH_CUSTOM zsh -dfc '
    source "$ZSH_CUSTOM/autoload.zsh"
    source "$ZSH_CUSTOM/aliases.zsh"
    for cmd in caffeinate caffinate killport kafka_up sql gemini; do
      whence -w "$cmd" >/dev/null || {
        print -u2 "verification failed: $cmd is not available"
        exit 1
      }
    done
    caffeinate help >/dev/null
    print "zsh verification passed"
  '
}

uninstall() {
  local install_root=${XDG_DATA_HOME:-$HOME/.local/share}/ubuntu-shortcuts
  local -a link_roots=("$REPO_ROOT")
  [[ -d $install_root ]] && link_roots+=("$install_root")

  local dest resolved root matched
  for dest in "$ZSH_CUSTOM/autoload.zsh" "$ZSH_CUSTOM/aliases.zsh"; do
    matched=0
    if [[ -L $dest ]]; then
      resolved=$(readlink -f -- "$dest")
      for root in "${link_roots[@]}"; do
        if [[ $resolved == "$root"/* ]]; then
          matched=1
          break
        fi
      done
    fi

    if (( matched )); then
      if (( DRY_RUN )); then
        printf '[dry-run] remove %s\n' "$dest"
      else
        rm -f -- "$dest"
        info "removed $dest"
      fi
    else
      warn "not removing $dest (not a symlink into this repo)"
    fi
  done

  local latest
  latest=$(find "$STATE_DIR/backups" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sort | tail -n 1 || true)
  if [[ -n $latest ]]; then
    info "restoring files from $latest"
    while IFS= read -r -d '' file; do
      local rel=${file#"$latest"/}
      local target="$HOME/$rel"
      if (( DRY_RUN )); then
        printf '[dry-run] restore %s\n' "$target"
      else
        mkdir -p -- "$(dirname -- "$target")"
        rm -rf -- "$target"
        cp -a -- "$file" "$target"
        info "restored $target"
      fi
    done < <(find "$latest" -mindepth 1 \( -type f -o -type l \) -print0)
  else
    info "no backups found under $STATE_DIR/backups"
  fi
}

main() {
  if (( UNINSTALL )); then
    uninstall
    return 0
  fi

  (( DRY_RUN )) && info "dry run: no files will be changed"

  if (( COPY_MODE )); then
    local install_root=${XDG_DATA_HOME:-$HOME/.local/share}/ubuntu-shortcuts
    if (( DRY_RUN )); then
      info "would copy zsh/ and docker/ to $install_root"
    else
      mkdir -p -- "$install_root"
      rm -rf -- "$install_root/zsh" "$install_root/docker"
      cp -a -- "$REPO_ROOT/zsh" "$REPO_ROOT/docker" "$install_root/"
      info "copied zsh/ and docker/ to $install_root"
    fi
    REPO_ROOT=$install_root
  fi

  if (( DO_ZSH )); then
    install_zsh
  fi
  if (( DO_DOCKER )); then
    install_docker
  fi

  if (( DO_ZSH && ! DRY_RUN )); then
    verify_zsh
  fi

  info "done. restart the shell with: exec zsh"
}

main "$@"
