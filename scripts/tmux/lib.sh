# Shared setup for the tmux tutorial scripts (mbs-function-tutorial.sh and
# mbs-transport-function-tutorial.sh). Not meant to be run directly.
#
# Expects the caller to have set SCRIPT_DIR to its own directory before
# sourcing this file, e.g.:
#   SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
#   source "$SCRIPT_DIR/../lib.sh"

if [ -z "$BASH_VERSION" ]; then
    echo "This script requires bash. Run it as: bash $0" >&2
    exit 1
fi

# User-specific overrides (see local.env.example for the full list of
# variables the caller may set before this point).
LOCAL_ENV="$SCRIPT_DIR/../local.env"
if [[ -f "$LOCAL_ENV" ]]; then
    echo "Loading local overrides from $LOCAL_ENV"
    if ! source "$LOCAL_ENV"; then
        echo "Error: failed to load $LOCAL_ENV (check it for shell syntax errors)." >&2
        exit 1
    fi
else
    echo "No $LOCAL_ENV found; using built-in default paths (see local.env.example)."
fi
