<h1 align="center">ubuntu-shortcuts</h1>

<p align="center">
  <strong>A reproducible Ubuntu setup for zsh, Docker services, and the commands I use every day.</strong>
</p>

<p align="center">
  <a href="https://github.com/rishabhsingh2305/ubuntu-shortcuts/actions/workflows/ci.yml"><img src="https://github.com/rishabhsingh2305/ubuntu-shortcuts/actions/workflows/ci.yml/badge.svg?branch=main" alt="CI"></a>
  <img src="https://img.shields.io/badge/Ubuntu-22.04%20%7C%2024.04-E95420?logo=ubuntu&amp;logoColor=white" alt="Ubuntu 22.04 and 24.04">
  <img src="https://img.shields.io/badge/shell-zsh-4EAA25" alt="zsh">
  <img src="https://img.shields.io/badge/Docker-compose-2496ED?logo=docker&amp;logoColor=white" alt="Docker Compose">
</p>

<p align="center">
  <a href="#quick-start">Quick start</a> ·
  <a href="#whats-inside">What's inside</a> ·
  <a href="#how-it-works">How it works</a> ·
  <a href="#daily-workflow">Daily workflow</a> ·
  <a href="#command-reference">Command reference</a> ·
  <a href="#troubleshooting">Troubleshooting</a>
</p>

---

This repo started as a hand-written set of zsh functions and has grown into the
single source of truth for my Ubuntu machines. A development machine symlinks
the checkout into Oh My Zsh; any other machine installs a tarball without
cloning. Adding a command is one file — there is no registry to update.

## Quick start

### Fresh machine

```bash
curl -fsSL https://raw.githubusercontent.com/rishabhsingh2305/ubuntu-shortcuts/main/bootstrap.sh \
  -o /tmp/ubuntu-shortcuts-bootstrap.sh

bash /tmp/ubuntu-shortcuts-bootstrap.sh --provision
exec zsh
```

`--provision` installs the base packages, Oh My Zsh, SDKMAN!, and Docker, then
applies the zsh configuration. Run it as your normal user, not with `sudo`.
Log out and back in afterwards so the Docker group applies.

### Update an installed machine

```bash
curl -fsSL https://raw.githubusercontent.com/rishabhsingh2305/ubuntu-shortcuts/main/bootstrap.sh | bash
exec zsh
```

The payload is refreshed in place. `docker/mysql/.env` is preserved.

### Work on the config itself

```bash
git clone git@github.com:rishabhsingh2305/ubuntu-shortcuts.git
cd ubuntu-shortcuts
./install.sh
exec zsh
```

This is live-symlink mode: edit files in the checkout, `exec zsh`, and commit.

> **No clone required on normal machines.** `bootstrap.sh` uses `curl` + `tar`.
> `install.sh` is only for a checkout or an already-installed payload.

## What's inside

| Area | What you get |
|---|---|
| **Shell** | One file per command, autoloaded from `zsh/functions/` |
| **Aliases** | `caffinate` → `caffeinate`, plus space for your own |
| **Keep-awake** | `caffeinate` — lid-close/sleep inhibition with durations and status |
| **Kafka** | Compose stack plus producer, consumer, topic, logs, and lifecycle helpers |
| **MySQL** | Compose service with generated secrets and a `sql` shell shortcut |
| **Setup** | `bootstrap.sh` (no clone), `setup.sh` (provisioning), `install.sh` (linker) |
| **Safety** | Idempotent installs, timestamped backups, isolated tests, CI |

## How it works

Two files in Oh My Zsh's custom directory are symlinked to the repo:

```text
~/.oh-my-zsh/custom/autoload.zsh  ──►  <repo>/zsh/autoload.zsh
~/.oh-my-zsh/custom/aliases.zsh   ──►  <repo>/zsh/aliases.zsh
```

`autoload.zsh` resolves its own real path (even through the symlink), adds
`zsh/functions/` to `$fpath`, and registers every file as a command:

```zsh
typeset -g UBUNTU_SHORTCUTS_ROOT="${${(%):-%x}:A:h:h}"
fpath=("$UBUNTU_SHORTCUTS_ROOT/zsh/functions" $fpath)

for _fn in "$UBUNTU_SHORTCUTS_ROOT"/zsh/functions/*(N.); do
  autoload -Uz -- "${_fn:t}"
done
```

**Filename == command name.** Drop in `zsh/functions/mycmd`, start a new shell,
and `mycmd` exists. No generated registry, no `.zshrc` edits.

## Daily workflow

```bash
# 1. Add a command
cat > zsh/functions/mycmd <<'EOF'
mycmd() {
  emulate -L zsh
  echo "hello from mycmd"
}
EOF

# 2. Reload and test
exec zsh
mycmd

# 3. Track it
git add zsh/functions/mycmd
git commit -m "feat: add mycmd"
```

Adding an alias is one line:

```zsh
# zsh/aliases.zsh
alias gs='git status --short'
```

On machines installed with `bootstrap.sh`, push the commit and re-run the
bootstrap command to refresh their payload.

## Command reference

### caffeinate

```bash
caffeinate 45m          # keep awake for 45 minutes
caffeinate 2h           # 2 hours
caffeinate -d 2h        # background; stop with `caffeinate off`
caffeinate status       # active sessions and remaining time
caffeinate off          # stop everything
caffeinate help
```

A bare number means minutes. `caffinate` is an alias for the typo I keep making.

| Note | Detail |
|---|---|
| Requirements | systemd; GNOME idle inhibition when available |
| Privileges | No sudo and no permanent system changes |
| Name collision | `/usr/bin/caffeinate` also exists; the zsh function shadows it. Use `command caffeinate` for the system binary. |
| Removal | `caffeinate off`, delete `zsh/functions/caffeinate`, run `./install.sh`, `exec zsh` |

### Kafka

| Command | Purpose |
|---|---|
| `kafka_up` | Start the stack in the foreground (`kafka_up -d` for background) |
| `kafka_down` | Stop and remove the stack |
| `kafka_logs` | Follow logs |
| `kafka_producer <topic>` | Open the console producer |
| `kafka_consumer <topic>` | Read a topic from the beginning |
| `kafka_create_topic <topic>` | Create a topic |
| `kafka_start` | Start a native apt/service Kafka install (not the Docker stack) |

Kafka CLI commands use `${KAFKA_HOME:-/opt/kafka}` and
`${KAFKA_BOOTSTRAP_SERVERS:-localhost:9092}`.

### MySQL

| Command | Purpose |
|---|---|
| `sql_start` | Start the Compose service |
| `sql` | Open a MySQL shell (prompts for the root password) |
| `sql_stop` | Stop the service |

The first install generates `docker/mysql/.env` with random passwords. The file
is gitignored. If you reuse an existing data volume, its password must match
the one in `.env`. Set `MYSQL_DATABASE` there to change the initial database.

### Installer

| Command | Purpose |
|---|---|
| `./bootstrap.sh` | Install or update from the GitHub tarball |
| `./bootstrap.sh --provision` | Also run the fresh-machine package setup |
| `./bootstrap.sh --ref v1.0.0` | Pin a branch or tag |
| `./bootstrap.sh --from ./path` | Install from a local directory or tarball |
| `./bootstrap.sh --uninstall` | Remove links; keep the payload |
| `./install.sh` | Link a checkout or installed payload (`zsh` + `docker`) |
| `./install.sh zsh` | Link only the zsh config |
| `./install.sh --dry-run` | Show actions without changing anything |
| `./install.sh --uninstall` | Remove repo-owned links; restore the latest backup |

`install.sh` never uses `sudo` for files under `$HOME`. Existing files are
backed up to `~/.local/state/ubuntu-shortcuts/backups/<timestamp>/` first.
Set `ZSH_CUSTOM=/path/to/custom` if you moved Oh My Zsh's custom directory.

## Configuration

Machine-specific or secret configuration belongs in:

```text
~/.config/ubuntu-shortcuts/local.zsh
```

It is sourced after the repo functions when it exists and is never committed:

```zsh
alias work='cd ~/work/project'
export KAFKA_HOME="$HOME/tools/kafka"
```

### Not managed yet

`~/.zshrc` still initializes NVM, conda, zoxide, pnpm, Go, and the opencode
`PATH`. These are tool-generated or machine-specific, so they stay out of this
repo for now. Stable additions can move into `local.zsh`.

`aql_*` assumes an existing `aerospike` container; this repo does not yet define
an Aerospike Compose file.

## Testing

| Script | Covers |
|---|---|
| `./test/lint.sh` | Bash/zsh syntax, shellcheck, Compose config |
| `./test/install_test.sh` | Isolated `$HOME`, dry run, idempotency, migration, uninstall |
| `./test/bootstrap_test.sh` | No-clone directory/tarball install, `.env` preservation, uninstall |

CI runs all three on every push and pull request.

## Troubleshooting

| Symptom | Fix |
|---|---|
| `caffeinate: command not found` | `exec zsh`; check `whence -w caffeinate` and the two custom symlinks |
| `caffinate` is not an alias | Check `~/.oh-my-zsh/custom/aliases.zsh` points at the repo |
| Docker permission denied | Log out and back in, or run `newgrp docker` |
| `docker compose` unavailable | Install `docker-compose-v2` (or use the v1 fallback) |
| MySQL access denied | Make `docker/mysql/.env` match the password used by the existing volume |
| `bootstrap.sh` returns 404 | Push the branch/tag, or pass the correct `--ref` |
| Push asks for a password | Use an SSH remote, `gh auth setup-git`, or a PAT |
| Shell startup errors | Run `zsh -n zsh/autoload.zsh zsh/aliases.zsh zsh/functions/*` |

## Repository layout

<details>
<summary>Show the full tree</summary>

```text
.
├── bootstrap.sh                # no-clone tarball installer
├── install.sh                  # safe, rerunnable linker
├── setup.sh                    # fresh Ubuntu provisioning
├── lib/common.sh               # backup/link helpers
├── zsh/
│   ├── autoload.zsh            # fpath + autoload + local overrides
│   ├── aliases.zsh             # alias definitions
│   └── functions/              # filename == command name
│       ├── caffeinate
│       ├── killport
│       ├── kafka_up
│       ├── kafka_down
│       ├── kafka_logs
│       ├── kafka_producer
│       ├── kafka_consumer
│       ├── kafka_create_topic
│       ├── sql
│       ├── sql_start
│       ├── sql_stop
│       ├── aql_start
│       ├── aql_restart
│       ├── aql_stop
│       ├── gemini
│       ├── setjava8
│       ├── runjava8app
│       ├── _docker_compose
│       └── _ubuntu_shortcuts_compose
├── docker/
│   ├── kafka/compose.yml
│   └── mysql/compose.yml
└── test/
    ├── bootstrap_test.sh
    ├── install_test.sh
    └── lint.sh
```

</details>

## Security notes

- `docker/mysql/.env` is generated locally and gitignored.
- The old hard-coded MySQL password was removed from the current file, but it
  remains in git history. Rotate it if it was ever used on a machine that matters.
- `bootstrap.sh` executes code downloaded from GitHub. Inspect it first or pin a
  tag with `--ref` for a reproducible install.
- `install.sh` does not use `sudo`; it writes to the checkout/payload,
  `$ZSH_CUSTOM`, `.zshrc` only for the legacy migration, and the backup
  directory.
