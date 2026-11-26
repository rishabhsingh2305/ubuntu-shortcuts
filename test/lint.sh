#!/usr/bin/env bash
#
# Static checks that can run locally or in CI: ./test/lint.sh

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
cd "$ROOT"

bash -n install.sh setup.sh lib/common.sh test/*.sh
printf 'bash syntax: ok\n'

zsh -n zsh/autoload.zsh zsh/aliases.zsh zsh/functions/*
printf 'zsh syntax: ok\n'

if command -v shellcheck >/dev/null 2>&1; then
  shellcheck install.sh setup.sh lib/common.sh test/*.sh
  printf 'shellcheck: ok\n'
else
  printf 'shellcheck: not installed, skipped\n'
fi

if command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
  MYSQL_ROOT_PASSWORD=test MYSQL_PASSWORD=test \
    docker compose -f docker/mysql/compose.yml config >/dev/null
  docker compose -f docker/kafka/compose.yml config >/dev/null
  printf 'compose config: ok\n'
else
  printf 'docker compose: not available, skipped\n'
fi
