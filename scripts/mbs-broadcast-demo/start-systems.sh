#!/bin/bash
# Brings up every system the bypass demo needs, and stops there: no MBS User Service and no
# Ingest Session are created. Those are the content provider's own act, so they are made in the
# rt-mbs-application-provider UI, by loading a template -- see templates/README.md.
#
# Use this when you want to drive provisioning yourself, try different content, or demonstrate
# what the provider does. start-bypass-live.sh is the same bring-up with the service and session
# created for you, for when you just want the video running.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
BYPASS_PROVISION=0 exec ./start-bypass-live.sh "$@"
