#!/usr/bin/env bash
#
# Isolated bootstrap test: installs from a local directory and a local
# tarball, without git or network. Run: ./test/bootstrap_test.sh

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
TMP=$(mktemp -d "${TMPDIR:-/tmp}/ubuntu-shortcuts-bootstrap.XXXXXX")
trap 'rm -rf -- "$TMP"' EXIT

export HOME="$TMP/home"
export ZSH_CUSTOM="$HOME/.oh-my-zsh/custom"
INSTALL_ROOT="$HOME/.local/share/ubuntu-shortcuts"
mkdir -p -- "$ZSH_CUSTOM"

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

# Directory mode.
"$ROOT/bootstrap.sh" --from "$ROOT" >/dev/null

[[ -f $INSTALL_ROOT/zsh/autoload.zsh ]] || fail "payload is missing"
[[ ! -e $INSTALL_ROOT/.git ]] || fail "payload contains .git"
[[ -L $ZSH_CUSTOM/autoload.zsh ]] || fail "autoload.zsh is not a symlink"
[[ -L $ZSH_CUSTOM/aliases.zsh ]] || fail "aliases.zsh is not a symlink"
[[ $(readlink -f -- "$ZSH_CUSTOM/autoload.zsh") == "$INSTALL_ROOT/zsh/autoload.zsh" ]] ||
  fail "autoload.zsh points at the wrong place"

env_file="$INSTALL_ROOT/docker/mysql/.env"
[[ -f $env_file ]] || fail "MySQL .env was not created"
[[ -f $INSTALL_ROOT/docker/mysql/.env.example ]] || fail "MySQL .env.example was lost"
[[ $(stat -c %a "$env_file") == 600 ]] || fail "MySQL .env is not mode 600"
env_before=$(sha256sum "$env_file")

# Re-running must keep the generated MySQL secrets.
"$ROOT/bootstrap.sh" --from "$ROOT" >/dev/null
[[ $(sha256sum "$env_file") == "$env_before" ]] || fail "MySQL .env changed on update"

result=$(zsh -dfc '
  source "$ZSH_CUSTOM/autoload.zsh"
  source "$ZSH_CUSTOM/aliases.zsh"
  for cmd in caffeinate caffinate killport kafka_up sql gemini; do
    whence -w "$cmd" >/dev/null || exit 1
  done
  caffeinate help >/dev/null
  print ok
')
[[ $result == ok ]] || fail "zsh smoke test failed: $result"

# GitHub-style tarball mode (one top-level directory).
mkdir -p -- "$TMP/archive/ubuntu-shortcuts-main"
tar -C "$ROOT" \
  --exclude='.git' \
  --exclude='.env' \
  --exclude='docker/mysql/.env' \
  -cf - . | tar -C "$TMP/archive/ubuntu-shortcuts-main" -xf -
tar -czf "$TMP/payload.tar.gz" -C "$TMP/archive" ubuntu-shortcuts-main

"$ROOT/bootstrap.sh" --from "$TMP/payload.tar.gz" >/dev/null
[[ -f $INSTALL_ROOT/zsh/autoload.zsh ]] || fail "tarball update removed the payload"
[[ $(sha256sum "$env_file") == "$env_before" ]] || fail "tarball update changed MySQL .env"

# Uninstall must remove the links but keep the payload.
"$ROOT/bootstrap.sh" --uninstall >/dev/null
[[ ! -L $ZSH_CUSTOM/autoload.zsh ]] || fail "uninstall left autoload.zsh"
[[ ! -L $ZSH_CUSTOM/aliases.zsh ]] || fail "uninstall left aliases.zsh"
[[ -f $INSTALL_ROOT/install.sh ]] || fail "uninstall deleted the payload"

printf 'bootstrap test passed\n'
