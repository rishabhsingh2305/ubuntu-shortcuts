#!/usr/bin/env bash
#
# Isolated installer test. Uses a throwaway $HOME so it never touches the
# real shell configuration. Run: ./test/install_test.sh

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
TMP=$(mktemp -d "${TMPDIR:-/tmp}/ubuntu-shortcuts-test.XXXXXX")
trap 'rm -rf -- "$TMP"' EXIT

export HOME="$TMP"
export ZSH_CUSTOM="$TMP/.oh-my-zsh/custom"
mkdir -p -- "$ZSH_CUSTOM"

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

# Dry-run must not create links.
"$ROOT/install.sh" --dry-run zsh >/dev/null
[[ ! -e $ZSH_CUSTOM/autoload.zsh ]] || fail "dry-run created autoload.zsh"
[[ ! -e $ZSH_CUSTOM/aliases.zsh ]] || fail "dry-run created aliases.zsh"

# Legacy installer line must be disabled exactly once.
# shellcheck disable=SC2016  # write the literal source line into .zshrc
printf 'source "$HOME/.my_zsh_functions"\n' > "$HOME/.zshrc"

# Simulate the old caffeinate file living in the OMZ custom directory.
mkdir -p "$ZSH_CUSTOM/functions"
printf '# old caffeinate\n' > "$ZSH_CUSTOM/functions/caffeinate"

# First install, then a second run that must be a no-op.
"$ROOT/install.sh" zsh >/dev/null
grep -q '^# \[ubuntu-shortcuts\] source' "$HOME/.zshrc" ||
  fail "legacy .my_zsh_functions line was not disabled"
[[ ! -e $ZSH_CUSTOM/functions/caffeinate ]] ||
  fail "old custom caffeinate was not migrated"
find "$HOME/.local/state/ubuntu-shortcuts/backups" -name caffeinate | grep -q . ||
  fail "old custom caffeinate was not backed up"
zshrc_before=$(sha256sum "$HOME/.zshrc")
"$ROOT/install.sh" zsh >/dev/null
[[ $(sha256sum "$HOME/.zshrc") == "$zshrc_before" ]] ||
  fail "second run modified .zshrc again"

[[ -L $ZSH_CUSTOM/autoload.zsh ]] || fail "autoload.zsh is not a symlink"
[[ -L $ZSH_CUSTOM/aliases.zsh ]] || fail "aliases.zsh is not a symlink"
[[ $(readlink -f -- "$ZSH_CUSTOM/autoload.zsh") == "$ROOT/zsh/autoload.zsh" ]] ||
  fail "autoload.zsh points at the wrong place"

result=$(zsh -dfc '
  source "$ZSH_CUSTOM/autoload.zsh"
  source "$ZSH_CUSTOM/aliases.zsh"
  for cmd in caffeinate caffinate killport kafka_up sql gemini; do
    whence -w "$cmd" >/dev/null || exit 1
  done
  alias caffinate >/dev/null || exit 1
  caffeinate help >/dev/null || exit 1
  print ok
')
[[ $result == ok ]] || fail "zsh smoke test failed: $result"

# Uninstall removes the links and restores the pre-install files.
"$ROOT/install.sh" --uninstall >/dev/null
[[ ! -L $ZSH_CUSTOM/autoload.zsh ]] || fail "uninstall left autoload.zsh"
[[ ! -L $ZSH_CUSTOM/aliases.zsh ]] || fail "uninstall left aliases.zsh"

printf 'install test passed\n'
