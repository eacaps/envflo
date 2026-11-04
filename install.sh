#!/usr/bin/env sh
# envflo installer.
#
# Installs the envflo script to an XDG data directory and adds a small wrapper
# function to your shell rc so you can run `envflo <environment>` from anywhere.
#
# Usage (from a clone):
#   sh install.sh
#
# Usage (remote):
#   curl -fsSL https://raw.githubusercontent.com/eacaps/envflo/main/install.sh | sh
#
# Environment overrides:
#   ENVFLO_PREFIX   install dir (default: ${XDG_DATA_HOME:-$HOME/.local/share}/envflo)
#   ENVFLO_RC       rc file to modify (default: auto-detected from $SHELL)
#   ENVFLO_NO_RC=1  install the script but do NOT touch any rc file

set -eu

REPO_RAW_URL="https://raw.githubusercontent.com/eacaps/envflo/main/envflo"

# --- resolve install location -----------------------------------------------
PREFIX="${ENVFLO_PREFIX:-${XDG_DATA_HOME:-$HOME/.local/share}/envflo}"
TARGET="$PREFIX/envflo"

# --- obtain the script -------------------------------------------------------
# Prefer a local copy sitting next to this installer (clone / downloaded repo);
# otherwise download it.
SELF_DIR=$(cd "$(dirname "$0")" 2>/dev/null && pwd || printf '')
SRC=""
if [ -n "$SELF_DIR" ] && [ -f "$SELF_DIR/envflo" ]; then
    SRC="$SELF_DIR/envflo"
fi

mkdir -p "$PREFIX"

if [ -n "$SRC" ]; then
    printf 'envflo: installing from local copy %s\n' "$SRC"
    cp "$SRC" "$TARGET"
else
    printf 'envflo: downloading from %s\n' "$REPO_RAW_URL"
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL "$REPO_RAW_URL" -o "$TARGET"
    elif command -v wget >/dev/null 2>&1; then
        wget -qO "$TARGET" "$REPO_RAW_URL"
    else
        printf 'envflo: need curl or wget to download the script\n' >&2
        exit 1
    fi
fi

printf 'envflo: installed to %s\n' "$TARGET"

# --- optionally wire up the shell rc ----------------------------------------
if [ "${ENVFLO_NO_RC:-0}" = "1" ]; then
    printf 'envflo: ENVFLO_NO_RC set; skipping rc modification.\n'
    printf 'envflo: add this line to your shell rc manually:\n'
    printf '    envflo() { source "%s" "$@"; }\n' "$TARGET"
    exit 0
fi

# detect the rc file if not overridden
detect_rc() {
    if [ -n "${ENVFLO_RC:-}" ]; then
        printf '%s' "$ENVFLO_RC"
        return
    fi
    case "${SHELL:-}" in
        *zsh)  printf '%s' "$HOME/.zshrc" ;;
        *bash)
            # macOS login shells read .bash_profile; Linux reads .bashrc.
            if [ -f "$HOME/.bashrc" ]; then printf '%s' "$HOME/.bashrc"
            else printf '%s' "$HOME/.bash_profile"; fi
            ;;
        *)     printf '%s' "$HOME/.profile" ;;
    esac
}

RC_FILE=$(detect_rc)

BEGIN_MARK="# >>> envflo >>>"
END_MARK="# <<< envflo <<<"

# the wrapper function: resolved to an absolute path at install time
RC_SNIPPET=$(cat <<EOF
$BEGIN_MARK
# Loads environment-specific .env files into the current shell.
# Usage: envflo <environment>
envflo() { source "$TARGET" "\$@"; }
$END_MARK
EOF
)

touch "$RC_FILE"

# idempotent: if our marker block is already present, replace it; else append.
if grep -qF "$BEGIN_MARK" "$RC_FILE" 2>/dev/null; then
    printf 'envflo: updating existing block in %s\n' "$RC_FILE"
    # delete the old block (from BEGIN to END inclusive) via a temp file
    tmp=$(mktemp "${TMPDIR:-/tmp}/envflo_rc.XXXXXX")
    awk -v b="$BEGIN_MARK" -v e="$END_MARK" '
        $0 == b {skip=1}
        skip==0 {print}
        $0 == e {skip=0}
    ' "$RC_FILE" > "$tmp"
    printf '%s\n' "$RC_SNIPPET" >> "$tmp"
    cat "$tmp" > "$RC_FILE"
    rm -f "$tmp"
else
    printf 'envflo: adding wrapper function to %s\n' "$RC_FILE"
    printf '\n%s\n' "$RC_SNIPPET" >> "$RC_FILE"
fi

printf '\nenvflo: done. Restart your shell or run:\n'
printf '    source %s\n' "$RC_FILE"
printf '\nThen use it like:\n'
printf '    envflo              # list available environments\n'
printf '    envflo beta         # load .env -> .env.local -> .env.beta -> .env.beta.local\n'
