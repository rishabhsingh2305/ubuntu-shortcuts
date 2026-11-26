# ubuntu-shortcuts

Personal Ubuntu setup, kept in git. The repository is the **source of truth**:
a development machine can symlink the checkout into Oh My Zsh, while any other
machine can bootstrap the same files from a tarball without git.

## What it manages

- `zsh/functions/` — one file per command, autoloaded automatically
- `zsh/aliases.zsh` — aliases, including `caffinate` → `caffeinate`
- `zsh/autoload.zsh` — discovers functions and sets up `$fpath`
- `docker/kafka/compose.yml` — local Kafka + Zookeeper
- `docker/mysql/compose.yml` — local MySQL (passwords come from `.env`)
- `bootstrap.sh` — no-clone tarball installer
- `setup.sh` — fresh-machine provisioning
- `install.sh` — idempotent linker for a checkout or installed payload

## Quick start

### New machine (no clone)

```bash
curl -fsSL https://raw.githubusercontent.com/rishabhsingh2305/ubuntu-shortcuts/main/bootstrap.sh \
  -o /tmp/ubuntu-shortcuts-bootstrap.sh
bash /tmp/ubuntu-shortcuts-bootstrap.sh --provision
exec zsh
```

Downloading first keeps the terminal available for the `sudo`/`chsh` prompts in
the provisioning step. `bootstrap.sh` uses `curl` + `tar`, not git.
`--provision` still installs git as part of the base developer packages. It
downloads a tarball into `~/.local/share/ubuntu-shortcuts`, installs the zsh
config, and runs the package setup (Oh My Zsh, SDKMAN!, Docker). Run it as your
normal user, not with `sudo`; log out and back in after it finishes so the
Docker group applies.

### Existing machine or update

```bash
curl -fsSL https://raw.githubusercontent.com/rishabhsingh2305/ubuntu-shortcuts/main/bootstrap.sh | bash
exec zsh
```

Re-running the same command refreshes the payload and preserves
`docker/mysql/.env`. Pin a tag if you want reproducible installs:

```bash
curl -fsSL .../bootstrap.sh | bash -s -- --ref v1.0.0
```

### Development machine (edit and commit)

```bash
git clone git@github.com:rishabhsingh2305/ubuntu-shortcuts.git
cd ubuntu-shortcuts
./install.sh
exec zsh
```

This is the live-symlink mode: edit files in the repo, `exec zsh`, commit.

Both modes create the same two links:

```
~/.oh-my-zsh/custom/autoload.zsh  -> <checkout-or-payload>/zsh/autoload.zsh
~/.oh-my-zsh/custom/aliases.zsh   -> <checkout-or-payload>/zsh/aliases.zsh
```

Everything else (functions, compose files) is discovered from the linked
payload at shell startup.

## Layout

```
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

## How loading works

Oh My Zsh sources every `$ZSH_CUSTOM/*.zsh` file. `autoload.zsh` resolves its
own real path (even through the symlink), prepends `zsh/functions/` to
`$fpath`, and registers every file as an autoloaded function:

```zsh
typeset -g UBUNTU_SHORTCUTS_ROOT="${${(%):-%x}:A:h:h}"
fpath=("$UBUNTU_SHORTCUTS_ROOT/zsh/functions" $fpath)
for _fn in "$UBUNTU_SHORTCUTS_ROOT"/zsh/functions/*(N.); do
  autoload -Uz -- "${_fn:t}"
done
```

The practical result: **filename == command name**. There is no registry to
update when adding a command.

## Daily workflow: keeping improvements tracked

This is the loop this repo is designed for:

1. Try something in the shell.
2. If it is worth keeping, put it in the repo:
   - **command** → `zsh/functions/<name>`
   - **alias** → one line in `zsh/aliases.zsh`
   - **service** → `docker/<service>/compose.yml`
3. Run `exec zsh` (new functions/aliases are picked up from the symlinked
   directory; no reinstall is needed).
4. Test it.
5. `git add` / `git commit`.

This workflow applies to the development clone. On machines installed with
`bootstrap.sh`, push the commit from the development clone and re-run the
bootstrap command to refresh their payload.

For example, the `caffinate` typo alias was added like this:

```zsh
# zsh/aliases.zsh
alias caffinate='caffeinate'
```

No installer run, no edit to `.zshrc`, no generated registry.

### Adding a function

```bash
cat > zsh/functions/mycmd <<'EOF'
mycmd() {
  emulate -L zsh
  echo "hello from mycmd"
}
EOF
exec zsh
mycmd
```

### Adding a service

Add `docker/<name>/compose.yml`, then add functions that call:

```zsh
_ubuntu_shortcuts_compose <name> up -d
```

## caffeinate

`zsh/functions/caffeinate` keeps the laptop awake through lid close. It is
autoloaded, so it behaves like a normal command:

```bash
caffeinate 45m          # 45 minutes
caffeinate 2h           # 2 hours
caffeinate -d 2h        # background, stop with caffeinate off
caffeinate status       # show active sessions and remaining time
caffeinate off          # stop all sessions
caffeinate help
```

A bare number means minutes. `caffinate` is an alias for the command because
that is the typo I keep making.

Notes:

- Requires systemd; GNOME idle inhibition is used when available.
- No sudo and no permanent system changes.
- `/usr/bin/caffeinate` also exists (from the Caffeine package). The zsh
  function intentionally shadows it. Use `command caffeinate …` to call the
  system binary.
- To remove it: `caffeinate off`, delete `zsh/functions/caffeinate`, run
  `./install.sh`, and `exec zsh`.

## Docker services

```bash
kafka_up                # foreground; use kafka_up -d for background
kafka_down
kafka_logs
kafka_producer <topic>
kafka_consumer <topic>
kafka_create_topic <topic>

sql_start               # start the mysql service
sql                     # open a mysql shell (prompts for the root password)
sql_stop
```

- Kafka uses `docker/kafka/compose.yml`.
- MySQL uses `docker/mysql/compose.yml`. The installer creates
  `docker/mysql/.env` with generated passwords the first time; that file is
  gitignored. Edit it if you want to choose your own. Set `MYSQL_DATABASE`
  there too if you want the container to create a different initial database.
- If you reuse an existing MySQL data volume, the password in `.env` must match
  the one the volume was initialized with.
- `kafka_start` is for a native apt/service Kafka install, separate from the
  Docker workflow.
- `aql_*` assumes an existing `aerospike` container; this repo does not define
  an Aerospike compose file yet. Put machine-specific helpers in `local.zsh`.

## Machine-local overrides

Anything host-specific or secret belongs in:

```text
~/.config/ubuntu-shortcuts/local.zsh
```

`autoload.zsh` sources it after the repo functions if it exists. It is never
committed. Example:

```zsh
alias work='cd ~/work/project'
export KAFKA_HOME="$HOME/tools/kafka"
```

## Installer

### No-clone bootstrap

```bash
./bootstrap.sh                  # install/update from the GitHub tarball
./bootstrap.sh --provision      # packages, Oh My Zsh, SDKMAN!, Docker, then config
./bootstrap.sh --ref v1.0.0     # pin a branch or tag
./bootstrap.sh --from ./path    # local directory or tarball (offline/testing)
./bootstrap.sh --uninstall      # remove the links; keep the payload
```

- Downloads a tarball; does **not** run `git clone`.
- Installs the payload at `~/.local/share/ubuntu-shortcuts`.
- Re-run it to update; `docker/mysql/.env` is preserved.
- The payload is intentionally not a git checkout. Use the checkout mode below
  when you want to edit and commit.
- `bootstrap.sh` executes code downloaded from GitHub. Inspect it first or pin a
  tag with `--ref` if you want a reproducible install.

### Checkout

```bash
./install.sh                 # zsh + docker
./install.sh zsh             # only zsh
./install.sh --dry-run       # show actions, change nothing
./install.sh --uninstall     # remove repo-owned links; restore latest backup
```

- `install.sh` expects a checkout or an installed payload; use
  `bootstrap.sh` when there is neither. It deliberately has no clone/copy mode.
- Never uses `sudo` for files under `$HOME`.
- Existing files are backed up to
  `~/.local/state/ubuntu-shortcuts/backups/<timestamp>/` before replacement.
- Re-running is a no-op.
- Set `ZSH_CUSTOM=/path/to/custom` before running if you moved Oh My Zsh's
  custom directory; the default is `~/.oh-my-zsh/custom`.

## Tests

```bash
./test/lint.sh            # bash/zsh syntax, shellcheck, compose config
./test/install_test.sh    # isolated $HOME; dry run, idempotency, migration, uninstall
./test/bootstrap_test.sh  # no-clone directory/tarball install, .env preservation, uninstall
```

CI runs all three on every push and pull request.

## Not managed (yet)

`~/.zshrc` still initializes NVM, conda, zoxide, pnpm, Go and the opencode
`PATH`. Those are tool-generated or machine-specific, so they stay out of this
repo for now; stable additions can go in `local.zsh`. `setup.sh` installs the
base packages, Oh My Zsh, SDKMAN!, Docker, and this repo's zsh config.

## A note on secrets

The old `docker/mysql/compose.yml` contained a hard-coded root password. It has
been removed from the current file and replaced by a gitignored `.env`. The
old value still exists in git history — rotate it if it was ever used on a
machine that matters.
