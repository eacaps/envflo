#!/usr/bin/env sh
# Run the envflo test suite under every shell we care about (bash and zsh),
# so portability regressions between the two are caught automatically.
#
# Usage:
#   sh tests/run_tests.sh
#
# Exit status is non-zero if the suite fails under any shell.

_DIR=$(cd "$(dirname "$0")" && pwd)
SUITE="$_DIR/test_envflo.sh"

OVERALL=0
RAN_ANY=0

for sh_bin in bash zsh; do
    if command -v "$sh_bin" >/dev/null 2>&1; then
        RAN_ANY=1
        printf '==================== %s ====================\n' "$sh_bin"
        if "$sh_bin" "$SUITE"; then
            :
        else
            OVERALL=1
        fi
        printf '\n'
    else
        printf '(skipping %s — not installed)\n\n' "$sh_bin"
    fi
done

if [ "$RAN_ANY" -eq 0 ]; then
    printf 'No target shells (bash/zsh) found.\n' >&2
    exit 99
fi

if [ "$OVERALL" -eq 0 ]; then
    printf 'ALL SHELLS PASSED\n'
else
    printf 'SOME TESTS FAILED\n' >&2
fi

exit "$OVERALL"
