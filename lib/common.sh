#!/usr/bin/env bash
# Shared helpers for install.sh. This file is sourced, not executed.

: "${DRY_RUN:=0}"
: "${BACKUP_DIR:=${XDG_STATE_HOME:-$HOME/.local/state}/ubuntu-shortcuts/backups}"

info() {
  printf '[info] %s\n' "$*"
}

warn() {
  printf '[warn] %s\n' "$*" >&2
}

die() {
  printf '[error] %s\n' "$*" >&2
  exit 1
}

# Copy a file/symlink into the timestamped backup directory, preserving its
# path relative to $HOME.
backup_path() {
  local path=$1
  [[ -e $path || -L $path ]] || return 0

  if (( DRY_RUN )); then
    printf '[dry-run] backup %s\n' "$path"
    return 0
  fi

  local rel=${path#"$HOME"/}
  local dest="$BACKUP_DIR/$rel"
  mkdir -p -- "$(dirname -- "$dest")"
  cp -a -- "$path" "$dest"
  info "backed up $path -> $dest"
}

# Symlink src to dest. Existing files are backed up first.
link_file() {
  local src=$1
  local dest=$2

  if [[ -L $dest ]] && [[ $(readlink -f -- "$dest") == "$(readlink -f -- "$src")" ]]; then
    info "ok $dest"
    return 0
  fi

  if [[ -e $dest || -L $dest ]]; then
    backup_path "$dest"
  fi

  if (( DRY_RUN )); then
    printf '[dry-run] link %s -> %s\n' "$dest" "$src"
    return 0
  fi

  mkdir -p -- "$(dirname -- "$dest")"
  rm -rf -- "$dest"
  ln -s -- "$src" "$dest"
  info "linked $dest -> $src"
}
