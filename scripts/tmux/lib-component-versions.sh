# Sourced by the tutorial scripts to print, at start-up, what each component actually is.
#
# Two different things are reported per component, and they can disagree:
#
#   Checkout revision / Branch   the working tree the component is built from
#   Built binary reports         what the binary itself prints with -v, i.e. what will run
#
# A binary built before a later pull reports the older version while the checkout reports the
# newer one. Printing only the checkout hides exactly the staleness this table exists to reveal,
# which is why both columns are here rather than one.
#
# One caveat on the Built column: MBSF and MBSTF report the Open5GS framework version they were
# compiled against, not their own release, so for those two the Checkout column is the identifier
# to go by.

# The top of the git working tree containing a path, so the table does not depend on how deep a
# component's build or install directory happens to sit. Falls back to the path itself when it is
# not in a working tree, which is the case for an installed tree with no sources beside it.
repository_of() {
    git -C "${1:-.}" rev-parse --show-toplevel 2>/dev/null || printf '%s' "${1:-.}"
}

_component_version_format="%-14s  %-46s  %-32s  %-30s  %s\n"

print_component_version_header() {
    # shellcheck disable=SC2059
    printf "$_component_version_format" "Component" "Checkout revision" "Branch" "Built binary reports" "Location"
    # shellcheck disable=SC2059
    printf "$_component_version_format" "---------" "-----------------" "------" "--------------------" "--------"
}

print_component_version() {
    local name="$1"
    local repository="$2"
    local binary="${3:-}"
    local revision="not a git repository"
    local branch="-"
    local built="-"

    if git -C "$repository" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        revision=$(git -C "$repository" describe --always --dirty --tags 2>/dev/null || printf 'unknown')
        branch=$(git -C "$repository" branch --show-current 2>/dev/null)
        [[ -n "$branch" ]] || branch="detached HEAD"
    fi

    if [[ -n "$binary" ]]; then
        if [[ -x "$binary" ]]; then
            # Bounded, because this runs before the stack starts and a component that hangs on -v
            # must not stop the tutorial from coming up.
            if command -v timeout >/dev/null 2>&1; then
                built=$(timeout 5 "$binary" -v 2>&1 | head -1)
            else
                built=$("$binary" -v 2>&1 | head -1)
            fi
            [[ -n "$built" ]] || built="reported no version"
        else
            built="not built"
        fi
    fi

    # shellcheck disable=SC2059
    printf "$_component_version_format" "$name" "$revision" "$branch" "$built" "$repository"
}
