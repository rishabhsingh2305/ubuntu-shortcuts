# ubuntu-shortcuts: zsh entrypoint (symlinked into $ZSH_CUSTOM).
#
# This file is sourced automatically by Oh My Zsh because it lives in
# $ZSH_CUSTOM/*.zsh. It does two things:
#   1. Discover every function in zsh/functions/ and autoload it.
#   2. Source machine-local overrides that are not part of the repo.

# Resolve the repo root even though this file is a symlink.
typeset -g UBUNTU_SHORTCUTS_ROOT="${${(%):-%x}:A:h:h}"
if [[ ! -d "$UBUNTU_SHORTCUTS_ROOT/zsh/functions" ]]; then
  # Fallback for shells where %x is not the sourced file.
  UBUNTU_SHORTCUTS_ROOT="${${0:A}:h:h}"
fi
export UBUNTU_SHORTCUTS_ROOT

# Filename == command name. Add a file, get a command; no registry update.
if (( ${fpath[(Ie)$UBUNTU_SHORTCUTS_ROOT/zsh/functions]} == 0 )); then
  fpath=("$UBUNTU_SHORTCUTS_ROOT/zsh/functions" $fpath)
fi

for _ubuntu_shortcuts_fn in "$UBUNTU_SHORTCUTS_ROOT"/zsh/functions/*(N.); do
  autoload -Uz -- "${_ubuntu_shortcuts_fn:t}"
done
unset _ubuntu_shortcuts_fn

# Machine-local escape hatch. Never committed; safe for work-specific helpers.
_ubuntu_shortcuts_local="${XDG_CONFIG_HOME:-$HOME/.config}/ubuntu-shortcuts/local.zsh"
if [[ -f $_ubuntu_shortcuts_local ]]; then
  source "$_ubuntu_shortcuts_local"
fi
unset _ubuntu_shortcuts_local
