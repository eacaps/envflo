#!/usr/bin/env sh
# Test suite for envflo.
#
# Runs a set of assertions against the envflo script. The whole suite is
# executed under both bash and zsh (when available) by run_tests.sh, so this
# file is written in portable POSIX sh plus the two target shells.
#
# Each test runs envflo in a *subshell* with a dedicated temp fixture dir so
# tests never leak environment variables into one another.
#
# Usage:
#   sh  tests/test_envflo.sh         # run under the current sh
#   bash tests/test_envflo.sh
#   zsh  tests/test_envflo.sh
#   sh  tests/run_tests.sh           # run under every available shell

# --- locate the script under test -------------------------------------------
# This file lives in <repo>/tests/, the script is <repo>/envflo.
_TEST_DIR=$(cd "$(dirname "$0")" && pwd)
ENVFLO="$_TEST_DIR/../envflo"

if [ ! -f "$ENVFLO" ]; then
    printf 'FATAL: cannot find envflo at %s\n' "$ENVFLO" >&2
    exit 99
fi

# --- tiny assertion framework ------------------------------------------------
TESTS_RUN=0
TESTS_FAILED=0
CURRENT_TEST=""

# which shell are we running under (for the summary line)
_detect_shell() {
    if [ -n "$ZSH_VERSION" ]; then printf 'zsh'
    elif [ -n "$BASH_VERSION" ]; then printf 'bash'
    else printf 'sh'
    fi
}
RUNNER_SHELL=$(_detect_shell)

# start a named test
it() {
    CURRENT_TEST="$1"
    TESTS_RUN=$((TESTS_RUN + 1))
}

_fail() {
    TESTS_FAILED=$((TESTS_FAILED + 1))
    printf '  [FAIL] (%s) %s\n' "$RUNNER_SHELL" "$CURRENT_TEST" >&2
    printf '         %s\n' "$1" >&2
}

_pass() {
    printf '  [ok]   (%s) %s\n' "$RUNNER_SHELL" "$CURRENT_TEST"
}

# assert_eq <expected> <actual> [message]
assert_eq() {
    if [ "$1" = "$2" ]; then
        _pass
    else
        _fail "${3:-assertion failed}: expected [$1], got [$2]"
    fi
}

# assert_empty <value> [message]
assert_empty() {
    if [ -z "$1" ]; then
        _pass
    else
        _fail "${2:-expected empty}: got [$1]"
    fi
}

# assert_contains <haystack> <needle> [message]
assert_contains() {
    case "$1" in
        *"$2"*) _pass ;;
        *) _fail "${3:-expected to contain}: [$2] not found in [$1]" ;;
    esac
}

# --- fixtures ----------------------------------------------------------------
# make_fixture creates a fresh temp dir populated with the standard test files
# and echoes its path.
make_fixture() {
    _dir=$(mktemp -d "${TMPDIR:-/tmp}/envflo_fix.XXXXXX")
    cat > "$_dir/.env" <<'EOF'
# base config
APP_NAME=cosmos
SHARED=from_base
BASE_ONLY=yes
EOF
    cat > "$_dir/.env.local" <<'EOF'
SHARED=from_base_local
LOCAL_ONLY=local_val
EOF
    cat > "$_dir/.env.beta" <<'EOF'
export SHARED=from_beta
BETA_ONLY="beta value with spaces"
APP_URL='https://beta.example.com'
# a comment line
EMPTY_VAL=
EOF
    cat > "$_dir/.env.beta.local" <<'EOF'
SHARED=from_beta_local
EOF
    cat > "$_dir/.env.prod" <<'EOF'
SHARED=from_prod
PROD_ONLY=prodval
EOF
    printf '%s' "$_dir"
}

cleanup_fixture() { [ -n "$1" ] && rm -rf "$1"; }

# =============================================================================
# TESTS
# =============================================================================

# ---- overlay ordering & precedence -----------------------------------------
it "loads base .env values"
_out=$(fix=$(make_fixture); ENVFLO_DIR="$fix" . "$ENVFLO" beta >/dev/null 2>&1; printf '%s' "$APP_NAME"; cleanup_fixture "$fix")
assert_eq "cosmos" "$_out" "APP_NAME from .env"

it "last file wins for shared key (.env.<env>.local overrides all)"
_out=$(fix=$(make_fixture); ENVFLO_DIR="$fix" . "$ENVFLO" beta >/dev/null 2>&1; printf '%s' "$SHARED"; cleanup_fixture "$fix")
assert_eq "from_beta_local" "$_out" "SHARED precedence"

it ".env.local overrides .env"
# prod has no prod.local and doesn't set LOCAL_ONLY, so .env.local wins
_out=$(fix=$(make_fixture); ENVFLO_DIR="$fix" . "$ENVFLO" prod >/dev/null 2>&1; printf '%s' "$LOCAL_ONLY"; cleanup_fixture "$fix")
assert_eq "local_val" "$_out" "LOCAL_ONLY from .env.local"

it "env-specific value loads"
_out=$(fix=$(make_fixture); ENVFLO_DIR="$fix" . "$ENVFLO" prod >/dev/null 2>&1; printf '%s' "$PROD_ONLY"; cleanup_fixture "$fix")
assert_eq "prodval" "$_out" "PROD_ONLY from .env.prod"

# ---- parsing ----------------------------------------------------------------
it "double-quoted value with spaces is preserved, quotes stripped"
_out=$(fix=$(make_fixture); ENVFLO_DIR="$fix" . "$ENVFLO" beta >/dev/null 2>&1; printf '%s' "$BETA_ONLY"; cleanup_fixture "$fix")
assert_eq "beta value with spaces" "$_out" "BETA_ONLY quoted"

it "single-quoted value has quotes stripped"
_out=$(fix=$(make_fixture); ENVFLO_DIR="$fix" . "$ENVFLO" beta >/dev/null 2>&1; printf '%s' "$APP_URL"; cleanup_fixture "$fix")
assert_eq "https://beta.example.com" "$_out" "APP_URL single-quoted"

it "export-prefixed line is parsed"
# .env.beta has 'export SHARED=from_beta'; it's later overridden, so instead
# assert the key exists by checking a value that is only reachable if parsing
# the export line succeeded (SHARED becomes from_beta before .local overrides).
# Simpler: make a tiny fixture with only an export line.
_out=$(
    d=$(mktemp -d "${TMPDIR:-/tmp}/envflo_exp.XXXXXX")
    printf 'export ONLY_EXPORT=hi\n' > "$d/.env"
    ENVFLO_DIR="$d" . "$ENVFLO" beta >/dev/null 2>&1
    printf '%s' "$ONLY_EXPORT"
    rm -rf "$d"
)
assert_eq "hi" "$_out" "export prefix stripped"

it "comment lines are ignored"
_out=$(
    d=$(mktemp -d "${TMPDIR:-/tmp}/envflo_cmt.XXXXXX")
    printf '# just a comment\nREAL=1\n' > "$d/.env"
    ENVFLO_DIR="$d" . "$ENVFLO" beta >/dev/null 2>&1
    printf '%s' "$REAL"
    rm -rf "$d"
)
assert_eq "1" "$_out" "comment ignored, REAL set"

it "empty value is allowed"
_out=$(fix=$(make_fixture); ENVFLO_DIR="$fix" . "$ENVFLO" beta >/dev/null 2>&1; printf '[%s]' "$EMPTY_VAL"; cleanup_fixture "$fix")
assert_eq "[]" "$_out" "EMPTY_VAL empty"

# ---- clean switch (unset between env changes) -------------------------------
it "switching env unsets vars from the previous env"
_out=$(
    fix=$(make_fixture)
    . "$ENVFLO" >/dev/null 2>&1  # no-op warm-up to be safe
    ENVFLO_DIR="$fix" . "$ENVFLO" beta >/dev/null 2>&1
    ENVFLO_DIR="$fix" . "$ENVFLO" prod >/dev/null 2>&1
    printf '[%s]' "$BETA_ONLY"   # beta-only var must be gone
    cleanup_fixture "$fix"
)
assert_eq "[]" "$_out" "BETA_ONLY unset after switch to prod"

it "switching env applies the new env's values"
_out=$(
    fix=$(make_fixture)
    ENVFLO_DIR="$fix" . "$ENVFLO" beta >/dev/null 2>&1
    ENVFLO_DIR="$fix" . "$ENVFLO" prod >/dev/null 2>&1
    printf '%s' "$SHARED"
    cleanup_fixture "$fix"
)
assert_eq "from_prod" "$_out" "SHARED is prod after switch"

it "base vars remain set after switch (not treated as env-specific)"
_out=$(
    fix=$(make_fixture)
    ENVFLO_DIR="$fix" . "$ENVFLO" beta >/dev/null 2>&1
    ENVFLO_DIR="$fix" . "$ENVFLO" prod >/dev/null 2>&1
    printf '%s' "$BASE_ONLY"
    cleanup_fixture "$fix"
)
assert_eq "yes" "$_out" "BASE_ONLY still set"

# ---- ENVFLO_ENV bookkeeping -------------------------------------------------
it "ENVFLO_ENV reflects the active environment"
_out=$(fix=$(make_fixture); ENVFLO_DIR="$fix" . "$ENVFLO" prod >/dev/null 2>&1; printf '%s' "$ENVFLO_ENV"; cleanup_fixture "$fix")
assert_eq "prod" "$_out" "ENVFLO_ENV=prod"

# ---- return codes -----------------------------------------------------------
it "returns 2 and prints usage when no arg given"
_rc=$(
    fix=$(make_fixture)
    ENVFLO_DIR="$fix" . "$ENVFLO" >/dev/null 2>&1
    printf '%s' "$?"
    cleanup_fixture "$fix"
)
assert_eq "2" "$_rc" "no-arg return code"

it "no-arg output lists available environments"
_out=$(
    fix=$(make_fixture)
    ENVFLO_DIR="$fix" . "$ENVFLO" 2>&1 >/dev/null
    cleanup_fixture "$fix"
)
assert_contains "$_out" "beta" "lists beta"

it "no-arg output lists prod too"
_out=$(
    fix=$(make_fixture)
    ENVFLO_DIR="$fix" . "$ENVFLO" 2>&1 >/dev/null
    cleanup_fixture "$fix"
)
assert_contains "$_out" "prod" "lists prod"

it "no-arg does NOT list the .local overlay as an environment"
_out=$(
    fix=$(make_fixture)
    ENVFLO_DIR="$fix" . "$ENVFLO" 2>&1 >/dev/null
    cleanup_fixture "$fix"
)
# "local" should not appear as a standalone listed env line ("  local")
case "$_out" in
    *"  local"*) _fail "'.env.local' wrongly listed as an environment" ;;
    *) _pass ;;
esac

it "returns 1 when no files exist for the directory"
_rc=$(
    d=$(mktemp -d "${TMPDIR:-/tmp}/envflo_empty.XXXXXX")
    ENVFLO_DIR="$d" . "$ENVFLO" beta >/dev/null 2>&1
    printf '%s' "$?"
    rm -rf "$d"
)
assert_eq "1" "$_rc" "missing-files return code"

it "empty dir with no arg reports none found, returns 2"
_out=$(
    d=$(mktemp -d "${TMPDIR:-/tmp}/envflo_empty2.XXXXXX")
    ENVFLO_DIR="$d" . "$ENVFLO" 2>&1 >/dev/null
    rm -rf "$d"
)
assert_contains "$_out" "no environment files" "empty-dir message"

# --- summary -----------------------------------------------------------------
printf '\n(%s) %d run, %d failed\n' "$RUNNER_SHELL" "$TESTS_RUN" "$TESTS_FAILED"

[ "$TESTS_FAILED" -eq 0 ]
