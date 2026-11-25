# Sourced by scripts/test-development-branches.sh and scripts/check-build-from-clean.sh; not run on its own.
#
# The three edits of section 5 of scripts/mbs-broadcast-demo/README.md ("Release pins and the pins for testing").
#
# What the development branches commit points at the release branches (5mbs on the forks, main on the rt-* components). The work the demo
# needs is on the development branches and not yet on the release ones, so the MBSF and the MBSTF do not compile as committed. To test the
# development branches the three wraps below are pointed at them before the build; nothing else changes.
#
#   apply_development_pins ROOT      ROOT has rt-mbs/rt-mbs-function and rt-mbs/rt-mbs-transport-function checked out
#
# Each file is reported. A wrap that holds neither the release nor the development revision stops the run (return 1): the table in the README
# no longer describes it, and building on regardless would test something else than what that section says.

_pin_wrap() { # file from to
    local file="$1" from="$2" to="$3"
    if [ ! -f "$file" ]; then
        echo "development pins: $file does not exist" >&2
        return 1
    elif grep -q "^revision = $from\$" "$file"; then
        sed -i "s/^revision = $from\$/revision = $to/" "$file"
        echo "pinned $file: revision $from -> $to"
    elif grep -q "^revision = $to\$" "$file"; then
        echo "pinned $file: revision $to already"
    else
        echo "development pins: $file holds neither 'revision = $from' nor 'revision = $to'; section 5 of the demo README needs updating" >&2
        return 1
    fi
}

apply_development_pins() {
    local root="$1"
    _pin_wrap "$root/rt-mbs/rt-mbs-function/subprojects/open5gs.wrap"                   5mbs 5mbs-development || return 1
    _pin_wrap "$root/rt-mbs/rt-mbs-function/subprojects/rt-5gc-service-consumers.wrap"  main development     || return 1
    _pin_wrap "$root/rt-mbs/rt-mbs-transport-function/subprojects/rt-libflute.wrap"     main development     || return 1
}
