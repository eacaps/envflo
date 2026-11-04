# envflo

Load environment-specific `.env` files into your **current shell**, following the
[dotenv-flow](https://github.com/kerimdzhanov/dotenv-flow) overlay convention.

```sh
envflo beta
```

loads, in order (later files override earlier ones):

```
.env  →  .env.local  →  .env.beta  →  .env.beta.local
```

and `export`s the resulting variables into your current shell session. Switching
environments (`envflo prod` after `envflo beta`) first unsets the variables the
previous environment set, so you never carry stale values between environments.

Works in both **zsh** and **bash**.

---

## Why it must be sourced (and why it's not a `PATH` executable)

A program on your `PATH` runs in a **child process**, and a child process cannot
modify its parent shell's environment — so any variables it exports vanish when it
exits. `envflo` therefore runs *inside* your shell as a **function** that `source`s
the script. That's why installation adds a small wrapper function to your shell rc
rather than dropping an executable on your `PATH`.

---

## Install

### Option 1 — curl (quick)

```sh
curl -fsSL https://raw.githubusercontent.com/eacaps/envflo/main/install.sh | sh
```

Then restart your shell (or `source ~/.zshrc`).

### Option 2 — manual

Clone the repo and run the installer:

```sh
git clone https://github.com/eacaps/envflo.git
cd envflo
sh install.sh
```

Or do it entirely by hand — copy `envflo` somewhere stable and add a wrapper
function to your shell rc:

```sh
mkdir -p ~/.local/share/envflo
cp envflo ~/.local/share/envflo/envflo

# add to ~/.zshrc (or ~/.bashrc):
envflo() { source "$HOME/.local/share/envflo/envflo" "$@"; }
```

Restart your shell afterward.

### Installer options

| Variable        | Effect                                                            |
|-----------------|-------------------------------------------------------------------|
| `ENVFLO_PREFIX` | Install directory (default `${XDG_DATA_HOME:-$HOME/.local/share}/envflo`) |
| `ENVFLO_RC`     | rc file to modify (default: auto-detected from `$SHELL`)          |
| `ENVFLO_NO_RC=1`| Install the script but don't touch any rc file                    |

The installer is idempotent — re-running it replaces its managed block in your rc
rather than duplicating it. The block is delimited by:

```sh
# >>> envflo >>>
...
# <<< envflo <<<
```

---

## Usage

Run with no argument to list the environments discovered from `.env.*` files in the
current directory:

```sh
$ envflo
envflo: usage: source envflo <environment>
envflo: available environments in .:
  beta
  prod
```

Load an environment:

```sh
$ envflo beta
envflo: loaded "beta" (APP_NAME SHARED BETA_ONLY ...)
```

Switch environments (previous env's variables are unset first):

```sh
$ envflo prod
envflo: loaded "prod" (APP_NAME SHARED PROD_ONLY ...)
```

### Environment variables set by envflo

| Variable      | Meaning                                                     |
|---------------|-------------------------------------------------------------|
| `ENVFLO_ENV`  | The name of the currently loaded environment                |
| `ENVFLO_KEYS` | Newline-separated list of keys envflo set (used for cleanup) |
| `ENVFLO_DIR`  | **Input:** directory to read `.env*` files from (default `.`) |

Load files from a different directory:

```sh
ENVFLO_DIR=./config envflo beta
```

---

## File format

Simple `KEY=value` lines. Supported:

- Blank lines and `#` comments are ignored.
- An optional leading `export ` is tolerated: `export KEY=value`.
- Surrounding single or double quotes are stripped: `KEY="a value"` → `a value`.
- Empty values are allowed: `KEY=`.

Not supported (kept intentionally simple): variable interpolation (`${OTHER}`),
multi-line values, and inline comments after a value.

---

## Precedence

For `envflo <env>`, files are loaded in this order; the **last** file to set a key
wins:

1. `.env`              — committed base defaults
2. `.env.local`        — your machine-local base overrides (gitignored)
3. `.env.<env>`        — committed environment defaults
4. `.env.<env>.local`  — your machine-local environment overrides (gitignored)

Missing files are simply skipped.

> Convention: commit `.env` and `.env.<env>` as non-secret defaults, and keep
> secrets only in the `*.local` overlays. Add `*.local` to your `.gitignore` so
> machine-local overrides and credentials are never committed.

---

## Development / tests

The test suite is pure shell (no external dependencies) and runs under both bash
and zsh:

```sh
sh tests/run_tests.sh
```

It verifies overlay ordering, `.local` precedence, quote/comment/export parsing,
clean unset-on-switch, environment discovery, and exit codes — under each shell —
so portability regressions between bash and zsh are caught automatically.
