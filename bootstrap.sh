#!/usr/bin/env bash
#
# bootstrap.sh - install or update ubuntu-shortcuts without cloning the repo.
#
# Downloads a GitHub tarball, installs it under
# ~/.local/share/ubuntu-shortcuts, then runs the repo's install.sh.
#
# Usage:
#   curl -fsSL .../bootstrap.sh | bash
#   curl -fsSL .../bootstrap.sh | bash -s -- --provision
#   ./bootstrap.sh --from .          # local directory or tarball (testing/offline)
#   ./bootstrap.sh --ref v1.0.0      # pin a branch or tag
#   ./bootstrap.sh --uninstall
#
# Options:
#   --provision     Run setup.sh first (apt packages, Oh My Zsh, SDKMAN!, Docker)
#   --uninstall     Remove the installed links (does not delete the payload)
#   --ref <ref>     Branch or tag to download (default: main)
#   --repo <slug>   GitHub owner/repo (default: rishabhsingh2305/ubuntu-shortcuts)
#   --from <path>   Use a local directory or tarball instead of downloading
#   --dir <path>    Install root (default: ~/.local/share/ubuntu-shortcuts)
#   -h, --help      Show this help

set -euo pipefail

REPO_SLUG=${UBUNTU_SHORTCUTS_REPO:-rishabhsingh2305/ubuntu-shortcuts}
REF=${UBUNTU_SHORTCUTS_REF:-main}
INSTALL_ROOT=${UBUNTU_SHORTCUTS_HOME:-${XDG_DATA_HOME:-$HOME/.local/share}/ubuntu-shortcuts}
PROVISION=0
UNINSTALL=0
FROM=""
TMP_DIR=""

info() {
  printf '[info] %s\n' "$*"
}

die() {
  printf '[error] %s\n' "$*" >&2
  exit 1
}

usage() {
  cat <<'EOF'
bootstrap.sh - install ubuntu-shortcuts without cloning

Usage:
  curl -fsSL .../bootstrap.sh | bash
  curl -fsSL .../bootstrap.sh | bash -s -- --provision
  ./bootstrap.sh [options]

Options:
  --provision     Run setup.sh first (apt, Oh My Zsh, SDKMAN!, Docker)
  --uninstall     Remove the installed links (does not delete the payload)
  --ref <ref>     Branch or tag to download (default: main)
  --repo <slug>   GitHub owner/repo (default: rishabhsingh2305/ubuntu-shortcuts)
  --from <path>   Use a local directory or tarball instead of downloading
  --dir <path>    Install root (default: ~/.local/share/ubuntu-shortcuts)
  -h, --help      Show this help

The payload is installed without .git. Re-run this command to update.
For --provision, download the script first so sudo/chsh can use the terminal:
  curl -fsSL .../bootstrap.sh -o /tmp/bootstrap.sh && bash /tmp/bootstrap.sh --provision
EOF
}

cleanup() {
  if [[ -n ${TMP_DIR:-} ]]; then
    rm -rf -- "$TMP_DIR"
  fi
}
trap cleanup EXIT

while (( $# > 0 )); do
  case $1 in
    --provision)
      PROVISION=1
      ;;
    --uninstall)
      UNINSTALL=1
      ;;
    --ref)
      [[ $# -ge 2 ]] || die "--ref needs a value"
      REF=$2
      shift
      ;;
    --repo)
      [[ $# -ge 2 ]] || die "--repo needs a value"
      REPO_SLUG=${2#https://github.com/}
      REPO_SLUG=${REPO_SLUG#git@github.com:}
      REPO_SLUG=${REPO_SLUG%.git}
      REPO_SLUG=${REPO_SLUG%/}
      shift
      ;;
    --from)
      [[ $# -ge 2 ]] || die "--from needs a path"
      FROM=$2
      shift
      ;;
    --dir)
      [[ $# -ge 2 ]] || die "--dir needs a path"
      INSTALL_ROOT=$2
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      die "Unknown option: $1 (try --help)"
      ;;
  esac
  shift
done

if (( UNINSTALL )); then
  [[ -f "$INSTALL_ROOT/install.sh" ]] ||
    die "No installed copy at $INSTALL_ROOT"
  exec bash "$INSTALL_ROOT/install.sh" --uninstall
fi

if [[ -z $FROM ]]; then
  command -v curl >/dev/null 2>&1 || die "curl is required"
fi
command -v tar >/dev/null 2>&1 || die "tar is required"

TMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/ubuntu-shortcuts.XXXXXX")
SRC_DIR=""
ARCHIVE=""

if [[ -n $FROM ]]; then
  if [[ -d $FROM ]]; then
    SRC_DIR=$(cd -- "$FROM" && pwd -P)
  elif [[ -f $FROM ]]; then
    ARCHIVE=$FROM
  else
    die "--from path not found: $FROM"
  fi
else
  ARCHIVE="$TMP_DIR/repo.tar.gz"
  branch_url="https://github.com/$REPO_SLUG/archive/refs/heads/$REF.tar.gz"
  tag_url="https://github.com/$REPO_SLUG/archive/refs/tags/$REF.tar.gz"

  info "downloading $REPO_SLUG@$REF"
  if ! curl -fsSL "$branch_url" -o "$ARCHIVE"; then
    info "branch '$REF' not found; trying tag '$REF'"
    curl -fsSL "$tag_url" -o "$ARCHIVE"
  fi
fi

if [[ -n $ARCHIVE ]]; then
  mkdir -p -- "$TMP_DIR/src"
  tar -xzf "$ARCHIVE" -C "$TMP_DIR/src"

  # GitHub archives normally contain a single top-level directory. Find the
  # directory that actually holds zsh/autoload.zsh rather than assuming it.
  if [[ -f "$TMP_DIR/src/zsh/autoload.zsh" ]]; then
    SRC_DIR="$TMP_DIR/src"
  else
    shopt -s nullglob
    for candidate in "$TMP_DIR/src"/*/; do
      if [[ -f "$candidate/zsh/autoload.zsh" ]]; then
        SRC_DIR=${candidate%/}
        break
      fi
    done
    shopt -u nullglob
  fi
fi

[[ -n $SRC_DIR ]] || die "could not locate the payload"
[[ -f "$SRC_DIR/zsh/autoload.zsh" ]] ||
  die "payload does not look like ubuntu-shortcuts: $SRC_DIR"
[[ -f "$SRC_DIR/install.sh" ]] || die "payload is missing install.sh"
[[ -f "$SRC_DIR/lib/common.sh" ]] || die "payload is missing lib/common.sh"

# Stage the payload, excluding local secrets and git metadata.
STAGING="$TMP_DIR/payload"
mkdir -p -- "$STAGING"
tar -C "$SRC_DIR" \
  --exclude='.git' \
  --exclude='.env' \
  --exclude='docker/mysql/.env' \
  -cf - . | tar -C "$STAGING" -xf -

# Preserve the generated MySQL password file across updates.
ENV_BACKUP=""
if [[ -f "$INSTALL_ROOT/docker/mysql/.env" ]]; then
  ENV_BACKUP="$TMP_DIR/mysql.env"
  cp -a -- "$INSTALL_ROOT/docker/mysql/.env" "$ENV_BACKUP"
fi

OLD="$INSTALL_ROOT.old.$$"
if [[ -e $OLD ]]; then
  rm -rf -- "$OLD"
fi
if [[ -e $INSTALL_ROOT ]]; then
  mv -- "$INSTALL_ROOT" "$OLD"
fi

mkdir -p -- "$(dirname -- "$INSTALL_ROOT")"
if ! mv -- "$STAGING" "$INSTALL_ROOT"; then
  if [[ -e $OLD ]]; then
    mv -- "$OLD" "$INSTALL_ROOT"
  fi
  die "failed to install the payload"
fi

if [[ -n $ENV_BACKUP ]]; then
  mkdir -p -- "$INSTALL_ROOT/docker/mysql"
  cp -a -- "$ENV_BACKUP" "$INSTALL_ROOT/docker/mysql/.env"
  chmod 600 -- "$INSTALL_ROOT/docker/mysql/.env"
fi
rm -rf -- "$OLD"

chmod +x -- "$INSTALL_ROOT/install.sh" "$INSTALL_ROOT/setup.sh" 2>/dev/null || true

if (( PROVISION )); then
  info "provisioning and installing from $INSTALL_ROOT"
  "$INSTALL_ROOT/setup.sh"
else
  info "installing from $INSTALL_ROOT"
  "$INSTALL_ROOT/install.sh"
fi
